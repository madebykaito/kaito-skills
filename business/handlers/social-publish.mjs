import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readOwner } from '../scripts/kaito-ledger-lib.mjs';

const engine = fileURLToPath(new URL('../scripts/kaito-engines.mjs', import.meta.url));
function call(script, args) {
  const p = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  if (p.status !== 0) { const e = new Error(p.stderr.trim() || p.stdout.trim() || 'command failed'); e.code = p.status || 1; throw e; }
  return p.stdout;
}

export const socialHandlers = new Map(
  ['linkedin', 'linkedin-page', 'x', 'youtube'].map(platform => [`social.${platform}.publish`, { publish }]),
);

async function publish(claimed) {
  const platform = claimed.action.split('.')[1];
  let result = 'failed';
  try {
    const payload = JSON.parse(claimed.text.toString('utf8'));
    if (!payload || typeof payload.content !== 'string' || !payload.settings || payload.settings.__type !== platform || Object.keys(payload).some(k => !['content', 'settings', 'media_names'].includes(k))) throw new Error('invalid approved post JSON');
    const allowed = { linkedin: ['__type'], 'linkedin-page': ['__type'], x: ['__type', 'who_can_reply_post', 'made_with_ai', 'paid_partnership', 'community'], youtube: ['__type', 'title', 'type', 'selfDeclaredMadeForKids', 'tags', 'made_with_ai'] };
    if (typeof payload.settings !== 'object' || Array.isArray(payload.settings) || Object.keys(payload.settings).some(k => !allowed[platform].includes(k))) throw new Error('unsupported Postiz setting');
    if (claimed.disclosure === 'ai' && (!['x', 'youtube'].includes(platform) || payload.settings.made_with_ai !== true)) throw new Error('AI disclosure requires made_with_ai=true in approved settings');
    const media = claimed.media;
    const owner = readOwner(claimed.owner);
    if (owner.channels?.[platform === 'linkedin-page' ? 'linkedin' : platform] !== claimed.account) throw new Error('account does not match owner platform');
    if (!Array.isArray(payload.media_names) && media.length || payload.media_names && (!Array.isArray(payload.media_names) || payload.media_names.length !== media.length)) throw new Error('approved media_names must match media');
    const keyPath = process.env.POSTIZ_KEY_FILE || owner.keys?.postiz;
    if (!keyPath) throw new Error('Postiz key file is missing');
    const key = readFileSync(keyPath, 'utf8').trim();
    if (!key || /[\r\n]/.test(key)) throw new Error('invalid Postiz key file');
    const pick = JSON.parse(call(engine, ['pick', 'publish-social', '--owner', claimed.owner, '--allow-cloud', '--json']));
    if (pick.provider !== 'postiz') throw new Error('Postiz is not the selected publish-social provider');
    const url = new URL(process.env.POSTIZ_URL || pick.path);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('invalid Postiz URL');
    const base = url.toString().replace(/\/$/, '');
    const request = async (route, options = {}) => {
      const response = await fetch(base + '/public/v1/' + route, { ...options, headers: { Authorization: key, ...options.headers }, signal: AbortSignal.timeout(30000), redirect: 'error' });
      if (!response.ok) { const e = new Error(`Postiz HTTP ${response.status}`); e.status = response.status; throw e; }
      return response.json();
    };
    const integrations = await request('integrations');
    if (!Array.isArray(integrations) || !integrations.some(i => i.id === claimed.account && i.identifier === platform)) throw new Error('account is not a matching Postiz integration');
    const images = [];
    for (const [index, bytes] of media.entries()) {
      const name = payload.media_names[index];
      if (typeof name !== 'string' || !/^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif|mp4|mov)$/i.test(name)) throw new Error('invalid approved media filename');
      const ext = name.split('.').pop().toLowerCase();
      const mime = ({jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',webp:'image/webp',gif:'image/gif',mp4:'video/mp4',mov:'video/quicktime'})[ext];
      const form = new FormData(); form.append('file', new Blob([bytes], { type: mime }), name);
      const uploaded = await request('upload', { method: 'POST', body: form });
      if (!uploaded.id || !uploaded.path) throw new Error('Postiz upload response lacks id or path');
      images.push({ id: uploaded.id, path: uploaded.path });
    }
    const body = { type: 'now', date: new Date().toISOString(), shortLink: false, tags: [], posts: [{ integration: { id: claimed.account }, value: [{ content: payload.content, image: images }], settings: payload.settings }] };
    result = 'uncertain';
    const response = await request('posts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const id = Array.isArray(response) ? response[0]?.postId : response?.postId;
    if (typeof id !== 'string' || !id) throw new Error('Postiz did not return a post id');
    return { result: 'ok', remoteId: id };
  } catch (e) {
    // A client error on post creation is an explicit rejection. A server error or lost response is ambiguous.
    if (result === 'uncertain' && e.status >= 400 && e.status < 500 && e.status !== 408 && e.status !== 429) result = 'failed';
    return { result, note: `Postiz ${result}` };
  }
}
