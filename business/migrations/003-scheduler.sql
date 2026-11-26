CREATE TABLE scheduler_claims (
  ref TEXT PRIMARY KEY REFERENCES attempts (ref),
  worker_url TEXT,
  worker_until TEXT,
  worker_accepted INTEGER NOT NULL DEFAULT 0,
  worker_done INTEGER NOT NULL DEFAULT 0,
  CHECK ((worker_url IS NULL) = (worker_until IS NULL))
) WITHOUT ROWID;

CREATE TABLE scheduler_preparations (
  ref TEXT PRIMARY KEY REFERENCES actions (ref),
  token TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  remote_id TEXT,
  expires_at INTEGER
) WITHOUT ROWID;
