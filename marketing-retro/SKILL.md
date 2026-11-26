---
name: marketing-retro
description: Compare an owner's published marketing results with the agreed brief and record lessons from real metrics.
---

# Marketing retro

Resolve the owner first. Read the published piece and agreed brief. Run the retro from owner-scoped Instagram insights:

```sh
node <store>/business/scripts/kaito-marketing.mjs retro --owner <id> --brief <brief.json>
```

For a specific post, set `instagram.subject` in the brief to its Instagram media ID. Use `instagram.start` and `instagram.end` for dates in the owner's calendar, with an exclusive end. The command uses the latest matching snapshot. If no snapshot covers the agreed period, use `--metrics <metrics.json>` with verified numbers from the correct source and period.

The brief's `metric` and numeric `target` determine the comparison. Report the actual period and source, result versus target, what to repeat and stop, and three next actions. Label explanations as hypotheses; one result does not establish a pattern. Record the dated result in the owner's memory, keeping internal figures private. Only add verified facts and actual buyer words to their respective owner records.
