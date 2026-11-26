---
name: marketing-review
description: Review an owner's marketing draft against its agreed brief and evidence before approval.
---

# Marketing review

Resolve the owner first. Obtain the agreed brief, the exact draft, the owner's brand and voice, and evidence. Stop if the brief is missing. Run:

```sh
node <store>/business/scripts/kaito-marketing.mjs review --owner <id> --brief <brief.json> --post <post>
```

The command checks claims and flags missing verbatim message or action. This is a conservative mechanical check, not a verdict: equivalent wording may be flagged and matching wording may still mislead. Independently review the exact piece for the intended buyer, one message and action, permitted proof, brand and voice. Read it as a skeptical buyer: identify what they might doubt, skip or misunderstand. Report findings with lines and fixes without rewriting the draft. Fail on unbacked claims, off-brief content or a material finding. A mechanical pass alone is not approval. After fixes, review again; publication still needs ledger approval of the exact payload.

Evidence is `$KAITO_HOME/owners/<id>/evidence.json`, an array of objects with `claim`, `source`, `date` and `expiry` (ISO dates). Each detected claim must appear verbatim, case-insensitively, in a current evidence entry with a nonempty source. Check source quality and all factual statements manually: the pattern detector cannot find every claim. Run it separately with `node <store>/business/scripts/kaito-claims.mjs check --owner <id> <post>`.
