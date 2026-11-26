# Triage and reply

Create `faq.json` in the owner's folder. Use an empty array if the owner has no FAQ yet.

```json
[
  {
    "category": "delivery",
    "keywords": ["tracking", "where is my order"],
    "reply": "Please share the order number so we can check the shipment."
  }
]
```

FAQ entries rank by the number of matching keywords or phrases in the subject and plain-text body. The top FAQ match gives the category. The built-in categories cover billing, delivery, account and product, with general as the fallback. The scan puts urgent messages first, then ranks by FAQ match count and newest message date. Review unmatched or HTML-only messages in the source inbox before replying.

```sh
B="${KAITO_HOME:-$HOME/.kaito}/store/business/scripts"
node "$B/kaito-support.mjs" --owner lumen-tea --maildir /path/to/export
node "$B/kaito-support.mjs" --owner lumen-tea --mbox /path/to/export.mbox
node "$B/kaito-support.mjs" --owner lumen-tea --imap
node "$B/kaito-today.mjs" --owner lumen-tea
```

IMAP uses TLS and opens the mailbox read-only. Set `keys.imap` in `owner.json` to the owner's private JSON file with `host`, `username`, `password` and optional `port` (default 993) and `mailbox` (default `INBOX`).

The default scan reads up to 50 messages from the chosen source. Increase it with `--limit` up to 200. Messages over 5 MiB are triaged from their headers. `--no-queue` previews the triage. Other runs add one `support-reply` queue item per message and owner. Urgent items are due immediately. Re-scanning reuses existing items, including closed items.

Pick a draft and write its edited text to a local body file. Review the `reply.to` value, which can come from the incoming Reply-To header. Pass the suggested subject and, when available, the original message ID to email-send.

```sh
node "$B/kaito-email.mjs" propose --owner lumen-tea --to "$to" \
  --subject "$subject" --body-file "$body_file" --in-reply-to "$message_id"
```

Omit `--in-reply-to` when no message ID was returned. If the scan could not identify a single reply address, check the source manually. After the support work is complete, close its queue item with `node "$B/kaito-today.mjs" queue close "$queue_id"`.
