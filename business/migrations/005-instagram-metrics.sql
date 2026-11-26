CREATE TABLE instagram_publish_requests (
  ref TEXT PRIMARY KEY REFERENCES actions(ref),
  ig_user_id TEXT NOT NULL,
  container_id TEXT NOT NULL,
  caption_sha256 TEXT NOT NULL,
  requested_at TEXT NOT NULL
) STRICT, WITHOUT ROWID;

CREATE TABLE instagram_metrics (
  owner TEXT NOT NULL,
  ig_user_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('account', 'media')),
  subject_id TEXT NOT NULL,
  metric TEXT NOT NULL,
  period TEXT NOT NULL,
  period_end TEXT NOT NULL,
  snapshot_date TEXT NOT NULL,
  value REAL NOT NULL,
  collected_at TEXT NOT NULL,
  graph_version TEXT NOT NULL,
  PRIMARY KEY (owner, ig_user_id, scope, subject_id, metric, period, period_end, snapshot_date)
) STRICT, WITHOUT ROWID;

CREATE TABLE instagram_insights_runs (
  owner TEXT NOT NULL,
  ig_user_id TEXT NOT NULL,
  snapshot_date TEXT NOT NULL,
  collected_at TEXT NOT NULL,
  PRIMARY KEY (owner, ig_user_id, snapshot_date)
) STRICT, WITHOUT ROWID;
