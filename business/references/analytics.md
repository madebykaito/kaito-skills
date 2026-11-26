# Analytics

Use a self-hosted Umami API base ending in `/api`, or the Umami Cloud API base. The key file contains one API key, without a label. Keep it outside the repository. `--url` also accepts `UMAMI_URL`; remote endpoints require HTTPS. The URL may not contain credentials, a query or a fragment.

```
node business/scripts/kaito-umami.mjs pull --owner lumen-tea --website WEBSITE_ID --start 2026-11-16T00:00:00Z --end 2026-11-23T00:00:00Z --url http://127.0.0.1:3000/api --key-file /path/to/key
node business/scripts/kaito-channel-retro.mjs --owner lumen-tea --website WEBSITE_ID --start 2026-11-16T00:00:00Z --end 2026-11-23T00:00:00Z
```

The end is exclusive. A pull replaces the snapshot for the same owner, website and interval. The retro needs exactly seven days and selects an exact snapshot, never adds visitor counts across periods. If several websites match, name one. Instagram reports the latest account snapshot per metric in the owner’s calendar dates from start to end. Rolling figures are shown as snapshots, without summing them. For tests or supplied exports, `--fixture /path/to/file` takes both channels:

```json
{"umami":{"pageviews":120,"visitors":80},"instagram":{"reach":42}}
```

Missing channels are marked `No data.` Fixture values must be finite numbers. A fixture replaces the database input; it is intended for testing and supplied exports.

For local Umami, `business/engines/umami.compose.yml` starts Umami and Postgres. Set `UMAMI_DB_PASSWORD` to a URL-safe random password, `UMAMI_APP_SECRET` to a random secret, and `UMAMI_TWO_FACTOR_KEY` to 64 hexadecimal characters before `docker compose -f business/engines/umami.compose.yml up -d`. Create the website and API key in Umami after startup.
