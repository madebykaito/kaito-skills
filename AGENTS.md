# Kaito Skills repository rules

- Put each skill family in one top-level bundle. List its skills in `bundle.json` and give each skill its own `SKILL.md`. `tools/check-layout.mjs` checks the layout and documents exceptions in `tools/layout-allowlist.json`.
- Vendor runtime files only. Keep upstream `LICENSE` and `NOTICE` files. Leave out upstream tests, CI files, build output and dependencies.
- Add a row for every skill in `README.md`, `THIRD_PARTY_LICENSES.md` and the matching file under `helpmekaito/references/domains/`. `helpmekaito/scripts/check-routes.sh` must print `routes ok`. `tools/validate-skills.mjs` checks the skill name and description.
- Keep private data out of the repo. Use the fictional owner fixtures for examples and tests. Privacy tests read denylisted names from a local denylist file. Keep those names out of code. Run `tools/privacy-scan.mjs` before committing.
- Commit as the repo's configured Git user. Check `git config user.name` and `git config user.email`. Leave AI co-author and generated-with trailers out of commit messages.
- For a large task, give each whole module to one agent (about five in parallel), merge all branches into one, run the full suite once, hand failures to one fix agent, and ship one PR. See `helpmekaito/references/models.md`.
- Tests use local fixtures and never reach real services. Build agents run only their own test files. The lead runs the full `tests/run.sh` suite once on the combined branch. CI runs it in every test job.
- Ship working behavior with no runtime stubs.
- Write short, plain docs. Use direct sentences and skip em dashes and marketing filler.
