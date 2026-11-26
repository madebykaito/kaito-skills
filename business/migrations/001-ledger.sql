-- Approval ledger: stored payload files, actions with their digest and state, approvals,
-- send attempts and an append-only event log. See business/references/ledger.md.

CREATE TABLE artifacts (
  sha256     TEXT PRIMARY KEY CHECK (length(sha256) = 64),
  bytes      INTEGER NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('text', 'media', 'document')),
  name       TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE actions (
  ref          TEXT PRIMARY KEY,
  owner        TEXT NOT NULL,
  account      TEXT NOT NULL,
  action       TEXT NOT NULL,
  text_sha256  TEXT REFERENCES artifacts (sha256),
  media_json   TEXT NOT NULL DEFAULT '[]',
  disclosure   TEXT NOT NULL CHECK (disclosure IN ('ai', 'none')),
  due_at       TEXT,
  payload_json TEXT NOT NULL,
  digest       TEXT NOT NULL CHECK (length(digest) = 64),
  state        TEXT NOT NULL CHECK (state IN ('proposed', 'approved', 'claimed', 'sent', 'failed', 'uncertain', 'reconciled', 'rejected', 'expired')),
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL,
  approved_at  TEXT,
  approved_via TEXT,
  remote_id    TEXT,
  note         TEXT
);
CREATE INDEX actions_owner_state ON actions (owner, state);
CREATE INDEX actions_state_due ON actions (state, due_at);

CREATE TABLE approvals (
  id           INTEGER PRIMARY KEY,
  ref          TEXT NOT NULL REFERENCES actions (ref),
  digest       TEXT NOT NULL,
  via          TEXT NOT NULL CHECK (via IN ('terminal', 'prompt')),
  at           TEXT NOT NULL,
  context_json TEXT
);

CREATE TABLE attempts (
  ref         TEXT NOT NULL REFERENCES actions (ref),
  n           INTEGER NOT NULL,
  digest      TEXT NOT NULL,
  claimed_at  TEXT NOT NULL,
  finished_at TEXT,
  result      TEXT CHECK (result IN ('ok', 'failed', 'uncertain')),
  remote_id   TEXT,
  note        TEXT,
  PRIMARY KEY (ref, n)
);
-- One attempt per ref: a ref is claimed once and never again.
CREATE UNIQUE INDEX attempts_one_per_ref ON attempts (ref);

CREATE TABLE events (
  id     INTEGER PRIMARY KEY,
  ref    TEXT,
  at     TEXT NOT NULL,
  kind   TEXT NOT NULL,
  detail TEXT
);

-- What was stored, approved and logged is never edited. These triggers stop accidental edits
-- through the ledger or a stray SQL statement; they are not a defence against someone who
-- drops them (see "Trust assumptions" in ledger.md).
CREATE TRIGGER artifacts_no_update BEFORE UPDATE ON artifacts BEGIN SELECT RAISE(ABORT, 'artifacts are immutable'); END;
CREATE TRIGGER artifacts_no_delete BEFORE DELETE ON artifacts BEGIN SELECT RAISE(ABORT, 'artifacts are immutable'); END;
CREATE TRIGGER approvals_no_update BEFORE UPDATE ON approvals BEGIN SELECT RAISE(ABORT, 'approvals are immutable'); END;
CREATE TRIGGER approvals_no_delete BEFORE DELETE ON approvals BEGIN SELECT RAISE(ABORT, 'approvals are immutable'); END;
CREATE TRIGGER events_no_update BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
CREATE TRIGGER events_no_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
CREATE TRIGGER actions_no_delete BEFORE DELETE ON actions BEGIN SELECT RAISE(ABORT, 'actions are never deleted; reject or expire them'); END;
-- INSERT OR REPLACE deletes the old row without firing delete triggers, so a second insert
-- with an existing key is refused before the conflict is resolved.
CREATE TRIGGER actions_no_replace BEFORE INSERT ON actions WHEN EXISTS (SELECT 1 FROM actions WHERE ref = NEW.ref) BEGIN SELECT RAISE(ABORT, 'actions are never replaced'); END;
CREATE TRIGGER artifacts_no_replace BEFORE INSERT ON artifacts WHEN EXISTS (SELECT 1 FROM artifacts WHERE sha256 = NEW.sha256) BEGIN SELECT RAISE(ABORT, 'artifacts are immutable'); END;
CREATE TRIGGER approvals_no_replace BEFORE INSERT ON approvals WHEN EXISTS (SELECT 1 FROM approvals WHERE id = NEW.id) BEGIN SELECT RAISE(ABORT, 'approvals are immutable'); END;
CREATE TRIGGER events_no_replace BEFORE INSERT ON events WHEN EXISTS (SELECT 1 FROM events WHERE id = NEW.id) BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
CREATE TRIGGER attempts_no_replace BEFORE INSERT ON attempts WHEN EXISTS (SELECT 1 FROM attempts WHERE ref = NEW.ref) BEGIN SELECT RAISE(ABORT, 'a ref has one attempt'); END;
CREATE TRIGGER attempts_no_delete BEFORE DELETE ON attempts BEGIN SELECT RAISE(ABORT, 'attempts are never deleted'); END;

CREATE TRIGGER actions_payload_fixed
BEFORE UPDATE OF ref, owner, account, action, text_sha256, media_json, disclosure, due_at, payload_json, digest ON actions
BEGIN SELECT RAISE(ABORT, 'an action payload is fixed once proposed; propose a new action'); END;

CREATE TRIGGER actions_state_flow
BEFORE UPDATE OF state ON actions
WHEN NOT (
     OLD.state = NEW.state
  OR (OLD.state = 'proposed'  AND NEW.state IN ('approved', 'rejected', 'expired'))
  OR (OLD.state = 'approved'  AND NEW.state IN ('claimed', 'rejected', 'expired'))
  OR (OLD.state = 'claimed'   AND NEW.state IN ('sent', 'failed', 'uncertain'))
  OR (OLD.state = 'uncertain' AND NEW.state IN ('reconciled', 'failed'))
  -- A send that reconcile marked failed and whose publisher later reported ok.
  OR (OLD.state = 'failed'    AND NEW.state = 'reconciled')
)
BEGIN SELECT RAISE(ABORT, 'illegal state change'); END;

CREATE TRIGGER actions_approval_needed
BEFORE UPDATE OF state ON actions
WHEN NEW.state = 'approved'
  AND NOT EXISTS (SELECT 1 FROM approvals WHERE ref = NEW.ref AND digest = NEW.digest)
BEGIN SELECT RAISE(ABORT, 'no approval recorded for this digest'); END;
