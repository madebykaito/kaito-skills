CREATE TABLE money_documents (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('quote', 'invoice', 'credit')),
  previous_id TEXT UNIQUE REFERENCES money_documents(id),
  original_id TEXT REFERENCES money_documents(id),
  payload TEXT NOT NULL,
  CHECK ((kind = 'credit') = (original_id IS NOT NULL))
) WITHOUT ROWID;

CREATE TABLE money_proposals (
  ref TEXT PRIMARY KEY REFERENCES actions(ref),
  document_id TEXT NOT NULL REFERENCES money_documents(id),
  issue_date TEXT NOT NULL,
  sequence INTEGER NOT NULL CHECK (sequence > 0)
) WITHOUT ROWID;

CREATE TABLE money_issues (
  document_id TEXT PRIMARY KEY REFERENCES money_documents(id),
  ref TEXT NOT NULL UNIQUE REFERENCES money_proposals(ref),
  owner TEXT NOT NULL,
  kind TEXT NOT NULL,
  financial_year INTEGER NOT NULL,
  sequence INTEGER NOT NULL CHECK (sequence > 0),
  number TEXT NOT NULL,
  original_id TEXT UNIQUE REFERENCES money_issues(document_id),
  UNIQUE (owner, kind, financial_year, sequence)
) WITHOUT ROWID;

CREATE TABLE money_payments (
  invoice_id TEXT NOT NULL REFERENCES money_issues(document_id),
  reference TEXT NOT NULL,
  paise INTEGER NOT NULL CHECK (paise > 0),
  PRIMARY KEY (invoice_id, reference)
) WITHOUT ROWID;

CREATE TABLE money_chases (
  invoice_id TEXT PRIMARY KEY REFERENCES money_issues(document_id),
  queue_id INTEGER NOT NULL UNIQUE REFERENCES queue_items(id)
) WITHOUT ROWID;

CREATE TRIGGER money_documents_no_replace BEFORE INSERT ON money_documents
WHEN EXISTS (SELECT 1 FROM money_documents WHERE id = NEW.id OR previous_id = NEW.previous_id)
BEGIN SELECT RAISE(ABORT, 'document revision already exists'); END;
CREATE TRIGGER money_documents_no_update BEFORE UPDATE ON money_documents
BEGIN SELECT RAISE(ABORT, 'document revisions are immutable'); END;
CREATE TRIGGER money_documents_no_delete BEFORE DELETE ON money_documents
BEGIN SELECT RAISE(ABORT, 'document revisions are immutable'); END;

CREATE TRIGGER money_proposals_no_replace BEFORE INSERT ON money_proposals
WHEN EXISTS (SELECT 1 FROM money_proposals WHERE ref = NEW.ref)
BEGIN SELECT RAISE(ABORT, 'proposal already exists'); END;
CREATE TRIGGER money_proposals_no_update BEFORE UPDATE ON money_proposals
BEGIN SELECT RAISE(ABORT, 'proposals are immutable'); END;
CREATE TRIGGER money_proposals_no_delete BEFORE DELETE ON money_proposals
BEGIN SELECT RAISE(ABORT, 'proposals are immutable'); END;

CREATE TRIGGER money_issues_no_replace BEFORE INSERT ON money_issues
WHEN EXISTS (SELECT 1 FROM money_issues WHERE document_id = NEW.document_id OR ref = NEW.ref
  OR original_id = NEW.original_id
  OR (owner = NEW.owner AND kind = NEW.kind AND financial_year = NEW.financial_year AND sequence = NEW.sequence))
BEGIN SELECT RAISE(ABORT, 'issue already exists'); END;
CREATE TRIGGER money_issues_no_update BEFORE UPDATE ON money_issues
BEGIN SELECT RAISE(ABORT, 'issued documents are immutable'); END;
CREATE TRIGGER money_issues_no_delete BEFORE DELETE ON money_issues
BEGIN SELECT RAISE(ABORT, 'issued documents are immutable'); END;

CREATE TRIGGER money_payments_no_replace BEFORE INSERT ON money_payments
WHEN EXISTS (SELECT 1 FROM money_payments WHERE invoice_id = NEW.invoice_id AND reference = NEW.reference)
BEGIN SELECT RAISE(ABORT, 'payment already exists'); END;
CREATE TRIGGER money_payments_no_update BEFORE UPDATE ON money_payments
BEGIN SELECT RAISE(ABORT, 'recorded payments are immutable'); END;
CREATE TRIGGER money_payments_no_delete BEFORE DELETE ON money_payments
BEGIN SELECT RAISE(ABORT, 'recorded payments are immutable'); END;
