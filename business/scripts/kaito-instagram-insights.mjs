#!/usr/bin/env node
import { EXIT, fail, only, openDb, parseArgs, printKv, run } from './kaito-ledger-lib.mjs';
import { instagramOwner } from './kaito-instagram-graph.mjs';
import { instagramInsightsDaily, pullInstagramInsights } from '../handlers/instagram-insights.mjs';

const USAGE = `usage:
  kaito-instagram-insights.mjs pull [--owner <id>] [--ref <published-ref> | --limit <n>] [--json]
  kaito-instagram-insights.mjs daily --owner <id> [--json]
  kaito-instagram-insights.mjs list [--owner <id>] [--date <YYYY-MM-DD>] [--json]`;

await run(async (argv) => {
  if (argv.length === 1 && argv[0] === '--help') { console.log(USAGE); return; }
  const args = parseArgs(argv, { bool: ['json'] });
  const [cmd] = args._;
  if (args._.length !== 1) fail(EXIT.usage, USAGE);
  if (cmd === 'list') {
    only(args, ['owner', 'date', 'json']);
    if (args.date !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(args.date)) fail(EXIT.usage, 'Use --date YYYY-MM-DD');
    const owner = instagramOwner(args.owner);
    const db = openDb();
    try {
      const rows = db.prepare(`SELECT * FROM instagram_metrics WHERE owner = ? ${args.date ? 'AND snapshot_date = ?' : ''}
        ORDER BY snapshot_date DESC, scope, ig_user_id, subject_id, metric, period_end`)
        .all(owner.id, ...(args.date ? [args.date] : []));
      if (args.json) console.log(JSON.stringify(rows));
      else for (const x of rows) console.log([x.snapshot_date, x.scope, x.subject_id, x.metric, x.period, x.period_end || '-', x.value].join('\t'));
    } finally { db.close(); }
    return;
  }
  let result;
  if (cmd === 'pull') {
    only(args, ['owner', 'ref', 'limit', 'json']);
    const limit = Number(args.limit ?? 50);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 200 || (args.ref && args.limit)) {
      fail(EXIT.usage, 'Choose --ref or a --limit from 1 to 200');
    }
    result = await pullInstagramInsights({ owner: args.owner, ref: args.ref, limit });
  } else if (cmd === 'daily') {
    only(args, ['owner', 'json']);
    if (!args.owner) fail(EXIT.usage, 'daily needs --owner <id>');
    result = await instagramInsightsDaily.run({ owner: args.owner });
  } else fail(EXIT.usage, USAGE);
  if (args.json) console.log(JSON.stringify(result));
  else printKv(result);
});
