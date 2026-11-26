---
name: music
description: "Make instrumental music beds on this Mac with ACE-Step through ComfyUI, with no cloud and no vocals. Several takes per request, each with its own style tags and seed, written as 48 kHz WAV with a sidecar JSON. Use when the user wants background music, a bed under a voiceover or a reel, or a few options to choose from."
license: MIT
---

# music

Instrumental beds from ACE-Step 1.5 turbo, run locally through ComfyUI. A 30 s take takes about 20 seconds once the model is loaded.

Script: `scripts/music.py` (Python 3, standard library only). It needs the `local-video` skill too, because it uses that skill's ComfyUI client (`local-video/scripts/comfy.py`).

## Use

```bash
python3 scripts/music.py --style "warm lo-fi, soft keys" --seconds 30 --takes 3 --out-dir out --name bed
```

This writes `out/bed-take1.wav`, `bed-take2.wav`, `bed-take3.wav`, each with a `.json` sidecar, and prints `take1=<path>` and so on.

- `--takes N` (1 to 12): each take adds a different style modifier to your base style and uses its own seed (`--seed` for take 1, then +7919 per take). Past the built-in list of seven modifiers, styles repeat with new seeds. `--variants "sitar|marimba|pads"` replaces the list with your own, one per take.
- `--seconds` 5 to 240, `--bpm` (66), `--key` ("D minor"), `--steps` (8).
- Output is WAV, 48 kHz, stereo, 16 bit. A file ComfyUI returns in another format or rate is converted with ffmpeg; ffmpeg is needed for that.
- The sidecar holds the final tags, seed, bpm, key, length and elapsed time, so a take can be rebuilt.
- `--dry-run` prints the planned takes as JSON and runs nothing. `--start` opens Comfy Desktop when no ComfyUI answers. `--url` or `COMFY_URL` points at one you started.

Beds are instrumental by design: the lyrics field is fixed to `[Instrumental]`. For a bed under speech keep the style plain (soft pads, light percussion) and mix it well below the voice; listen to the takes before choosing, as they differ a lot.

## Rules for this Mac

Same as `local-video`: one heavy model at a time through the lock `/tmp/kaito-heavy.lock`, `/free` before and after, and a refusal with exit 3 and the numbers when free memory is below the need (14 GB for ACE-Step; `--need-gb` overrides it). The model stays loaded between the takes of one run.

Exit codes: 0 ok, 1 error, 2 usage, 3 needs a decision (low memory, lock timeout), 4 not found (checkpoint, ComfyUI, ffmpeg, the `local-video` skill).

## Setup

ComfyUI (Comfy Desktop) with the checkpoint `checkpoints/ace_step_1.5_turbo_aio.safetensors` (about 10 GB). ACE-Step is released by ACE Studio and StepFun under an open licence; read the model card of the checkpoint you download before commercial use.
