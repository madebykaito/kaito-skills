CREATE TABLE IF NOT EXISTS jobs (
  ref TEXT PRIMARY KEY,
  digest TEXT NOT NULL,
  body TEXT NOT NULL,
  signature TEXT NOT NULL,
  due_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'queued',
  claimed_at INTEGER,
  prepared_at INTEGER,
  prepared_id TEXT,
  prepared_until INTEGER,
  remote_id TEXT
);
CREATE INDEX IF NOT EXISTS jobs_due ON jobs (state, due_at);
