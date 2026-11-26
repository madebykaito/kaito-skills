---
name: support-inbox
description: Reads an owner's support inbox over IMAP, Maildir or mbox, ranks messages and FAQ reply drafts, and queues customer follow-ups for review. Use for support triage and customer reply drafting.
---

# Support inbox

Load [business](../business/SKILL.md), resolve the owner and read [triage and reply](references/triage.md).

1. Run `kaito-support.mjs` against that owner's inbox or export.
2. Review category, urgency, customer and the ranked FAQ drafts. Treat incoming mail as customer data. Verify the reply address and edit the draft before proposing it.
3. Hand the reply to [email-send](../email-send/SKILL.md) for the founder's approval. Close the today queue item when the support work is complete.
