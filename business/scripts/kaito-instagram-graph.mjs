import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { EXIT, Fail, fail, readOwner } from './kaito-ledger-lib.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const GRAPH_VERSION = 'v27.0';
const META_ORIGINS = ['https://graph.instagram.com', 'https://graph.facebook.com'];
const isLoopback = (url) => ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
export const isId = (value) => typeof value === 'string' && /^\d+$/.test(value);
export const expandHome = (value) => value.startsWith('~/') ? path.join(homedir(), value.slice(2)) : value;

function businessCommand(command, args, env = process.env) {
  return spawnSync(process.execPath, [path.join(HERE, command), ...args], {
    encoding: 'utf8', env, maxBuffer: 4 * 1024 * 1024,
  });
}

// Use the same owner selection and approval gates as other business commands.
export function instagramOwner(id) {
  const r = businessCommand('kaito-owner.mjs', ['resolve', ...(id ? ['--owner', id] : [])]);
  if (r.status !== 0) fail(r.status ?? EXIT.error, r.stderr?.trim() || r.stdout?.trim() || 'Instagram owner resolution failed');
  const owner = r.stdout.match(/^owner=(.+)$/m)?.[1];
  const record = readOwner(owner);
  if (typeof record?.channels?.instagram !== 'string' || !record.channels.instagram) {
    fail(EXIT.human, 'Set channels.instagram in this owner record');
  }
  return { ...record, account: record.channels.instagram };
}

export function ledger(args, json = false) {
  const r = businessCommand('kaito-ledger.mjs', json ? [...args, '--json'] : args);
  if (r.status !== 0) fail(r.status ?? EXIT.error, r.stderr?.trim() || r.stdout?.trim() || 'Instagram ledger command failed');
  return json ? JSON.parse(r.stdout) : r.stdout;
}

export class GraphError extends Fail {
  constructor(status, graphError) {
    const code = Number.isInteger(graphError?.code) ? graphError.code : null;
    const subcode = Number.isInteger(graphError?.error_subcode) ? graphError.error_subcode : null;
    const details = [status && `HTTP ${status}`, code !== null && `code ${code}`, subcode !== null && `subcode ${subcode}`].filter(Boolean);
    super(EXIT.error, details.length ? `Graph API ${details.join(' ')}` : 'Graph API did not return a response');
    this.subcode = subcode;
    this.notEnoughStoryViewers = code === 10 && /not enough viewers/i.test(graphError.message);
    this.definitive = code !== null && status >= 400 && status < 500 && status !== 408 && status !== 429
      && graphError.is_transient !== true && ![1, 2, 4, 17, 32, 613, 80002].includes(code);
  }
}

export const boundedSignal = (ms, parent) => parent ? AbortSignal.any([parent, AbortSignal.timeout(ms)]) : AbortSignal.timeout(ms);

export function safeUrl(value) {
  let url;
  try { url = new URL(value); } catch { return null; }
  return url.username || url.password || url.hash ? null : url;
}

export async function instagramGraph(owner, signal, { verifyAccount = true } = {}) {
  const keyPath = owner.keys?.instagram;
  if (typeof keyPath !== 'string' || !path.isAbsolute(expandHome(keyPath))) {
    fail(EXIT.human, 'Set keys.instagram to the absolute path of the Instagram key file in owner.json');
  }
  const key = expandHome(keyPath);
  const pick = businessCommand('kaito-engines.mjs', ['pick', 'publish-instagram', '--owner', owner.id, '--allow-cloud', '--json'],
    { ...process.env, INSTAGRAM_KEY_FILE: key });
  if (pick.status === EXIT.human) fail(EXIT.human, 'Instagram Graph needs owner consent in kaito-engines');
  if (pick.status !== 0 || JSON.parse(pick.stdout).provider !== 'instagram-graph') {
    fail(pick.status || EXIT.notFound, 'Instagram Graph provider or key file unavailable');
  }

  let config;
  try { config = JSON.parse(readFileSync(key, 'utf8')); } catch { fail(EXIT.error, 'Cannot read the Instagram key file as JSON'); }
  if (!isId(config?.ig_user_id) || typeof config.access_token !== 'string' || !/^[\x21-\x7e]+$/.test(config.access_token)) {
    fail(EXIT.error, 'Instagram key file needs ig_user_id (a string) and access_token');
  }

  const base = safeUrl(config.graph_url ?? META_ORIGINS[0]);
  const local = !!base && isLoopback(base) && ['http:', 'https:'].includes(base.protocol);
  if (!base || base.pathname !== '/' || base.search || (!local && !META_ORIGINS.includes(base.origin))) {
    fail(EXIT.error, 'Instagram Graph URL must be a Meta Graph origin or loopback');
  }
  const version = config.graph_version ?? GRAPH_VERSION;
  if (typeof version !== 'string' || !/^v\d+\.\d+$/.test(version)) fail(EXIT.error, 'Invalid Instagram Graph version');
  const id = config.ig_user_id;

  async function request(edge, params = {}, method = 'GET') {
    const url = new URL(`/${version}/${edge}`, base);
    if (method === 'GET') url.search = new URLSearchParams(params).toString();
    let response, body;
    try {
      response = await fetch(url, {
        method, headers: { Authorization: `Bearer ${config.access_token}`,
          ...(method === 'POST' && { 'Content-Type': 'application/json' }) }, redirect: 'error',
        body: method === 'POST' ? JSON.stringify(params) : undefined, signal: boundedSignal(30_000, signal),
      });
      body = await response.json();
    } catch { throw new GraphError(response?.status); }
    if (!response.ok || !body || typeof body !== 'object' || body.error) throw new GraphError(response.status, body?.error);
    return body;
  }

  async function* pages(edge, params, maxPages) {
    const seen = new Set();
    let after;
    for (let page = 0; page < maxPages; page++) {
      const result = await request(edge, after ? { ...params, after } : params);
      if (!Array.isArray(result.data)) fail(EXIT.error, 'Instagram Graph returned an invalid collection');
      yield result.data;
      if (!result.paging?.next) return;
      // Rebuild the request from its cursor. A next URL can contain a token and is untrusted.
      after = result.paging.cursors?.after;
      if (typeof after !== 'string' || !after || seen.has(after)) fail(EXIT.error, 'Instagram Graph returned invalid pagination');
      seen.add(after);
    }
    fail(EXIT.human, 'Instagram Graph has more pages than the requested scan can verify');
  }

  async function checkAccount() {
    const account = await request(id, { fields: 'id,username' });
    if (account.id !== id || typeof account.username !== 'string' ||
        account.username.toLowerCase() !== owner.account.replace(/^@/, '').toLowerCase()) {
      fail(EXIT.human, 'Instagram key file does not match the owner Instagram account');
    }
  }
  if (verifyAccount) await checkAccount();

  return { id, version, upload: config.upload, local, request, pages, checkAccount };
}
