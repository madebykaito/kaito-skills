# Today queue and Monday brief

`kaito-today.mjs` answers "what needs me today" across owners, from the ledger. Dates are in the owner's timezone: `timezone` in `owner.json`, else `Asia/Kolkata`. Run as `node <store>/business/scripts/kaito-today.mjs`.

## What it lists

- Open queue items: callbacks, invoice chases, follow-ups, anything a stage adds.
- Actions waiting for the founder's approval (`proposed`).
- Sends to check (`uncertain`, or a claim with no result after 30 minutes).

Each item falls in a bucket by its local date: `overdue` (before today), `today`, `undated`, `later`. Overdue comes first, then today, each by due time. Queue items due later are left out. Approvals and checks are always listed, even when due later, because they block a send.

```
kaito-today.mjs [--owner <id>] [--json]
```

Text view:

```
Needs you today, Thu 26 Nov 2026 (Asia/Kolkata)
overdue  Fri 20 Nov        lumen-tea  invoice-chase  Chase invoice LT-0039  [q4]
today    Thu 26 Nov 01:30  lumen-tea  callback       Call the Kolkata stockist  [q2]
later    Sat 28 Nov 10:00  ira-das    approve        Approve instagram.post on @iradas.example  [act-20261126-1a2b3c4d]
```

`--json` prints `{date, timezone, items: [{bucket, source, id, owner, kind, title, due_at, due_local, ref}]}`. `source` is `queue` or `action`; for an action, `id` is its ref. Without `--owner` the header uses IST and each item uses its own owner's zone. Exit 4 when `--owner` names no owner.

## Queue

```
kaito-ledger.mjs queue add --owner <id> --kind <kind> --title <text> [--due <when>] [--ref <ref>] [--note text]
kaito-ledger.mjs queue list [--owner <id>] [--all] [--json]
kaito-ledger.mjs queue close <id>
```

`kaito-today.mjs queue ...` takes the same commands. `add` prints `id=<n>`.

- `--kind` is one lowercase kebab word. Use these where they fit: `callback`, `follow-up`, `invoice-chase`, `review`, `task`.
- `--due` is `YYYY-MM-DD` for a whole day, or a time. A time without an offset is the owner's local time, so `2026-11-28T11:00` for lumen-tea is 11:00 IST. A whole day keeps its calendar date even if the owner's timezone changes later. Impossible dates are refused, and so are local times a clock change skips or repeats: give an offset for those.
- The owner must have an `owner.json` (exit 4 otherwise).
- `--ref` links the item to a ledger action of the same owner.
- `close` on a closed item exits 3, on an unknown id 4.

Stages add their own items: sales adds callbacks, money adds invoice chases. Close the item when the work is done, not when it is drafted.

## Monday brief

```
kaito-today.mjs brief --owner <id>
```

A short markdown view of the owner's week, Monday to Sunday in the owner's zone. It has four sections, each `None.` when empty:

1. **Awaiting your approval**: every proposed action.
2. **Uncertain sends to check**: what reconcile lists.
3. **Overdue**: open queue items before today.
4. **Due this week**: queue items from today to Sunday, and approved sends scheduled this week.

Recipe, for the agent on a Monday morning (or when the founder asks "what is my week"):

1. Resolve the owner with `kaito-owner.mjs resolve`. With several owners and none named, run the brief once per owner.
2. Run `kaito-today.mjs brief --owner <id>` and show it as it is.
3. For each approval, offer the card (`kaito-approve.mjs <ref> --show`). Never approve on the founder's behalf; see `ledger.md`.
4. For each uncertain send, check the platform, then `kaito-ledger.mjs reconcile <ref> --sent --remote-id <id>` or `--failed`.
5. Ask which overdue items to do now, close those that are done, and leave the rest.

`--now <time with offset>` on `kaito-today.mjs` and `brief` pretends it is that time, for tests and dry runs. It changes nothing in the ledger.
