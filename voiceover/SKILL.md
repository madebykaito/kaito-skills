---
name: voiceover
description: Turn a script into a spoken voiceover for a Reel, Short, ad or explainer. Rewrites the script for the ear, then makes one TTS request per line (svara-TTS, Indic Parler-TTS or Sarvam), trims, adds breaths, levels to -16 LUFS in two passes and writes voice.wav at 48 kHz plus a timed parts JSON. Bengali, Hindi, English and other Indian languages. Use for voiceover, narration, TTS, "read this script aloud".
---

# Voiceover

Script in, `voice.wav` and a timed `parts.json` out. The parts JSON is what `captions` and the reel assembler read, so the timing is real: it comes from the length of each rendered line.

## 1. Rewrite for the ear first

The agent does this before any TTS call. Written copy sounds stiff when read aloud.

- One idea per line. Keep a line under about 12 words; the engines drift and hang on long ones.
- Short sentences. Split at the comma if you would take a breath there.
- Spell numbers and symbols the way they are said: "₹499" becomes "four hundred and ninety-nine rupees", "20%" becomes "twenty percent", "24/7" becomes "all day, every day". In Bengali or Hindi write the number words in that script.
- No abbreviations, hashtags, emoji, URLs or brackets. Say "dot com" only if the brand wants it said.
- Write in the script of the language. Keep one language per line; a brand name in Latin letters is fine if the engine handles it, otherwise spell it phonetically.
- One tone per line: `neutral`, `warm`, `excited`, `calm` or `serious`. If a line needs two, split it.
- `pause_after` is the silence after the line in seconds. Use 0.2 inside a thought, 0.4 to 0.6 before a turn or the call to action.
- Read the result out loud in your head. Cut anything you would stumble on.

Show the rewritten lines to the user when they own the wording, and wait for a yes before spending render time.

## 2. Lines file

```json
{
  "language": "bn-IN",
  "voice": "Bengali (Female)",
  "lines": [
    {"text": "...", "tone": "calm", "pause_after": 0.4},
    {"text": "...", "tone": "warm", "pause_after": 0.3}
  ]
}
```

`language` is a BCP-47 code (`bn-IN`, `en-IN`, `hi-IN`). `voice` is optional.

## 3. Run

```bash
python3 <store>/voiceover/scripts/voiceover.py --lines lines.json --out-dir <dir> [--engine svara|parler|sarvam] [--owner <id>]
```

Output folder: `voice.wav` (48 kHz mono, -16 LUFS), `parts.json`, `lines/lineNN.wav`. With an owner, the folder is `$KAITO_HOME/owners/<id>/studio/<job>/`.

Engines:

| Engine | What | Needs |
|---|---|---|
| `svara` (default) | svara-TTS v1 through mlx-audio. Local, free, Apache-2.0. | `SVARA_PYTHON` (default `~/AI-Tools/tts/mlx/bin/python`), model `kenpath/svara-tts-v1` in the Hugging Face cache |
| `parler` | Indic Parler-TTS. Local. Tone becomes the voice description. | `PARLER_HOME` or `PARLER_PYTHON` (default `~/AI-Tools/tts/parler`) with `parler_tts`, and the model `ai4bharat/indic-parler-tts` in the Hugging Face cache (set `PARLER_MODEL` for another) |
| `sarvam` | Sarvam Bulbul. Cloud: the script text leaves the machine. | `--owner`, key file `~/.config/sarvam/<owner>.env` with `SARVAM_API_KEY=`, and the owner's consent |

Rules:
- Take the heavy-model lock before svara or parler on a shared Mac: one heavy model at a time.
- Do not put emotion tags such as `<happy>` in the text. They made svara hang, so the script strips them. Tone is not applied by svara; pick `parler` or `sarvam` when tone matters.
- Sarvam needs consent. If `business/scripts/kaito-engines.mjs` is installed, the script runs its `consent` check for the owner. Without that tool it refuses unless `--cloud-ok`, which you pass only when the owner has agreed in this conversation. Never print or log the key.
- One request per line keeps each line's tone and lets one bad line be redone alone.
- Exit codes: 0 ok, 1 error, 2 usage, 3 consent needed, 4 engine or ffmpeg not found.

## 4. parts.json

```json
{
  "version": 1,
  "engine": "svara",
  "language": "bn-IN",
  "sample_rate": 48000,
  "lufs": -16.0,
  "voice": "voice.wav",
  "duration": 11.4,
  "lines": [
    {"index": 0, "text": "...", "tone": "calm", "start": 0.12, "end": 2.31, "pause_after": 0.4,
     "clip_start": 0.0, "clip_end": 2.71, "file": "lines/line00.wav", "duration": 2.71}
  ]
}
```

`start` and `end` are when the speech is heard in `voice.wav`: use them for captions. `clip_start` and `clip_end` bound the whole line clip (a short breath before the speech, the pause after it): use them to cut shots, since one clip's `clip_end` is the next clip's `clip_start` and `duration` is their difference. Paths are relative to the folder holding `parts.json`. The line durations add up to the length of `voice.wav`.

Next: `captions` to burn the lines in, or the reel assembler to cut shots to them.
