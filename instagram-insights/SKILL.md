---
name: instagram-insights
description: Pull or review account, Reel, post and Story insights for an owner's Instagram professional account. Use for Instagram metrics, daily snapshots, skipped legacy media and reporting on a published ledger ref.
---

# Instagram insights

Load `business` and resolve the owner. Configure the owner's Meta credentials as described in [setup and commands](references/insights.md). Use `kaito-instagram-insights.mjs pull` to collect metrics, `daily` for scheduled collection and `list` to read stored snapshots.

A skipped media item can predate the Business conversion or have unavailable metrics. Treat it as missing data. Include the metric period and snapshot date when reporting.
