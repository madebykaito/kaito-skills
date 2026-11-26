import { canonicalText, EXIT, fail } from './kaito-ledger-lib.mjs';
import { isId } from './kaito-instagram-graph.mjs';

export const MAX_CAROUSEL = 20;
export const kinds = ['image', 'reel', 'story', 'carousel'];
export const actionFor = (kind) => `instagram.${kind}.publish`;
export const kindOf = (action) => kinds.find((kind) => actionFor(kind) === action);

export function validatePayload(kind, options, count) {
  const { v, caption, type, location_id, collaborators, cover, thumb_offset } = options ?? {};
  if (v !== 1 || typeof caption !== 'string' || !Array.isArray(type) || !Array.isArray(collaborators)) {
    fail(EXIT.usage, 'Instagram action needs a payload made by kaito-instagram-publish.mjs propose');
  }
  if ([...caption].length > 2200 || /[\u0000-\u0009\u000b-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/u.test(caption) ||
      canonicalText(Buffer.from(caption)).toString() !== caption) {
    fail(EXIT.usage, 'Instagram caption must be canonical UTF-8, at most 2,200 characters, without control characters other than newlines');
  }
  if (location_id !== undefined && !isId(location_id)) fail(EXIT.usage, 'Instagram location ID must be numeric');
  if (collaborators.length > 3 || collaborators.some((x) => typeof x !== 'string' || !/^[A-Za-z0-9_.]{1,30}$/.test(x)) ||
      new Set(collaborators.map((x) => x.toLowerCase())).size !== collaborators.length) {
    fail(EXIT.usage, 'Give up to three distinct Instagram collaborator usernames');
  }
  if (cover !== undefined && cover !== true) fail(EXIT.usage, 'Invalid Instagram Reel cover');
  if (thumb_offset !== undefined && (!Number.isSafeInteger(thumb_offset) || thumb_offset < 0)) {
    fail(EXIT.usage, 'Instagram thumbnail offset must be a nonnegative integer in milliseconds');
  }
  if (kind !== 'reel' && (cover || thumb_offset !== undefined)) fail(EXIT.usage, 'Cover and thumbnail offset apply to Reels');
  if (cover && thumb_offset !== undefined) fail(EXIT.usage, 'Choose a cover or a thumbnail offset');
  if (kind === 'story' && (caption || location_id || collaborators.length)) {
    fail(EXIT.usage, 'Instagram Stories do not take a caption, location ID or collaborators through this API');
  }
  const min = kind === 'carousel' ? 2 : 1;
  const max = kind === 'carousel' ? MAX_CAROUSEL : 1;
  if (type.length < min || type.length > max || count !== type.length + Number(cover === true) ||
      type.some((x) => !['image', 'video'].includes(x)) ||
      (kind === 'image' && type[0] !== 'image') || (kind === 'reel' && type[0] !== 'video')) {
    fail(EXIT.usage, kind === 'carousel' ? 'Instagram carousels need 2 to 20 media items' : 'Invalid Instagram media for this post type');
  }
  if (Object.keys(options).some((key) => !['v', 'caption', 'type', 'location_id', 'collaborators', 'cover', 'thumb_offset'].includes(key))) {
    fail(EXIT.usage, 'Unsupported Instagram publish option in approved payload');
  }
  return options;
}

export function readPayload(item) {
  const kind = kindOf(item.action);
  if (!kind) fail(EXIT.usage, 'This ledger ref is not an Instagram publish action');
  let options;
  try { options = JSON.parse(Buffer.from(item.text).toString('utf8')); } catch { /* validation supplies the error */ }
  return { kind, options: validatePayload(kind, options, item.media.length) };
}
