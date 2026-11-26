---
name: email-send
description: Drafts and sends owner email through SMTP, Amazon SES or listmonk. Use to prepare an email for approval, send an approved email, or manage unsubscribe and do-not-contact entries for an owner.
---

# Email send

Load [business](../business/SKILL.md) and resolve the owner. Read [send and setup](references/send.md) for commands and key file formats.

1. Run `kaito-email.mjs` with the recipient, subject and body file to draft locally. Include the unsubscribe URL when the email calls for it.
2. Run `propose` on the final draft. Show the full `kaito-approve.mjs <ref> --show` card and have the founder approve the exact digest through the business ledger.
3. Run `send <ref> --digest <sha256>` when approved. Use the same owner. The claim rechecks do-not-contact and the owner's send limit.
4. When delivery is uncertain, check the provider and use ledger reconciliation before considering a new proposal.
