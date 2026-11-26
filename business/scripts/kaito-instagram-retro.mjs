export function instagramRetro(db, owner, { start, end, subject } = {}) {
  if (!db.prepare("SELECT 1 FROM sqlite_schema WHERE type='table' AND name='instagram_metrics'").get()) return null;
  const rows = db.prepare(`SELECT metric, value FROM (
      SELECT metric, value, row_number() OVER (
        PARTITION BY metric ORDER BY snapshot_date DESC, period_end DESC, collected_at DESC, subject_id
      ) AS newest
      FROM instagram_metrics WHERE owner=? AND scope=?
        AND (? IS NULL OR subject_id=?)
        AND (? IS NULL OR snapshot_date>=?) AND (? IS NULL OR snapshot_date<?)
    ) WHERE newest=1 ORDER BY metric`)
    .all(owner, subject ? 'media' : 'account', subject ?? null, subject ?? null, start ?? null, start ?? null, end ?? null, end ?? null);
  return rows.length ? Object.fromEntries(rows.map(({ metric, value }) => [metric, value])) : null;
}
