// The signed body is shared between Node and Workers. Ref and digest are covered on reads too.
export const MAX_BODY = 800_000;
export const LATE_MS = 24 * 60 * 60 * 1000;
export const isRef = (ref) => typeof ref === 'string' && /^act-[0-9]{8}-[0-9a-f]{8}$/.test(ref);
export const isSha = (sha) => typeof sha === 'string' && /^[0-9a-f]{64}$/.test(sha);

export function hmacKey(secret) {
  if (!isSha(secret)) throw new Error('scheduler secret must be 64 lowercase hex characters');
  const bytes = Uint8Array.from(secret.match(/../g), (hex) => parseInt(hex, 16));
  return crypto.subtle.importKey('raw', bytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

const encode = (body) => new TextEncoder().encode(body);

export async function sign(key, body) {
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, encode(body)));
  return Array.from(sig, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function verify(key, body, sig) {
  if (!isSha(sig)) return false;
  const bytes = Uint8Array.from(sig.match(/../g), (hex) => parseInt(hex, 16));
  return crypto.subtle.verify('HMAC', key, bytes, encode(body));
}

export async function readBody(request) {
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
  const reader = request.body?.getReader();
  if (!reader) throw new Error('missing body');
  let len = 0, body = '';
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) return body + decoder.decode();
      len += value.byteLength;
      if (len > MAX_BODY) throw new Error('body too large');
      body += decoder.decode(value, { stream: true });
    }
  } catch (error) {
    await reader.cancel();
    throw error;
  } finally { reader.releaseLock(); }
}
