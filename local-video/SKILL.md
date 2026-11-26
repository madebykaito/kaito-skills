---
name: local-video
description: "Make video on this Mac with no cloud: image to video and text to video with MiniMax H3 (and LTX when its weights are installed), SeedVR2 upscale, and Ken Burns moves from stills with ffmpeg. Runs through ComfyUI, one heavy model at a time. Use when the user wants a local clip from a still or a prompt, a 2x upscale of a clip, or a camera move on a photo, and does not want to pay a video API."
license: MIT
---

# local-video

Local video through ComfyUI on a Mac, plus ffmpeg Ken Burns. Nothing leaves the machine.

Script: `scripts/local_video.py` (Python 3, standard library only). It uses the shared client `scripts/comfy.py`, which the `music` skill uses too.

## Pick the engine

| Want | Command | Engine | Time on a 48 GB M-series Mac |
|---|---|---|---|
| A 5 s clip from a still | `i2v` | MiniMax H3 (default) or LTX | about 9 min at 352x608 |
| A 5 s clip from text | `t2v` | MiniMax H3 | about 9 min |
| A sharper clip | `upscale` | SeedVR2 3B | very slow: about 17 min per 5 s shot |
| A camera move on a photo, to the length of a voice line | `kenburns` | ffmpeg zoompan | seconds |

Ken Burns is the cheap path. Say so when a still with a slow move is enough: a generated clip costs minutes of the whole machine.

## Commands

```bash
S=<skill folder>/scripts/local_video.py
python3 $S i2v --image still.png --prompt "steam rises from the cup, slow push in" --license-ok --out-dir out
python3 $S t2v --prompt "a tea garden at dawn, mist, handheld" --aspect 9:16 --license-ok --out-dir out
python3 $S upscale --video out/clip.mp4 --mult 2 --out-dir out
python3 $S kenburns --image still.png --duration 4 --move push_in --out-dir out
python3 $S kenburns --shots shots.json --parts parts.json --out-dir out
```

Each result is written with a sidecar `<name>.json` (engine, parameters, seed, elapsed seconds, licence) and the script prints `video=<path>`.

Options that matter:
- `--seconds 5` (H3 and LTX), `--megapixels 0.2` (H3 canvas: 0.2 is 352x608 in portrait), `--seed`, `--steps` (H3 default 8).
- `--name` sets the file name. `--out-dir` is required in practice; the default is `./local-video-out`.
- `--dry-run` prints the plan as JSON and runs nothing.
- `--start` opens Comfy Desktop when no ComfyUI answers. `--url` or `COMFY_URL` points at a local ComfyUI you started yourself.
- `--need-gb N` overrides the memory the run needs. A very high value is a safe way to test the refusal.

Ken Burns moves: `push_in`, `pull_out`, `pan_left`, `pan_right`, `tilt_up`, `tilt_down`, `drift`. Size defaults to 1080x1920 at 24 fps.

`shots.json` is a list of `{"image": "a.png", "move": "pan_left", "duration": 3}`. A shot can take `"line": N` and `"share": 0.5` instead of a duration, and then `--parts` supplies the length: a JSON list (or `{"parts": [...]}`) whose items are seconds, or objects with `duration`, `seconds`, or `start` and `end`.

## Rules for this Mac

1. One heavy model at a time, across every agent. The script takes the lock `/tmp/kaito-heavy.lock` (`mkdir`), waits for it, and removes it at the end, also on failure. Do not run two heavy jobs by hand next to it. If a process dies or ComfyUI cannot confirm a job stopped, check ComfyUI and remove the lock directory by hand before retrying.
2. It POSTs ComfyUI `/free` before the model loads and again when done, so the next engine starts clean. After a manual ComfyUI session, run `python3 scripts/comfy.py free`.
3. It reads free memory from `/system_stats` and refuses to start when the workflow's need is higher (exit 3, with the numbers). It never lets the Mac swap. Defaults: H3 26 GB, SeedVR2 14 GB, LTX 16 GB.
4. The Wan 2.2 family needs the `euler` sampler; `uni_pc` corrupts video on Apple GPUs. H3 uses `er_sde`, set in the template.

Exit codes: 0 ok, 1 error, 2 usage, 3 needs a decision (licence not accepted, low memory, lock timeout), 4 not found (engine files, node pack, ComfyUI, ffmpeg).

## Setup

- ComfyUI (Comfy Desktop) with the node packs ComfyUI-GGUF, ComfyUI-AppleSilicon-FP8 and ComfyUI-PlagueKind-Nodes, as in the Bambushu recipe for MiniMax H3 on Apple silicon.
- H3 files in the ComfyUI model folders: `diffusion_models/MiniMax-H3-FL2VA-Pruned-Q5_K_M.gguf`, `loras/H3-PK-Parasyte-Turbo.safetensors`, `text_encoders/qwen3vl-32B-MiniMax-H3-Q4_K_M.gguf`, `vae/minimax_h3_video_vae_fp16.safetensors`, `vae/minimax_h3_audio_vae_fp32.safetensors`. About 37 GB.
- SeedVR2: `diffusion_models/seedvr2_3b_int8_convrot.safetensors` and `vae/seedvr2_ema_vae_fp16.safetensors`.
- LTX: a checkpoint (default name `ltx-video-2b-v0.9.5.safetensors`, or pass `--ltx-checkpoint`) and `text_encoders/t5xxl_fp16.safetensors`. If they are missing the command exits 4 with the file name. The LTX workflow has not been run on the author's Mac.
- A missing file or node pack is reported before anything loads.
- `--start` only opens the Comfy Desktop app. If its ComfyUI engine is not installed or not launched inside the app, nothing answers and the command exits 4 after the wait; launch ComfyUI from the app, or start it yourself and set `COMFY_URL`.

## Licences

MiniMax H3 is under the MiniMax H3 Community License. It excludes some countries (the US, EU, UK and South Korea), asks for a separate authorisation above US$20M in revenue, and treats commercial use of the outputs as needing a MiniMax licence. The script prints this and refuses to run H3 without `--license-ok`. Tell the user before client or paid work and let them read the licence themselves; do not pass the flag on their behalf for paid work they have not cleared.

LTX and SeedVR2 weights carry their own licences; the sidecar JSON records which.

The workflow templates in `workflows/` follow the structure of the ComfyUI MiniMax H3 template (MIT, Comfy Org) as retuned in the MacMax recipe (MIT, MAD IT).

## Not here

Still images, voice, captions and final assembly come from other tools. This skill only makes and moves clips.
