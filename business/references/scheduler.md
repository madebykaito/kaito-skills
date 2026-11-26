# Scheduler

From the business install or checkout, run these in a logged-in Mac user's terminal.

```sh
node <store>/business/scripts/kaito-schedule.mjs install
node <store>/business/scripts/kaito-schedule.mjs status
node <store>/business/scripts/kaito-schedule.mjs uninstall
node <store>/business/scripts/kaito-tick.mjs
```

Install loads `~/Library/LaunchAgents/com.kaito.tick.plist` in the user's GUI domain. It ticks at load and every 600 seconds while launchd runs it, with logs under `$KAITO_HOME/business/logs`. Use a stable install path that launchd can read, such as `$KAITO_HOME/store`. Reinstall after moving the store or replacing the Node executable. Use `--label com.kaito.tick.test` with a temporary `KAITO_HOME` for a separate fixture job.

Propose with `--due` and ask the founder to approve the ref through the ledger. The tick checks scheduled refs with a registered handler. Immediate actions without a due time follow the publisher's own claim flow. The tick may prepare an approved Reel container before its due time. At send time it atomically claims the ref, reads the verified artifacts and calls the handler once. A lost response is recorded as uncertain. A killed tick leaves a claim behind, and a later tick marks a scheduler claim with no result after 30 minutes uncertain. Check the platform before resolving it with `kaito-ledger.mjs reconcile`.

## Daily Instagram insights

Put an array of owner IDs such as `["lumen-tea"]` in `$KAITO_HOME/business/instagram-insights.json`. Configure the Instagram key and provider consent for each owner. The Mac LaunchAgent runs the read-only insights job after outbound work. Each owner gets one successful full pull per day in their timezone. A failed pull can retry on the next tick. An owner can also run the daily job with `kaito-instagram-insights.mjs daily --owner <id>`.

Scheduled email uses the configured sender and the same do-not-contact and rate limits as immediate email. Remote engines require recorded owner consent. Use `--due` on the email proposal to schedule it.

## Handler interface

Register a verb such as `instagram.reel.publish` in `business/handlers/registry.mjs`. Portable handlers for both runtimes go in `cloud-registry.mjs` with `cloud: true`. The Mac registry includes Instagram publishing, Postiz publishing and email. The Worker registry includes `noop-test` for drills.

The Mac publishing handlers set `ledger: true` and implement `publish(ref, digest, attempt)`. The handler consumes the one-time dispatch reservation and loads verified bytes from the ledger before using credentials. A handler that stages a container implements `prepare(ref, digest)` and records its binding before returning `{ id, expiresAt }`.

Portable Worker handlers use the following interface.

- `publish(item, { now, preparedId, env })` sends once. `item` has `ref`, `digest`, `attempt`, `idempotency_key`, `owner`, `account`, `action`, `disclosure`, `due_at`, `text` (bytes or null), and `media` (ordered byte arrays). Use those bytes and pass the idempotency key if the platform supports one. Return `{ result: 'ok' | 'failed' | 'uncertain', remoteId? }`. Return failed only when known that the platform did not accept the send. A thrown error or malformed response is uncertain.
- Optional `prepareAheadMs` and `prepare(item, { now, env })` let a tick create or stage an unpublished container for an approved payload. Return `{ id, expiresAt }` with expiry in epoch milliseconds. Prepare may retry after an interruption and must never publish. The final send may receive a null `preparedId`, including when the container expired or processing was still underway. Handle that case inside the claimed send.
- Use timeouts for network calls and bound the whole send below 30 minutes. The handler alone reads platform credentials. `env` is the Worker binding object and is absent on the Mac. Logs should omit credentials, request bodies and response bodies.

## Optional Cloudflare Worker

From `business/worker`, create a D1 database using Wrangler, replace the database id in `wrangler.toml`, apply `schema.sql` remotely, set the shared secret and deploy. The cron runs every ten minutes in UTC. Allow time for the trigger to propagate.

```sh
wrangler d1 create kaito-scheduler
wrangler d1 execute kaito-scheduler --remote --file=schema.sql
wrangler secret put KAITO_QUEUE_HMAC
wrangler deploy
```

Generate a random 32-byte key encoded as 64 lowercase hex characters. Keep it in a private file on the Mac (mode 0600) and supply the same value to the Worker secret prompt. The founder enables transfers for each consenting owner by setting their `cloud_ok` and naming them in `$KAITO_HOME/business/worker.json`.

```json
{"url":"https://scheduler.example/queue","key_file":"/absolute/path/to/scheduler.key","owners":["lumen-tea"]}
```

Hand off an approved, timed ref while the Mac is awake.

```sh
node <store>/business/scripts/kaito-tick.mjs sync <approved-ref>
```

Wait for `delegated=<ref>` before relying on the Worker. The Mac reserves the ledger's one claim and its sync destination in a single transaction. Regular ticks retry a pending handoff and import Worker results. D1 atomically claims a due ref before invoking a handler. Both queues retain the ref after completion to dedupe retries. There is no Mac fallback on a delegated ref. An explicit handoff can reserve a future action and closes the ledger's reject path. Reconciliation is available after the Worker's 24-hour late window plus 30 minutes, or sooner if the Worker already reported uncertainty. A queue upload may have arrived even if its response was lost.

The Worker treats a valid HMAC as proof that the trusted Mac claimed the exact approved job. Cloudflare processes the signed caption and media and needs its own platform credentials for any real cloud handler. Whoever holds the key can authorize jobs on the Worker. Keep the secret, deployment and D1 database private. Keep D1 ref records intact and keep the URL and key stable until pending work is settled. Changing the allowlist stops future uploads. It cannot recall already-synced jobs. Completed queue entries keep the ref, digest and result and clear the signed payload. The decoded job must fit within the 800,000-byte JSON envelope after base64 encoding. Keep larger media on the Mac until a cloud handler and artifact transport support it.
