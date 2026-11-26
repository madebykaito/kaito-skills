# Engines

Every capability the business skills need (voice, captions, images, video, email and so on) maps to a list of providers, local first. `kaito-engines.mjs` reads that list, checks what is installed, and tells an agent which provider to use. Studio and channel agents call it instead of hard-coding a path.

```
node <store>/business/scripts/kaito-engines.mjs doctor [--json] [--capability c] [--owner id]
node <store>/business/scripts/kaito-engines.mjs pick <capability> [--owner id] [--allow-cloud] [--force] [--json]
node <store>/business/scripts/kaito-engines.mjs consent <provider> --owner id [--grant|--revoke|--status]
node <store>/business/scripts/kaito-engines.mjs enable|disable <provider>
```

Exit codes: 0 ok, 1 error, 2 usage, 3 needs a human decision, 4 none usable.

## Files

- `business/engines/registry.json`: the defaults that ship with kaito-skills. Do not edit it on a machine.
- `$KAITO_HOME/engines.json`: your overrides. `KAITO_HOME` defaults to `~/.kaito`.

## Registry format

`capabilities` maps a capability to provider ids in preference order. `providers` maps an id to:

| Field | Meaning |
|---|---|
| `name`, `kind` | `kind` is `local` or `cloud`. Cloud means owner data leaves the machine |
| `enabled` | Default true. Providers with non-commercial or restricted weights ship `false` |
| `heavy` | Loads a large model. `pick` checks RAM before returning it |
| `env` | The environment variable that overrides the path, key file or URL |
| `checks` | All must pass. See below |
| `key.pattern` | Key file path with `<owner>`. Cloud providers only. The doctor checks the path, never opens the file |
| `min_ram_gb`, `disk_gb` | Estimates for planning, not measurements |
| `license.id`, `license.commercial`, `license.note` | The weight or service license and whether commercial use is cleared |
| `source` | URL to read the license and setup from |

Check types: `bin` (names on `PATH` plus candidate paths, optional `version` args), `path`, `python` (an interpreter, optional `module` to import), `hf` (model ids in the Hugging Face cache, `HF_HUB_CACHE` or `HF_HOME`), `http` (a URL, or `ports` on 127.0.0.1 with a `path`; any answer counts), `docker` (an image is pulled), `always`. `{"any": [...]}` passes when one inside passes. A `*` in a path matches within one folder level.

## Environment variables

Each provider reads one variable. It wins over `engines.json`, which wins over the registry default. A value that points at nothing makes the provider missing: it does not fall back to `PATH`.

| Provider | Variable | Expects |
|---|---|---|
| svara | `SVARA_PYTHON` | Python in the mlx-audio env |
| indic-parler | `PARLER_PYTHON` | Python in the Parler env |
| sarvam | `SARVAM_KEY_FILE` | Key file |
| edge-tts | `EDGE_TTS_BIN` | Binary |
| chromium | `CHROME_HEADLESS` | Headless Chromium or Chrome binary |
| whisper-cpp | `WHISPER_CPP_BIN` | Binary |
| mlx-whisper | `MLX_WHISPER_BIN` | Binary |
| mflux-z-image-turbo | `MFLUX_Z_IMAGE_BIN` | Binary |
| flux2-klein-4b | `MFLUX_FLUX2_BIN` | Binary |
| dlib | `DLIB_PYTHON` | Python with dlib |
| comfyui | `COMFY_URL` | URL, for example `http://127.0.0.1:8189` |
| wan-comfyui | `WAN_MODEL` | Model file |
| minimax-h3 | `MINIMAX_H3_SCRIPT` | `render_h3_q5.py` |
| ltx | `LTX_DIR` | Folder |
| seedvr2 | `SEEDVR2_SCRIPT` | `upscale.py` |
| acestep | `ACESTEP_SCRIPT` | `music.py` |
| moneyprinterturbo | `MONEYPRINTERTURBO_MAIN` | `main.py` |
| ollama | `OLLAMA_BIN` | Binary |
| host-llm | none | Always present |
| instagram-graph | `INSTAGRAM_KEY_FILE` | Key file |
| postiz | `POSTIZ_URL` | URL |
| smtp | `SMTP_KEY_FILE` | Key file |
| ses | `SES_KEY_FILE` | Key file |
| listmonk | `LISTMONK_URL` | URL |
| umami | `UMAMI_URL` | URL |
| twenty | `TWENTY_URL` | URL |
| ffmpeg | `FFMPEG_BIN` | Binary |
| docker | `DOCKER_BIN` | Binary |

A URL that is not on this machine (not 127.0.0.1, localhost or ::1) makes the provider count as cloud, so consent applies. URLs are printed without credentials or query strings.

A key-file variable names one file, so it fits a single owner. With several owners, leave it unset and use the `<owner>` pattern.

## Overrides: `$KAITO_HOME/engines.json`

```json
{
  "capabilities": { "tts": ["sarvam", "svara"] },
  "providers": {
    "ollama": { "enabled": false },
    "whisper-cpp": { "path": "/opt/tools/whisper-cli" },
    "ltx": { "enabled": true }
  }
}
```

Merge rules:

1. Start from the registry.
2. `capabilities.<cap>` lists provider ids. They go first, in your order. Providers you leave out follow in the default order. To drop one, disable it. Unknown ids are skipped with a warning.
3. `providers.<id>` merges field by field into the registry entry. `license` merges one level deeper. `checks` and `key` are replaced whole if given.
4. `path` (or the first of `paths`) replaces the primary location: the binary or file, the key file pattern, or the URL if it starts with `http`. The environment variable beats it.
5. `id` and `kind` of a built-in provider cannot be changed. An id that is not in the registry is a new provider. It needs `kind` and a non-empty `checks` list or a `key`, and it joins a capability only if `capabilities` lists it. A new provider starts disabled unless its `license.commercial` is true.
6. `kaito-engines enable|disable <id>` writes the `enabled` flag for you.

Invalid JSON stops the run with exit 1. The file is never rewritten except by `enable` and `disable`.

## What `pick` does

`pick` walks the capability's providers in order and returns the first one that passes:

1. Disabled providers are skipped. That is how non-commercial weights stay off until you opt in.
2. Missing providers are skipped (not installed, no key file, nothing answering).
3. Cloud providers are skipped unless `--allow-cloud` is given. With it, `--owner` is required and the owner must have granted consent for that provider (below). Otherwise `pick` exits 3 and names the consent command.
4. A `heavy` local provider is refused, exit 3, if the machine has less total RAM than it needs, or less free plus reclaimable RAM (on macOS free, inactive, purgeable and speculative pages; on Linux `MemAvailable`). The reason says how much is missing. `--force` overrides it. A refused provider does not stop the walk: a later provider in the list can still be returned.

Output is `provider=`, `path=`, `kind=`, `license=` and `commercial=` lines, or one JSON object with `--json`. When the provider is not cleared for commercial use, a warning goes to stderr. Exit 4 means nothing usable, with one reason per provider on stderr.

Only one heavy model should run at a time. `pick` checks RAM, not other running agents, so take the heavy lock described in the build contract before loading a model.

## Consent rule

Owner assets (photos, voice samples, drafts, customer data) never go to a cloud provider by default. The owner grants consent per provider:

```
kaito-engines.mjs consent sarvam --owner lumen-tea --grant
kaito-engines.mjs consent sarvam --owner lumen-tea --revoke
```

It is recorded in `$KAITO_HOME/owners/<id>/consent.json` as `{"version":1,"cloud":{"sarvam":{"granted":true,"at":"..."}}}`. Consent covers one provider for one owner. Only the founder grants it, in the founder's words: an agent never runs `--grant` on its own. A revoke takes effect on the next `pick`. Consent to a provider does not make it the default: `--allow-cloud` is still needed on each call.

## Doctor

`doctor` prints one line per provider: state (`present`, `missing`, `off`), kind, RAM needed against this machine, disk needed, license with the commercial flag, whether a key file exists, and where it is. A final block lists which provider each capability will use today. Without `--owner`, key files are matched against the pattern for any owner and shown as the pattern, never as a name. RAM and disk figures in the registry are estimates.

## Add a provider

1. Add an entry under `providers` in `registry.json` with every field above. Set `license.commercial` from the license text, not from memory. If it is false, set `enabled: false`.
2. Add its id to the right `capabilities` list in preference order, local first.
3. Add its variable to the table above and read it in the studio script that calls it.
4. Run `tests/run.sh tests/engines.test.sh`. The registry test fails on a missing field, an unused provider, or a non-commercial provider that is enabled.
5. Run `kaito-engines.mjs doctor --capability <cap>` on a machine that has it and one that does not.

For a private provider, add it to your own `engines.json` instead.
