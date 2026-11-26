---
name: captions
description: Make a caption track for a video as transparent PNGs, one per caption, drawn by headless Chrome so Bengali, Hindi and other Indic conjuncts shape correctly, timed from a voiceover parts JSON, with an ffmpeg overlay filter and a concat list. Also transcribes existing video with whisper.cpp. Use for captions, subtitles, burned-in text, "transcribe this video".
---

# Captions

Two jobs: draw captions from timed lines, or get timed lines out of a video that already has speech.

## Render a caption track

```bash
python3 <store>/captions/scripts/captions.py render --parts <dir>/parts.json --out-dir <dir>/captions
```

Input is the `parts.json` from `voiceover`, or the `transcript.json` from `transcribe` below. Each line needs `text`, `start` and `end` in seconds. A line may carry `caption` to show different text from what is spoken.

Why Chrome: ffmpeg's text filters do not shape Indic scripts, so conjuncts such as ক্ষ, ন্দ্র and স্ত্র break apart. Chrome's text engine joins them. Always look at one frame before a long render.

Output in `--out-dir`:
- `cap00.png` and on: 1080 px wide, transparent, one per caption (default box 1080x360).
- `blank.png`: the same size, empty.
- `captions.json`: each caption with `text`, `start`, `end`, `file`.
- `concat.txt`: an ffconcat list of the whole track, `blank.png` in the gaps. `-f concat -i concat.txt` gives a timed caption stream.
- `overlay.filter` and `overlay.args`: an ffmpeg overlay chain and its `-i` inputs.

Use the overlay chain like this, with the video as input 0:

```bash
ffmpeg -i video.mp4 $(tr '\n' ' ' < captions/overlay.args) -filter_complex "$(cat captions/overlay.filter)" -map "[vout]" -map 0:a out.mp4
```

Paths with spaces break that shell expansion; build the argument list in code instead. If the other skill already has more inputs, pass `--first-input N` (the ffmpeg index of the first PNG) and `--base-label` (the label to overlay on, default `0:v`). The last label is `[vout]`.

Options: `--y` top of the caption box in the frame (default 1380, for 1080x1920), `--height`, `--font-size`, `--font-family` (a CSS stack; the default lists Noto Sans and macOS Indic fonts), `--color`, `--stroke`, `--max-words N` to split long lines into timed chunks, `--lead` to shift all times, `--test-text` to render one test frame from a string.

Text fills the box width and wraps only when the next word does not fit.

Chrome is found at `CHROME`, then Google Chrome, Chromium or Edge on macOS, then a headless shell from puppeteer or Playwright. Missing: exit 4 with how to fix it.

## Transcribe existing video

```bash
python3 <store>/captions/scripts/captions.py transcribe --video in.mp4 --out-dir <dir> [--model <ggml file>] [--lang auto]
```

Uses whisper.cpp: `whisper-cli` on PATH, or `WHISPER_CPP` set to the binary or its folder, and a ggml model from `--model` or `WHISPER_MODEL`. Writes `transcript.json` (the same shape as `parts.json`, `file` is null) and `whisper.srt`. Feed `transcript.json` to `render` to re-caption a video.

Not installed: exit 4 with install steps. The script never installs it. Small models misread Indic languages; use `small` or larger and read the result before burning it in.

Exit codes: 0 ok, 1 error, 2 usage, 4 Chrome, whisper.cpp or model not found.
