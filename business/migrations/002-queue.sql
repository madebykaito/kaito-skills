-- Today queue: things the founder has to do, per owner, with a due time.
CREATE TABLE queue_items (
  id         INTEGER PRIMARY KEY,
  owner      TEXT NOT NULL,
  kind       TEXT NOT NULL,
  title      TEXT NOT NULL,
  due_at     TEXT,  -- UTC instant, for an item with a time
  due_date   TEXT,  -- calendar date in the owner's zone, for a whole-day item
  all_day    INTEGER NOT NULL DEFAULT 0 CHECK (all_day IN (0, 1)),
  ref        TEXT,
  note       TEXT,
  state      TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
  created_at TEXT NOT NULL,
  closed_at  TEXT
);
CREATE INDEX queue_owner_state_due ON queue_items (owner, state, due_at);
CREATE INDEX queue_owner_state_date ON queue_items (owner, state, due_date);
