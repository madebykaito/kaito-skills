// The node side of kaito-tasks.sh: picks the provider for MGR and runs one command.
// Env from the shell: M (memory dir), D (task folder), B (board id), S (project slug), MGR (provider name).
// Local writes hold tasks/.<slug>.lock, never across a fetch.
import { existsSync } from 'node:fs';
import { D, MGR, ctx, die, one, openItems, taskFiles } from './providers/lib.mjs';

const [cmd, ...args] = process.argv.slice(2);
if (!/^[a-z]+$/.test(MGR || '')) die(`bad manager ${MGR ?? ''}`);
const P = (await import(`./providers/${MGR}.mjs`)).default;
ctx.P = P;

function list() {
  const ts = taskFiles(D).filter((t) => !P.isDone(t));
  if (P.remote && !existsSync(D)) console.error('no cache yet: run kaito-tasks.sh pull');
  for (const t of ts) console.log(`${t.meta.id} ${P.where(t)} ${one(t.meta.title)} (${openItems(t.body)} open)`);
}

try {
  if (cmd === 'list') list();
  else if (cmd === 'op') await P.op(args[0], args.slice(1));
  else if (Object.hasOwn(P.commands, cmd ?? '')) await P.commands[cmd](args);
  else die(`unknown command ${cmd}`);
} catch (e) {
  console.error(`kaito-tasks: ${P.redact ? P.redact(e.message) : e.message}`);
  process.exit(1);
}
