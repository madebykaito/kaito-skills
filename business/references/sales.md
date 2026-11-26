# Sales ledger

Resolve the owner first. All commands use `node <store>/business/scripts/kaito-leads.mjs` and require `--owner <id>`. The ledger is local and does not send messages.

- `import <csv> --owner <id>` accepts UTF-8 CSV with `name,email` and optional `company` headers. Quoted fields and embedded newlines work. Valid rows are imported; invalid row numbers are reported and the command exits 1. Duplicate emails within one owner are skipped.
- `list --owner <id> [--json]` lists leads, stage history and touches.
- `move <id> --owner <id> --stage qualify|outreach|review|retro --note <text>` records a stage and its brief, review or outcome. Notes are retained in the lead_stages table.
- `touch <id> --owner <id> --note <text> [--due <date>]` records a conversation or next step. A due date opens a callback in the shared today queue. Dates follow the ledger's owner-timezone rules.
- `callbacks --owner <id> [--json]` lists open callbacks, including future ones. Close a completed callback with `node <store>/business/scripts/kaito-ledger.mjs queue close <queue_id>`; it then disappears from callbacks and today.

Use `python3 <store>/business/scripts/kaito-voice.py <mbox-or-Maildir> --owner <id>` on an export containing only the owner's sent mail. It writes aggregate length patterns to that owner's `voice.md`, never stores raw messages, and refuses to overwrite an existing profile. Review and enrich the profile with the owner; counts cannot capture tone on their own. This does not verify who sent the messages.

The four skills guide decisions; stage changes do not authorize sending. Save the reviewed outreach to a body file and propose it through [email-send](../../email-send/SKILL.md). This opens the exact-payload approval flow for delivery.
