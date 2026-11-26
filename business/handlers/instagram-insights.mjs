import { EXIT, fail, isoUtc, localParts, openDb, ownerTz, tx } from '../scripts/kaito-ledger-lib.mjs';
import { GraphError, instagramGraph, instagramOwner, isId, ledger } from '../scripts/kaito-instagram-graph.mjs';
import { kindOf } from '../scripts/kaito-instagram-payload.mjs';

const MEDIA = 'views,reach,likes,comments,saved,shares,total_interactions';
const REELS = MEDIA + ',ig_reels_avg_watch_time,ig_reels_video_view_total_time';
const STORIES = 'views,reach,replies,shares,total_interactions';
const ACCOUNT_TOTALS = 'views,accounts_engaged,total_interactions,profile_links_taps,likes,comments,shares,saves';
const ACCOUNT_SERIES = 'reach';
const PAGE_SIZE = 50;

function points(response, scope, id, period, requested) {
  if (!Array.isArray(response.data)) fail(EXIT.error, 'Instagram insights response is missing its data array');
  const rows = [];
  const metrics = requested.split(',');
  for (const entry of response.data) {
    if (!metrics.includes(entry.name)) continue;
    for (const point of entry.total_value ? [entry.total_value] : entry.values ?? []) {
      if (!Number.isFinite(point.value)) continue;
      const end = Date.parse(point.end_time);
      rows.push([scope, id, entry.name, entry.period ?? period, Number.isFinite(end) ? isoUtc(end) : '', point.value]);
    }
  }
  return rows;
}

async function accountMetrics(graph, now) {
  const period = 'day';
  const query = { period, since: Math.floor((now - 2 * 86400_000) / 1000), until: Math.floor(now / 1000) };
  const rows = [];
  for (const [metric_type, metric] of [['time_series', ACCOUNT_SERIES], ['total_value', ACCOUNT_TOTALS]]) {
    const response = await graph.request(`${graph.id}/insights`, { ...query, metric_type, metric });
    rows.push(...points(response, 'account', graph.id, period, metric));
  }
  return rows;
}

async function recent(graph, edge, limit) {
  const found = new Map();
  for await (const batch of graph.pages(`${graph.id}/${edge}`, { fields: 'id,media_product_type', limit: PAGE_SIZE }, 20)) {
    for (const item of batch) {
      if (isId(item.id)) found.set(item.id, edge === 'stories' ? 'STORY' : item.media_product_type);
      if (found.size >= limit) return found;
    }
  }
  return found;
}

export async function pullInstagramInsights({ owner: ownerId, ref, limit = 50, daily = false }, { now = Date.now } = {}) {
  const owner = instagramOwner(ownerId);
  const time = now();
  const date = localParts(time, ownerTz(owner.id)).date;
  const graph = await instagramGraph(owner, AbortSignal.timeout(15 * 60_000), { verifyAccount: false });
  const db = openDb();
  try {
    if (daily && db.prepare('SELECT 1 FROM instagram_insights_runs WHERE owner = ? AND ig_user_id = ? AND snapshot_date = ?')
      .get(owner.id, graph.id, date)) return { status: 'current', date, metrics: 0, skipped: 0 };

    await graph.checkAccount();
    let media;
    if (ref) {
      const row = ledger(['status', ref], true);
      const kind = kindOf(row.action);
      if (row.owner !== owner.id || row.account !== owner.account || !kind || !isId(row.remote_id)) {
        fail(EXIT.human, 'Ref must be a published Instagram action for this owner');
      }
      media = new Map([[row.remote_id, { reel: 'REELS', story: 'STORY' }[kind] ?? 'FEED']]);
    } else {
      media = new Map([...await recent(graph, 'media', limit), ...await recent(graph, 'stories', limit)]);
    }

    let skipped = 0;
    const rows = await accountMetrics(graph, time);
    for (const [id, product] of media) {
      const metric = product === 'REELS' ? REELS : product === 'STORY' ? STORIES : MEDIA;
      try {
        const response = await graph.request(`${id}/insights`, { metric });
        rows.push(...points(response, 'media', id, 'lifetime', metric));
      } catch (error) {
        if (!(error instanceof GraphError) ||
            (error.subcode !== 2108006 && !(product === 'STORY' && error.notEnoughStoryViewers))) throw error;
        skipped++;
      }
    }
    const collected = isoUtc(time);
    tx(db, () => {
      const write = db.prepare(`INSERT INTO instagram_metrics
        (owner, ig_user_id, scope, subject_id, metric, period, period_end, value, snapshot_date, collected_at, graph_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT DO UPDATE SET value = excluded.value, collected_at = excluded.collected_at, graph_version = excluded.graph_version
          WHERE excluded.collected_at >= instagram_metrics.collected_at`);
      for (const row of rows) write.run(owner.id, graph.id, ...row, date, collected, graph.version);
      if (!ref && limit === 50) {
        db.prepare(`INSERT INTO instagram_insights_runs VALUES (?, ?, ?, ?)
          ON CONFLICT DO NOTHING`).run(owner.id, graph.id, date, collected);
      }
    });
    return { status: 'pulled', date, metrics: rows.length, skipped };
  } finally { db.close(); }
}

// A daily job calls this for a configured owner. It performs only read requests.
export const instagramInsightsDaily = { run: (item, context) => pullInstagramInsights({ owner: item.owner, daily: true }, context) };
