CREATE TABLE umami_metrics (
  owner TEXT NOT NULL,
  website_id TEXT NOT NULL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  stats_json TEXT NOT NULL,
  pulled_at TEXT NOT NULL,
  PRIMARY KEY (owner, website_id, start_at, end_at)
) WITHOUT ROWID;
