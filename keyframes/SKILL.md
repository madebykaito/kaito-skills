---
name: keyframes
description: "Make still images on this Mac with local mflux models: a styled still from a prompt and an optional brand style file, or a same-face still from reference photos of one person. Sizes for Reels (1080x1920), a sidecar JSON per image with prompt, seed and weight license, and an optional likeness score. Use for Reel keyframes, shot stills, brand photos and consistent-character scenes when no cloud image service is wanted. Not for Higgsfield or Gemini images."
---

# keyframes

Local stills for shots and posts. One script, `scripts/keyframes.py`, Python 3 standard library only. The models run as external mflux programs.

| Command | What it makes | Model |
|---|---|---|
| `still` | A styled still from a prompt. | Z-Image-Turbo, `mflux-generate-z-image-turbo` |
| `same-face` | A new scene with the same person, from one or more reference photos. | FLUX.2 klein 4B edit, `mflux-generate-flux2-edit` |
| `score` | How close a candidate face is to the references. Optional. | dlib through `LIKENESS_PYTHON` |
| `licenses` | The pinned weight licenses. | none |

Run it as `python3 <store>/keyframes/scripts/keyframes.py <command>`. `<store>` is `~/.kaito/store`.

## Before you run

- One heavy model at a time. The script waits for `/tmp/kaito-heavy.lock` before starting mflux and stops it after 30 minutes. Image models need about 16 GB free; close other model runs first. Check with the user if a TTS, video or ComfyUI job is running.
- The first run of each model downloads its weights to the Hugging Face cache (several GB). Say so before a first run.
- A run takes about 40 s to 2 min. Run it in the background and wait.
- Engines are found in `MFLUX_BIN_DIR` (default `~/.local/bin`). A missing engine exits 4 and says how to install mflux. A Reel size needs ffmpeg (`FFMPEG_BIN` or `PATH`), or pass `--native`.

## Styled still

```
python3 keyframes.py still --prompt "a cup of Darjeeling tea on a wooden table at dawn" \
  --style-file brand.md --size reel --seed 1126 --out-dir ./frames --name tea
```

- `--style-file` is the owner's brand text. The first section whose heading names image, visual, photo or style is appended to the prompt, else the whole file, capped at 900 characters.
- `--size`: `reel` (1080x1920), `square` (1080x1080), `portrait` (1080x1350), `landscape` (1920x1080) or `WIDTHxHEIGHT`. The model draws at its own size (a Reel is 864x1536, exactly 1.25 times smaller) and ffmpeg scales and crops to the final size. The model-size copy stays as `<name>.native.png`. `--native` skips the ffmpeg step.
- Without `--seed` a random one is picked. It is always recorded. Reuse a seed to repeat an image.
- Output goes to `--out-dir`, or `$KAITO_HOME/owners/<owner>/studio/keyframes/` with `--owner`.
- Write the prompt as a plain description of the picture: subject, place, light, lens feel. No text in the image; models spell badly.

## Same face

```
python3 keyframes.py same-face --ref ref1.png ref2.png --prompt "She reads at a cafe window" \
  --size portrait --out-dir ./frames --name cafe
```

- Needs at least one real reference photo of the person. Two different text prompts of a described person are not the same face. If there is no photo, make one reference portrait with `still`, then use that file as `--ref` for every later scene.
- Use clear, front-facing references with the face large in the frame. More references from different angles hold the face better.
- The script adds "The same person as in the reference image." before the prompt. `--no-prefix` removes it.
- Only use photos of people who agreed to it.

## Likeness score (optional)

```
LIKENESS_PYTHON=~/.venvs/likeness/bin/python python3 keyframes.py score --ref ref1.png ref2.png --candidate frames/cafe.png
```

Prints the mean and minimum face distance. Lower is closer: under 0.60 is the same-person line and 0.30 or less is a strong match. It is a guide. Look at the image too. Without dlib it exits 4 and prints the install steps; this skill never installs it.

## Licenses

Each image's sidecar JSON (`<name>.json`) records the prompt, user prompt, style file, seed, model, weights repo, weight license, a `commercial` flag, sizes, reference hashes, seconds and an AI-generated flag. The script prints the license before every run.

| Model | Weights | License | Commercial |
|---|---|---|---|
| `z-image-turbo` | Tongyi-MAI/Z-Image-Turbo | Apache-2.0 | yes |
| `flux2-klein-4b` | black-forest-labs/FLUX.2-klein-4B | Apache-2.0 | yes |
| `flux2-klein-9b` | black-forest-labs/FLUX.2-klein-9B | FLUX non-commercial | no |

Checked against the Hugging Face model cards on 2026-11-26. A non-commercial weight is refused (exit 3) unless `--noncommercial-ok`. Never pass that flag for client or paid work. Another model name is refused as not pinned. To add one, read its card and add a row to `MODELS` in the script.

## Exit codes

0 ok, 1 error, 2 usage, 3 refused for license, 4 engine or tool not found.

## After

Look at the image before you hand it on. Reel framing, hands and any text in the image are the usual faults. The stills are inputs for Reel shots and Ken Burns moves.
