# Recipes

Ordered chains for goals that need more than one skill. Run the steps in order. Skip a step when its input does not exist or the user scoped it out, and say which you skipped.

Each step lists a tier for delegation. "Main" means keep it in the main session.

## Landing page from a brief

1. `landing-page` (or the matching page-type skill from [pages.md](domains/pages.md)): structure and sections. Main.
2. `copywriting`: the copy for each section. Main.
3. `frontend-design`: build it. Main.
4. `better-interface`: one ranked verdict, then fix the top findings. Hard tier if delegated.
5. `schema`: metadata and structured data. Standard tier.
6. `gstack` `/qa`: test it in a browser.

The Route line names these six in this order, `landing-page` first. Add one add-on at most, only when the brief calls for it, and drop step 5 to stay at six: `ogilvy` if the headline is the hard part, `visual-style-presets` if no visual direction was given, `seo-audit` in place of `schema` if the page already exists and ranks badly.

## Pricing page

1. `pricing-page`: plans, value metric, FAQ.
2. `copywriting`: plan names, feature lines, FAQ answers.
3. `frontend-design`: build it.
4. `better-interface`, then `schema` for FAQ and product schema.

## Polish an existing interface

1. `better-interface`: the ranked verdict across disciplines. Hard tier.
2. `impeccable`: the polish pass on the top findings. Main.
3. `break-ui`: worst-case data. Standard tier.
4. `mobile-native`: only if it is a web app used on phones.

## Motion pass on an existing app

1. `remove-animations`: cut what should not move. Do this first.
2. `find-animation-opportunities`: where motion would help. Read-only. Standard tier.
3. `improve-animations`: prioritized plans for what exists. Read-only. Hard tier.
4. `animate`, `choreograph` or `gestures`: execute the plans. Standard tier, one agent per plan.
5. `animation-performance`: only if something drops frames.

## Page that does not convert

1. `cro`: diagnose.
2. `copy-editing`: tighten the copy the diagnosis flagged.
3. `analytics`: make the change measurable.

## SEO page set

1. `content-strategy`: which pages and why. Main.
2. `programmatic-seo` or `competitors`: the template. Main.
3. Page fill from data. Light tier, in parallel.
4. `schema`, then `stop-slop` on a sample. Standard tier.

## Product video

1. `stageshow`: faux product UI, if the real UI cannot be shown.
2. `hyperframes`, plus one adapter from [video.md](domains/video.md).
3. `hyperframes-media`: voiceover and captions.
4. `hyperframes-cli`: lint, preview, render.

For a video of an existing site, replace steps 1 and 2 with `website-to-hyperframes`.

## Research project

1. `brainstorming-research`: question, method and scope into an approved design doc. Main.
2. `writing-research-plan`: the plan with hypothesis, tasks and checks. Main. Use `scaffold-research-project` first if there is no project folder yet.
3. `literature-review`: the graded source guide and BibTeX. Standard tier for the database searches.
4. `acquire-sources`, then `ingest-source` per source: PDFs on disk, then source pages. Standard tier, one agent per source. Run `wiki-lint` after the round.
5. `drafting-manuscript`: the argument first, then one section at a time. Main.
6. `requesting-peer-review`: constructive, then adversarial. Hard tier, fresh context per reviewer.

`executing-research-plan` can run steps 4 and 5 from the plan. Each step is its own task, often its own session, so the six-skill cap counts per step.

## Ship a change safely

1. `adversarial-review`: try to break the diff. Hard tier, with a second opinion from a different vendor when one is available.
2. `interface-review`: only if the change touches UI. User-invoked: suggest it.
3. `gstack` `/qa`, then `/ship`.
