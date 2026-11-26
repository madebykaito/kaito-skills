---
name: instagram-publish
description: Publish or schedule an Instagram image, Reel, Story or carousel for an owner through their Meta app. Use for Instagram posting, AI disclosure, collaborators, locations, Reel covers and checking a lost publish response.
---

# Instagram publish

Load the `business` skill first and resolve the owner. Work with the owner's Instagram handle and key file. See [setup and commands](references/publish.md).

1. Run `kaito-instagram-publish.mjs propose` with the exact caption, media, disclosure and options. Add `--due` for a scheduled post.
2. Show the full `kaito-approve.mjs <ref> --show` card. Wait for the founder's approval through the ledger.
3. For an immediate post, run `kaito-instagram-publish.mjs publish <ref> --digest <sha256>`. For a scheduled post, leave the approved item for the scheduler.
4. If the result is uncertain, run `kaito-instagram-publish.mjs reconcile <ref>`. Keep the ref open for a manual check if the command cannot establish a unique match.
