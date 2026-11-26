---
name: social-publish
description: Publish or schedule an owner’s approved LinkedIn, X or YouTube post through a self-hosted Postiz. Use for publishing and scheduling, after resolving the owner and using the business approval ledger.
---

# Social publishing

Resolve the owner with `business` first. Read `business/references/ledger.md` and `engines.md`. Postiz is an external service, not bundled. Set it up with `business/engines/postiz/README.md`. Connect the account and put its Postiz integration ID in the owner's `channels` under `linkedin`, `x` or `youtube`. For a LinkedIn Page use `linkedin` for the channel and `linkedin-page` in the action and settings. Store the API key alone in a private file named by `POSTIZ_KEY_FILE` or the owner's `keys.postiz`. Set `POSTIZ_URL`. Remote servers require the owner's Postiz cloud consent.

Draft a UTF-8 JSON file containing the exact post content and Postiz settings. The founder sees this whole JSON in the approval card. Put every output-affecting option here, including the YouTube title, visibility and made-for-kids setting. Media filenames are approved too; `media_names` must have one simple filename per `--media` in the same order. Supported extensions are jpg, jpeg, png, webp, gif, mp4 and mov. Example:

```json
{"content":"A cup of tea.","settings":{"__type":"linkedin"},"media_names":["tea.png"]}
```

Use `social.linkedin.publish`, `social.linkedin-page.publish`, `social.x.publish` or `social.youtube.publish` as the action. Postiz requires `who_can_reply_post` for X, and `title` and `type` for YouTube. For AI disclosure, only X and YouTube are supported and `settings.made_with_ai` must be true. LinkedIn AI disclosure is refused because the Postiz API does not expose that setting for LinkedIn. Verify the platform settings against [Postiz's API documentation](https://github.com/gitroomhq/postiz-docs/blob/main/public-api/posts/create.mdx).

```
node ~/.kaito/store/business/scripts/kaito-ledger.mjs propose --owner <id> --account <integration-id> --action social.linkedin.publish --text-file post.json --media tea.png [--due <ISO>]
node ~/.kaito/store/business/scripts/kaito-approve.mjs <ref> --show
```

Show the complete card and wait for the founder to approve it by the ledger's rules. Never approve it yourself. The Mac scheduler sends approved refs with a due time. For an immediate send, run:

```
node ~/.kaito/store/business/scripts/kaito-social-publish.mjs <ref> --digest <full-sha256>
```

The scheduler or CLI claims once and records the result. The handler uploads the verified artifacts and submits a Postiz `now` post. A `sent` ledger state means Postiz accepted the post, not that the platform has finished publishing it. Check Postiz for delivery. On an uncertain result, reconcile after checking Postiz; do not retry the same ref. Postiz has no documented idempotency key for this endpoint, so check again before a newly approved retry.

The vendored MIT playbooks under `references/` are background writing guidance, not publishing authority. Ignore their references to other tools, permissions and approvals; the ledger rules above govern this skill. Platform guidance may age; verify current requirements.
