ALTER TABLE leads ADD COLUMN updated_at TEXT;
UPDATE leads SET updated_at = coalesce(
  (SELECT max(at) FROM lead_stages WHERE lead_id = leads.id), created_at);
CREATE TRIGGER leads_timestamp_insert AFTER INSERT ON leads
WHEN NEW.updated_at IS NULL
BEGIN
  UPDATE leads SET updated_at = NEW.created_at WHERE id = NEW.id;
END;
CREATE TRIGGER leads_timestamp_update AFTER UPDATE OF name, email, company, stage ON leads
WHEN OLD.name IS NOT NEW.name OR OLD.email IS NOT NEW.email
  OR OLD.company IS NOT NEW.company OR OLD.stage IS NOT NEW.stage
BEGIN
  UPDATE leads SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TABLE twenty_leads (
  lead_id INTEGER PRIMARY KEY REFERENCES leads(id),
  remote_id TEXT NOT NULL UNIQUE
);
CREATE TABLE twenty_shadow (
  lead_id INTEGER NOT NULL REFERENCES twenty_leads(lead_id),
  field TEXT NOT NULL,
  value TEXT NOT NULL,
  local_at TEXT NOT NULL,
  remote_at TEXT NOT NULL,
  PRIMARY KEY (lead_id, field)
);
CREATE TABLE twenty_conflicts (
  id INTEGER PRIMARY KEY,
  lead_id INTEGER NOT NULL REFERENCES leads(id),
  field TEXT NOT NULL,
  previous_value TEXT,
  local_value TEXT NOT NULL,
  remote_value TEXT NOT NULL,
  local_at TEXT NOT NULL,
  remote_at TEXT NOT NULL,
  winner TEXT NOT NULL CHECK (winner IN ('local', 'remote')),
  observed_at TEXT NOT NULL,
  UNIQUE (lead_id, field, local_at, remote_at, local_value, remote_value)
);
