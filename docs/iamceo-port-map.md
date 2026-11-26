# iamceo port map

The v1.7.0 business skills draw on the founder's private operations kit, iamceo. This page says which piece informs which new skill. It names pieces and roles only.

## The rule

Text is rewritten, not copied. Nothing from iamceo is pasted into this repo: no prompts, playbooks, copy, prices, names, handles, client details or media. Each skill is written fresh in its own words, with fictional owners (`lumen-tea`, `ira-das`) in examples and fixtures.

Before any branch is pushed, `node tools/privacy-scan.mjs` must pass. Locally it also reads the private denylist at `~/.kaito/privacy-denylist.txt`. CI runs the generic patterns only.

## Map

| iamceo piece | Informs | Role |
|---|---|---|
| Owner scoping and the owner record | owner registry | Pick the owner from the folder, refuse when it is ambiguous |
| Company and person profiles | owner folder files (`brand.md`, `voice.md`, `icp.md`) | One folder per owner holds who they are and how they sound |
| Offer and pricing sheets | `offers.json` | Machine-readable offers in the owner's currency |
| Channel and social profile notes | `channels.json` | Which accounts exist and how often each posts |
| Approval and publish discipline | action ledger and `kaito-approve` | Propose, approve by digest, then act once |
| Playbooks for go-to-market planning | business planning skills | Turn an owner folder into a dated plan |
| Content calendar scripts | content planning skills | Plan the week from channels and offers |
| Lead and outreach tracking | CRM and sales skills | Keep leads, follow-ups and replies in one place |
| Media scripts (voice, captions, stills, clips) | studio skills | Local engines for audio, captions, images and short video |
| Brand kit tokens and guidelines | brand skills | Colours, type and voice rules applied to output |
| Daily "needs me" review | `kaito-today` | One list of what waits on the founder |
| Reporting and spend tracking | analytics and money skills | Numbers per owner, per channel |

## Checklist for a new skill that uses this map

1. Read the iamceo piece for its idea only.
2. Write the skill text from scratch, in short plain sentences.
3. Use the fictional owners in every example.
4. Run `node tools/privacy-scan.mjs` and fix any hit before you commit.
