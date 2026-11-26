CREATE TABLE support_inbox_items (
  owner TEXT NOT NULL,
  message_key TEXT NOT NULL,
  queue_id INTEGER NOT NULL REFERENCES queue_items(id),
  PRIMARY KEY (owner, message_key)
) WITHOUT ROWID;
