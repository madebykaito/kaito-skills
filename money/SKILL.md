---
name: money
description: "Draft, check, approve and issue owner-scoped INR quotes, Indian GST invoices and credit notes. Use for document revisions, GST and place of supply, payment recording, aging and payment reminder drafts."
---

# Money

Load [business](../business/SKILL.md) and resolve the owner first. Read the [Money CLI reference](references/cli.md) for owner settings, input fields and calculations.

1. Gather the buyer's details, place of supply, line prices, HSN/SAC, tax rates and payment terms. Run `kaito-money.mjs draft`, then `check` to verify the tax and total and preview the client document. Use `revise` for edits before issue.
2. Run `propose` with the owner's billing channel and add `--pdf` when the client needs a PDF. Show the founder the exact stored client files and the ledger card from `kaito-approve.mjs <ref> --show`. The founder approves the ref and full digest under the [ledger rules](../business/references/ledger.md).
3. Run `issue` with that ref and digest, then `export` to retrieve the approved files. If the candidate date or number changed, propose again and get a fresh approval. Issue records the document locally. Delivery requires its own approval.
4. To correct an issued invoice, issue a credit note against it through the same approval flow. Draft a replacement invoice if needed.
5. Run `aging --sync` before reviewing `kaito-today.mjs`. Use `chase` for the current balance and an email draft, then pass its recipient, subject and body to `email-send`. Recheck the balance before handing off the draft. Use `payment` when the owner confirms a receipt.
