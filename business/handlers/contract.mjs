export const STALE_MS = 30 * 60 * 1000;

export function validId(id) {
  return typeof id === 'string' && id.length > 0 && id.length <= 256 && !/[\u0000-\u001f\u007f-\u009f]/.test(id);
}

export async function publish(handler, item, context) {
  try {
    const out = await handler.publish(item, context);
    if (['ok', 'failed', 'uncertain'].includes(out?.result) &&
        (out.remoteId == null || validId(out.remoteId))) {
      return { result: out.result, remoteId: out.remoteId ?? null,
        ...(typeof out.note === 'string' && { note: out.note }) };
    }
  } catch {
    // The platform might have accepted the send before the handler lost its response.
  }
  return { result: 'uncertain', remoteId: null };
}

export async function prepare(handler, item, context) {
  const out = await handler.prepare(item, context);
  if (!validId(out?.id) || !Number.isSafeInteger(out.expiresAt) || out.expiresAt <= context.now()) {
    throw new Error('invalid preparation');
  }
  return out;
}
