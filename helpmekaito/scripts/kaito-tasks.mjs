// The node side of kaito-tasks.sh: picks the provider for MGR and runs one command.
// Env from the shell: M (memory dir), D (task folder), B (board id), S (project slug), MGR (provider name).
// Local writes hold tasks/.<slug>.lock, never across a fetch.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { D, M, MGR, ctx, die, one, openItems, taskFiles } from './providers/lib.mjs';

const [cmd, ...args] = process.argv.slice(2);
if (!/^[a-z]+$/.test(MGR || '')) die(`bad manager ${MGR ?? ''}`);
const P = (await import(`./providers/${MGR}.mjs`)).default;
ctx.P = P;

function list() {
  const ts = taskFiles(D).filter((t) => !P.isDone(t));
  if (P.remote && !existsSync(D)) console.error('no cache yet: run kaito-tasks.sh pull');
  for (const t of ts) console.log(`${t.meta.id} ${P.where(t)} ${one(t.meta.title)} (${openItems(t.body)} open)`);
}

// Before a pull: re-read the structure when the stored map is stale. Only boards the user consented to; a failure never blocks the pull.
async function freshen() {
  if (!P.commands.discover) return;
  let map;
  try { map = JSON.parse(readFileSync(join(M, 'managers', `${MGR}.json`), 'utf8')); } catch { return; }  // never discovered: leave it to onboarding
  // Consent lists boards of every manager; refresh only the ones this manager's map already holds.
  const ids = (process.env.KAITO_DISCOVER_IDS || '').split(/\s+/).filter((id) => id && Object.hasOwn(map.boards || {}, id));
  const at = Date.parse(map.generated_at);
  const ttl = Number(process.env.KAITO_TTL_HOURS) > 0 ? Number(process.env.KAITO_TTL_HOURS) : 24;
  if (!ids.length || !at || Date.now() - at < ttl * 3600e3) return;
  const log = console.log; console.log = () => {};
  try { await P.commands.discover(ids); } catch { console.error('warning: could not refresh the board structure; using the stored one'); } finally { console.log = log; }
}

try {
  if (cmd === 'pull') await freshen();
  if (cmd === 'list') list();
  else if (cmd === 'op') await P.op(args[0], args.slice(1));
  else if (Object.hasOwn(P.commands, cmd ?? '')) await P.commands[cmd](args);
  else die(`unknown command ${cmd}`);
} catch (e) {
  console.error(`kaito-tasks: ${P.redact ? P.redact(e.message) : e.message}`);
  process.exit(1);
}
