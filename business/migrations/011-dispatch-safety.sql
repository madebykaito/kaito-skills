CREATE TABLE approval_receipts (
  token_hash TEXT PRIMARY KEY,
  ref TEXT NOT NULL REFERENCES actions(ref),
  digest TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER
) STRICT, WITHOUT ROWID;

UPDATE actions SET state = 'rejected',
  note = 'Legacy host approval had no terminal receipt. Propose again for approval.',
  updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE state = 'approved' AND EXISTS (
  SELECT 1 FROM approvals WHERE approvals.ref = actions.ref AND via = 'prompt'
);

CREATE TABLE dispatch_reservations (
  ref TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  allow_cloud INTEGER NOT NULL CHECK (allow_cloud IN (0, 1)),
  consumed_at INTEGER,
  intent_at INTEGER,
  PRIMARY KEY (ref, attempt),
  FOREIGN KEY (ref, attempt) REFERENCES attempts(ref, n)
) STRICT, WITHOUT ROWID;

CREATE TABLE instagram_prepared_containers (
  ref TEXT PRIMARY KEY REFERENCES actions(ref),
  digest TEXT NOT NULL,
  account TEXT NOT NULL,
  ig_user_id TEXT NOT NULL,
  container_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;
