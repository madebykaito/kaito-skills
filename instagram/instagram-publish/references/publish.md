# Instagram publishing setup

The publisher reads the private JSON file named by `keys.instagram` in the owner's `owner.json`. Set `channels.instagram` to the account's handle and grant the owner consent for the `instagram-graph` provider in the founder's terminal.

```sh
B="${KAITO_HOME:-$HOME/.kaito}/store/business/scripts"
node "$B/kaito-engines.mjs" consent instagram-graph --owner "$OWNER" --grant
```

Set `ig_user_id` to the app's Instagram account ID as a string and `access_token` to the long-lived token. The default is `graph.instagram.com` and Graph v27.0. With Facebook Login, set `graph_url` to `https://graph.facebook.com` and use the appropriate token for that account. Set `graph_version` if your app is pinned to another version. With Instagram Login, grant `instagram_business_basic` and `instagram_business_content_publishing`. With Facebook Login, check the permissions and Page tasks in Meta's setup. Stories require a Business account. [Meta content publishing](https://developers.facebook.com/documentation/instagram-platform/content-publishing)

## Media hosting

Meta fetches the media over public HTTPS. The publisher first reads the hosted bytes and checks the approved SHA-256. Choose an upload method in the private key file. Keep the token and any signed URLs there.

**Presigned PUT.** Use an S3-compatible bucket with versioning enabled. Map each media SHA-256 from the approval card to a signed PUT URL and a public read URL without a query for the same object. Include the Reel cover if used. The publisher appends the version from the PUT response, then verifies that the versioned GET returns the same version and approved bytes. The read endpoint must serve that exact `versionId` and return `x-amz-version-id`. Give public read access only to the staging prefix. Keep its versions available through container processing, then expire them with your bucket lifecycle policy. Sign with `image/jpeg` or `video/mp4` if your signer requires Content-Type. Use the local tunnel if your host lacks object versioning or needs a signed GET URL.

```json
{
  "ig_user_id": "123456",
  "access_token": "<long-lived-token>",
  "upload": {
    "kind": "presigned-put",
    "objects": {
      "<media-sha256>": {
        "put_url": "https://bucket.example/asset.mp4?<put-signature>",
        "read_url": "https://bucket.example/asset.mp4"
      }
    }
  }
}
```

**Local tunnel.** Serve one dedicated directory with a local HTTP server under the same user, then point your HTTPS tunnel at it. For example, serve `/absolute/instagram-staging` with `python3 -m http.server 8787 --bind 127.0.0.1 --directory /absolute/instagram-staging` and forward the tunnel to `http://127.0.0.1:8787`. Use a server that disables directory listings for a standing tunnel. Keep the server and tunnel running through the publish window. The publisher stages only the approved bytes under a random per-run path and removes them when container processing ends. A killed process can leave a staging directory for manual cleanup.

```json
{
  "ig_user_id": "123456",
  "access_token": "<long-lived-token>",
  "upload": {
    "kind": "tunnel",
    "directory": "/absolute/instagram-staging",
    "base_url": "https://media.example"
  }
}
```

## Commands

```sh
node "$B/kaito-instagram-publish.mjs" preflight reel.mp4
node "$B/kaito-instagram-publish.mjs" propose reel --owner "$OWNER" --media reel.mp4 --caption-file caption.txt --disclosure ai
node "$B/kaito-approve.mjs" "$REF"
node "$B/kaito-instagram-publish.mjs" publish "$REF" --digest "$DIGEST"
node "$B/kaito-instagram-publish.mjs" reconcile "$REF"
```

Set `REF` and `DIGEST` from the proposal output. The approval command above is for the founder's terminal. The ledger card shows the caption and options as JSON and the approved media digests in order.

- Types are `image`, `reel`, `story` and `carousel`. Give a single file or 2 to 20 files for a carousel. Carousel order follows `--media`.
- Use JPEG for images and covers. The Reel preflight checks MOV or MP4, moov before mdat, H.264 or HEVC, AAC at up to 48 kHz if an audio track is present, 3 seconds to 15 minutes and 300 MB. Story videos also have a 60-second, 100-MB limit. Use `FFPROBE_BIN` to override `ffprobe`.
- Use `--cover cover.jpg` to upload an approved JPEG as `cover_url`, or `--thumb-offset 500` for the frame at 500 ms. Use `--location-id` with a Meta location Page ID and `--collaborator` with up to three handles on feed posts, Reels or carousel parents. Stories take their text and graphics from the approved media.
- `--disclosure ai` sends `is_ai_generated=true`. Use `--due` with a timestamp such as `2026-11-28T09:30:00+05:30` to schedule. `--json` on `propose` emits the ref and digest as JSON.
- An uncertain send never resends on the same ref. Reconcile checks that the original container says `PUBLISHED` and that recent media has one match by exact caption digest, type and publish window. For a captionless, edited or ambiguous post, inspect Instagram and use the ledger's manual reconcile. Use `propose --retry-of <ref>` and get a new approval after a confirmed failure.

## Scheduler wiring

The Mac scheduler owns the due-time claim and result record. In its Node registry, import `instagramPublishHandlers` from `./instagram-publish.mjs` and use `new Map([...cloudHandlers, ...instagramPublishHandlers])`. The Reel handler prepares up to 20 minutes early. Preparation records the container in the ledger with the ref, digest and account. The publisher looks up that binding when it uses the claim. The Instagram handlers are Mac-only because they use the owner's local credentials, verified artifacts and ffprobe.
