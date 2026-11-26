# v1.7.0 verification

26 November 2026. Ran on the Mac against an exact temporary checkout. The real-run commands used a temporary `KAITO_HOME`, fictional owner `lumen-tea` and a loopback Graph server. Digest approvals were simulated for these fixtures.

In the commands below, `B=business/scripts` and `S=reel-assemble/scripts`. Paths to generated inputs are shown without their temporary directory prefix. Each command exited 0 unless stated.

| Command | Result |
|---|---|
| `SVARA_PYTHON=./voice-fixture python3 voiceover/scripts/voiceover.py --owner lumen-tea --lines lines.json --out-dir voice` | The fixture engine supplied audio. Voiceover wrote `voice.wav` and `parts.json` with a 4.54 s duration. |
| `python3 captions/scripts/captions.py render --parts voice/parts.json --out-dir captions` | Chromium rendered two timed PNG captions and wrote `captions.json`. |
| `ffmpeg -v error -f lavfi -i testsrc2=s=180x320:r=25:d=2 -c:v libx264 clip-a.mp4` | Generated the first fixture clip. |
| `ffmpeg -v error -f lavfi -i color=c=teal:s=180x320:r=25:d=2 -c:v libx264 clip-b.mp4` | Generated the second fixture clip. |
| `ffmpeg -v error -f lavfi -i sine=frequency=220:duration=2 bed.wav` | Generated the fixture music bed. |
| `python3 "$S/reel-assemble.py" --shots clip-a.mp4 clip-b.mp4 --parts voice/parts.json --captions captions/captions.json --bed bed.wav --out reel.mp4` | Assembled both clips using the original voiceover and captions outputs. |
| `python3 "$S/media-spec.py" check reel.mp4 --target ig-reels` | `pass: ig-reels`. Verified H.264 at 1080 × 1920 and AAC at 48 kHz with `ffprobe`. |
| `node tests/fixtures/instagram/graph.mjs "$fixture_dir"` | Started the fake Graph server on loopback. |
| `node "$B/kaito-owner.mjs" resolve --owner lumen-tea` | Resolved the sample to the temporary Lumen Tea owner. |
| `node "$B/kaito-claims.mjs" check --owner lumen-tea caption.txt` | The caption from the [campaign sample](samples/campaign-lumen-tea.md) passed the claims check. |
| `node "$B/kaito-marketing.mjs" review --owner lumen-tea --brief brief.json --post caption.txt` | The caption passed the brief's mechanical checks. |
| `node "$B/kaito-instagram-publish.mjs" propose reel --owner lumen-tea --media reel.mp4 --caption-file caption.txt --json` | Created a Reel ref and digest. |
| `AI_AGENT=1 node "$B/kaito-approve.mjs" "$ref" --digest "$digest"` | Fixture approval recorded against that digest. |
| `node "$B/kaito-instagram-publish.mjs" publish "$ref" --digest "$digest"` | Claimed and published through the Instagram handler. A repeat returned exit 3. |
| `node "$B/kaito-ledger.mjs" status "$ref" --json` | `sent`, attempt 1, remote ID `202`. The loopback log had one publish request. |
| `node "$B/kaito-instagram-insights.mjs" pull --owner lumen-tea --ref "$ref" --json` | Wrote 18 metrics, with zero skipped for this pull. |
| `node "$B/kaito-marketing.mjs" retro --owner lumen-tea --brief brief.json` | The brief pointed to media `202`. The retro read 7 fixture views against a target of 10. |
| `node "$B/kaito-email.mjs" --owner lumen-tea --to "$to" --subject "$subject" --body-file email.txt --unsubscribe https://example.test/leave` | Rendered the sample campaign email draft. The paid variants remained sample copy. |
| `node "$B/kaito-leads.mjs" import leads.csv --owner lumen-tea` | Imported one lead with zero duplicates. |
| `node "$B/kaito-leads.mjs" move 1 --owner lumen-tea --stage "$stage" --note "$note"` | Ran in order for `qualify`, `outreach`, `review` and `retro`. The outreach copy rendered through `kaito-email.mjs` in draft mode. |
| `node "$B/kaito-leads.mjs" touch 1 --owner lumen-tea --note 'Follow up on sample' --due 2020-01-01` | Opened callback item 1. `kaito-leads.mjs callbacks --owner lumen-tea --json` listed it. |
| `node "$B/kaito-ledger.mjs" queue close 1` | Closed the callback. Repeating the callbacks command returned an empty list. |
| `node "$B/kaito-money.mjs" draft invoice --owner lumen-tea --input invoice.json` | Created an unnumbered GST invoice draft. |
| `node "$B/kaito-money.mjs" check "$doc" --owner lumen-tea` | Net 155 paise, CGST 14, SGST 14, total 183. |
| `node "$B/kaito-money.mjs" propose "$doc" --owner lumen-tea --account "$billing" --pdf` | Chromium rendered the PDF for approval. |
| `AI_AGENT=1 node "$B/kaito-approve.mjs" "$ref" --digest "$digest"` | Approved the fixture invoice and its PDF. |
| `node "$B/kaito-money.mjs" issue "$doc" --owner lumen-tea --ref "$ref" --digest "$digest"` | Issued `INV-2026-000001`, sequence 1. |
| `node "$B/kaito-money.mjs" export "$doc" --owner lumen-tea --pdf invoice.pdf` | Exported the approved PDF. `pdftotext invoice.pdf invoice.txt` confirmed the number and GST labels and found no internal cost. |
| `node "$B/kaito-money.mjs" chase "$doc" --owner lumen-tea` | Produced a payment reminder. The recipient, subject and body rendered in `kaito-email.mjs` draft mode. |
| `node "$B/kaito-engines.mjs" doctor --owner lumen-tea --json` | Reported 48 GB RAM and 16 capabilities. Host LLM was selected for bulk drafting. Postiz, MoneyPrinterTurbo and Twenty were unavailable in the fixture run. |
| `node "$B/kaito-ledger.mjs" propose --owner lumen-tea --account @lumentea.example --action noop-test --text-file caption.txt --due "$due" --json` | Created one due fixture action. Approved with the same `kaito-approve.mjs "$ref" --digest "$digest"` fixture command. |
| `node "$B/kaito-tick.mjs` | First tick worked the item. Second tick did no work. Ledger status showed `sent` and attempt 1. |

## Release checks

- `tests/run.sh` passed all 600 tests across 44 suites.
- `helpmekaito/scripts/check-routes.sh` reported `routes ok`.
- `node tools/privacy-scan.mjs` reported `privacy ok` with the local denylist.
- `git diff --check origin/main` passed.
- `claude plugin validate .` passed and `node tools/validate-skills.mjs` checked all 242 skill files.

Founder runs still owed are Meta app publishing, Postiz delivery, real email delivery, a real Ollama model and MoneyPrinterTurbo startup.
