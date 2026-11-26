import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { EXIT, fail } from './kaito-ledger-lib.mjs';
import { boundedSignal, expandHome, safeUrl } from './kaito-instagram-graph.mjs';

const MAX_VIDEO = 300_000_000;
const JPEG = 'image/jpeg';
const VIDEO = 'video/mp4';

function fastStart(bytes) {
  let moov = false;
  for (let offset = 0; offset + 8 <= bytes.length;) {
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    let size = bytes.readUInt32BE(offset), header = 8;
    if (size === 1) {
      header = 16;
      if (offset + header > bytes.length) return false;
      size = Number(bytes.readBigUInt64BE(offset + 8));
    }
    if (size === 0) size = bytes.length - offset;
    if (size < header || size > bytes.length - offset) return false;
    if (type === 'mdat') return moov;
    if (type === 'moov') moov = true;
    offset += size;
  }
  return false;
}

export function mediaType(bytes, expected, kind = 'reel') {
  const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (jpeg && expected !== 'video') {
    if (bytes.length > 8_000_000) fail(EXIT.usage, 'Instagram JPEG exceeds 8 MB');
    return 'image';
  }
  if (expected === 'image') fail(EXIT.usage, 'Instagram images and covers must be JPEG');
  if (kind === 'story' && bytes.length > 100_000_000) fail(EXIT.usage, 'Instagram Story video exceeds 100 MB');
  if (bytes.length > MAX_VIDEO) fail(EXIT.usage, 'Instagram video exceeds 300 MB');
  if (!fastStart(bytes)) fail(EXIT.usage, 'Instagram video requires a MOV or MP4 with moov before mdat');

  // ffprobe needs seeking for container duration. Probe the same bytes used for upload.
  const dir = mkdtempSync(path.join(tmpdir(), 'kaito-ig-probe-'));
  try {
    const file = path.join(dir, 'video');
    writeFileSync(file, bytes, { mode: 0o600 });
    const result = spawnSync(process.env.FFPROBE_BIN || 'ffprobe', [
      '-v', 'error', '-show_entries', 'format=format_name,duration:stream=codec_type,codec_name,sample_rate', '-of', 'json', file,
    ], { encoding: 'utf8', timeout: 30_000 });
    if (result.error?.code === 'ENOENT') fail(EXIT.notFound, 'Install ffprobe or set FFPROBE_BIN');
    if (result.status !== 0) fail(EXIT.usage, 'ffprobe could not read the Instagram video');
    const { streams = [], format } = JSON.parse(result.stdout);
    const videos = streams.filter((s) => s.codec_type === 'video');
    const audio = streams.filter((s) => s.codec_type === 'audio');
    if (!format?.format_name?.split(',').includes('mp4') ||
        videos.length !== 1 || !['h264', 'hevc'].includes(videos[0].codec_name)) {
      fail(EXIT.usage, 'Instagram requires MOV or MP4 with one H.264 or HEVC stream');
    }
    if (audio.length > 1 || audio.some((s) => s.codec_name !== 'aac' || !(Number(s.sample_rate) > 0 && Number(s.sample_rate) <= 48_000))) {
      fail(EXIT.usage, 'Instagram audio must be AAC at 48 kHz or below');
    }
    const duration = Number(format.duration);
    if (!(duration >= 3 && duration <= 900)) fail(EXIT.usage, 'Instagram video must be 3 seconds to 15 minutes');
    if (kind === 'story' && duration > 60) fail(EXIT.usage, 'Instagram Story video must be at most 60 seconds');
    return 'video';
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

function uploadUrl(value, local) {
  const url = safeUrl(value);
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(url?.hostname);
  if (!url || (local ? !(loopback && ['http:', 'https:'].includes(url.protocol)) : loopback || url.protocol !== 'https:')) {
    fail(EXIT.human, 'Instagram upload URLs must be public HTTPS (loopback only in local Graph tests)');
  }
  return url;
}

async function verifyHostedBytes(url, digest, size, signal) {
  let bytes = 0;
  const hash = createHash('sha256');
  try {
    const response = await fetch(url, { redirect: 'error', signal: boundedSignal(300_000, signal) });
    if (!response.ok || !response.body) {
      await response.body?.cancel();
      fail(EXIT.error, 'Instagram media URL could not be downloaded');
    }
    for await (const part of response.body) {
      bytes += part.length;
      if (bytes > size) break;
      hash.update(part);
    }
  } catch { fail(EXIT.error, 'Instagram media URL could not be downloaded'); }
  if (bytes !== size || hash.digest('hex') !== digest) fail(EXIT.error, 'Instagram media URL returned bytes that differ from the approved media');
  return url.href;
}

export function uploadTarget(graph, digests, signal) {
  const config = graph.upload;
  if (config?.kind === 'presigned-put') {
    const entries = new Map();
    const urls = new Set();
    for (const digest of new Set(digests)) {
      const entry = config.objects?.[digest];
      if (!entry) fail(EXIT.human, 'Instagram upload target is missing a presigned object for an approved media digest');
      const put = uploadUrl(entry.put_url, graph.local);
      const get = uploadUrl(entry.read_url, graph.local);
      for (const [method, url] of [['PUT', put], ['GET', get]]) {
        const object = method + url.origin + url.pathname;
        if (urls.has(object)) fail(EXIT.human, 'Different Instagram media need distinct uploaded objects');
        urls.add(object);
      }
      entries.set(digest, { put, get });
    }
    return {
      async store(bytes, digest, type) {
        const entry = entries.get(digest);
        let response;
        try {
          response = await fetch(entry.put, {
            method: 'PUT', body: bytes, headers: { 'Content-Type': type === 'video' ? VIDEO : JPEG },
            redirect: 'error', signal: boundedSignal(300_000, signal),
          });
        } catch { fail(EXIT.error, 'Instagram media PUT did not return a response'); }
        await response.body?.cancel();
        if (!response.ok) fail(EXIT.error, `Instagram media PUT returned HTTP ${response.status}`);
        return verifyHostedBytes(entry.get, digest, bytes.length, signal);
      },
      close() {},
    };
  }
  if (config?.kind === 'tunnel') {
    const base = uploadUrl(config.base_url, graph.local);
    if (base.search || typeof config.directory !== 'string' || !path.isAbsolute(expandHome(config.directory))) {
      fail(EXIT.human, 'Instagram tunnel needs a base URL without a query and an absolute directory');
    }
    const root = expandHome(config.directory);
    if (!statSync(root, { throwIfNoEntry: false })?.isDirectory()) fail(EXIT.human, 'Instagram tunnel directory is missing');
    if (!base.pathname.endsWith('/')) base.pathname += '/';
    let dir;
    return {
      async store(bytes, digest, type) {
        dir ??= mkdtempSync(path.join(root, 'kaito-ig-'));
        const name = `${digest}.${type === 'video' ? 'mp4' : 'jpg'}`;
        const file = path.join(dir, name);
        try { writeFileSync(file, bytes, { flag: 'wx', mode: 0o600 }); }
        catch (error) { if (error.code !== 'EEXIST') fail(EXIT.error, 'Cannot write the Instagram tunnel upload'); }
        const url = new URL(`${path.basename(dir)}/${name}`, base);
        return verifyHostedBytes(url, digest, bytes.length, signal);
      },
      close() { if (dir) rmSync(dir, { recursive: true, force: true }); },
    };
  }
  fail(EXIT.human, 'Configure an Instagram presigned-put or tunnel upload target');
}
