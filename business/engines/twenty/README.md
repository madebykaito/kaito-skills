# Twenty

This template runs Twenty, PostgreSQL and Redis locally. After startup, configure [Kaito Lead sync](../../references/twenty.md).

Set `TWENTY_DB_PASSWORD` to a URL-safe password, `TWENTY_APP_SECRET` to a random secret and `TWENTY_ENCRYPTION_KEY` to a base64-encoded 32-byte key. Keep these values outside the repository. Then run:

```sh
docker compose -f business/engines/twenty/compose.yml up -d --wait
docker compose -f business/engines/twenty/compose.yml down
```

The server listens only on localhost, port 3319 by default. Set `TWENTY_PORT` to change it and `TWENTY_TAG` to select an image version. Volumes persist across `down`; use `down -v` only when the data can be discarded.
