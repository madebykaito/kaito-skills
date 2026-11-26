CREATE TABLE email_do_not_contact (
  owner TEXT NOT NULL,
  address TEXT NOT NULL,
  added_at TEXT NOT NULL,
  PRIMARY KEY (owner, address)
) WITHOUT ROWID;
