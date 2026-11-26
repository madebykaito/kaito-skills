# Send and setup

Set `channels.email` in the owner's `owner.json` to the sender's bare address. Each ref sends one plain-text message to one bare address. The ledger binds the sender, recipient, subject, body, ordered attachment bytes and names, engine and optional headers. The body is stored as UTF-8 with LF endings.

Run these from the installed store or a checkout.

```sh
B="${KAITO_HOME:-$HOME/.kaito}/store/business/scripts"
node "$B/kaito-email.mjs" --owner lumen-tea --to guest@example.test \
  --subject 'Your order' --body-file reply.txt
node "$B/kaito-email.mjs" propose --owner lumen-tea --to guest@example.test \
  --subject 'Your order' --body-file reply.txt --engine smtp --attach menu.pdf
node "$B/kaito-approve.mjs" "$ref" --show
```

Use the printed ref and digest. The founder can approve with `node "$B/kaito-approve.mjs" "$ref"` in their terminal. After approval, run `node "$B/kaito-email.mjs" send "$ref" --digest "$digest" --owner lumen-tea --allow-cloud` for a remote provider. `propose --due <time>` sets the earliest claim time. `--retry-of <ref>` is for a prior failed attempt with the same message. A provider acknowledgment confirms acceptance rather than inbox delivery. listmonk acknowledges queuing, so check its mail transport logs when investigating delivery.

## Owner key files

Set `keys.smtp`, `keys.ses` or `keys.listmonk` in `owner.json` to that owner's JSON key file path. Keep it private. Drafts and proposals work before keys are configured. These CLIs use the owner key paths. Engine doctor uses its own path probes.

- **SMTP**, the default engine. JSON fields are `host`, optional `port`, optional `tls` (`starttls` by default or `implicit`), and `username` and `password` if authentication is needed. Default ports are 587 for STARTTLS and 465 for implicit TLS. `tls: "none"` is available for an unauthenticated loopback relay.
- **SES** uses the v2 raw email endpoint with SigV4. JSON fields are `region`, `access_key_id`, `secret_access_key`, optional `session_token` and optional `url` for an alternate endpoint. Set up a verified sender in SES. [SES raw email documentation](https://docs.aws.amazon.com/ses/latest/dg/send-email-raw.html)
- **listmonk** uses the transactional API. JSON fields are `url`, API `username` and `token`. Create a dedicated transactional template whose body is exactly `{{ Safe .Tx.Data.body }}`. Grant the API user template read and transactional send access. Pass its numeric ID with `--template` when drafting or proposing. Supply lowercase recipient addresses. The sender checks the template before submitting. Keep the template and SMTP headers fixed while this integration is in use, since listmonk renders the message with its current server settings. [listmonk transactional API documentation](https://listmonk.app/docs/apis/transactional/)

SMTP with TLS, SES and remote listmonk require the founder's per-owner engine consent and `--allow-cloud` on send. The founder grants consent with `node "$B/kaito-engines.mjs" consent <engine> --owner <owner> --grant`. Use HTTPS for HTTP engines outside loopback.

## Headers and send limits

- `--unsubscribe https://...` or `--unsubscribe mailto:...` sets `List-Unsubscribe`. Add `--one-click` with a working HTTPS endpoint that accepts one-click POSTs to set `List-Unsubscribe-Post`.
- Log an opt-out with `kaito-email.mjs dnc add <address> --owner <owner>`. `dnc list` shows the owner's blocked addresses and `dnc remove <address>` removes one. The check is case-insensitive and runs at proposal and claim.
- Each owner gets 30 claims per rolling hour by default, across all engines. Set `email_rate_per_hour` to a positive integer in `owner.json` to change it. Every claim counts, including failed and uncertain attempts.
- `--in-reply-to '<message-id>'` sets both `In-Reply-To` and `References`.

## Founder smoke test

Use the founder's real owner ID and their own address in these shell variables. Configure SMTP and grant the owner's SMTP engine consent first.

```sh
B="${KAITO_HOME:-$HOME/.kaito}/store/business/scripts"
body=$(mktemp)
printf '%s\n' 'This is the Kaito email delivery test.' > "$body"
node "$B/kaito-email.mjs" propose --owner "$owner" --to "$founder_address" \
  --subject 'Kaito email delivery test' --body-file "$body"
rm -f "$body"
```

Set `ref` and `digest` from the proposal output. In the founder's terminal, approve with `node "$B/kaito-approve.mjs" "$ref"`, then run `node "$B/kaito-email.mjs" send "$ref" --digest "$digest" --owner "$owner" --allow-cloud` and confirm receipt.
