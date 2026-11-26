# Instagram insights

Use the owner's Meta app, key file and provider consent from [Instagram publishing setup](../../instagram-publish/references/publish.md). Insights can run without an upload target. Grant `instagram_business_basic` and `instagram_business_manage_insights` for Instagram Login. For Facebook Login, see the permissions for that account and token. [Meta Insights setup](https://developers.facebook.com/documentation/instagram-platform/insights)

```sh
B="${KAITO_HOME:-$HOME/.kaito}/store/business/scripts"
node "$B/kaito-instagram-insights.mjs" pull --owner "$OWNER"
node "$B/kaito-instagram-insights.mjs" pull --owner "$OWNER" --ref "$REF"
node "$B/kaito-instagram-insights.mjs" daily --owner "$OWNER"
node "$B/kaito-instagram-insights.mjs" list --owner "$OWNER" --json
```

`pull` fetches account time-series reach and totals for the last 48 hours, plus lifetime metrics for up to 50 recent posts and 50 active Stories. Use `--limit 1..200` to change each media limit or `--ref` to get one published item's metrics along with the account metrics. `list` also accepts `--date YYYY-MM-DD` in the owner's timezone. Meta may delay metrics by up to 48 hours, and Stories have a 24-hour window. [Account metrics](https://developers.facebook.com/documentation/instagram-platform/api-reference/instagram-user/insights), [media metrics](https://developers.facebook.com/documentation/instagram-platform/reference/instagram-media/insights)

Graph error subcode `2108006` is counted as a skipped media item. So is a Story that the API explicitly says has too few viewers. Unavailable metrics stay absent in SQLite. Other errors fail the pull and leave the daily job eligible to retry.

## Daily collection

Add the owner ID to `$KAITO_HOME/business/instagram-insights.json` to enable the read-only job in the [Mac scheduler](../../../business/references/scheduler.md#daily-instagram-insights). The scheduler checks eligible owners each tick. A successful full pull marks the owner's local date complete, and a later tick retries a failed pull.

A cron entry for 08:15 in the Mac's timezone uses absolute paths. Replace the paths and `owner-id` with your settings.

```cron
15 8 * * * KAITO_HOME=/absolute/kaito /absolute/node /absolute/kaito/store/business/scripts/kaito-instagram-insights.mjs daily --owner owner-id
```

The ledger migration creates `instagram_metrics`. It stores the owner and account ID, scope, subject ID, metric name, period, period end when supplied by Meta, snapshot date, value, collection time and Graph version. Repeating a pull on the same date updates matching rows.
