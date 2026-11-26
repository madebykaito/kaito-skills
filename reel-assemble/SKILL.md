---
name: reel-assemble
description: Assemble vertical short videos from shots, voiceover parts, timed caption PNGs and music, and check delivery media specs.
---

# Reel assemble

For a brand, resolve the owner with `business` first. Use the voiceover `parts.json` and captions `captions.json` without rewriting them. Run:

```sh
python3 <store>/reel-assemble/scripts/reel-assemble.py --shots clip.mp4 still.png --parts voice/parts.json --captions captions/captions.json --bed music.wav --out reel.mp4
python3 <store>/reel-assemble/scripts/media-spec.py check reel.mp4 --target ig-reels
```

The other targets are `yt-shorts` and `linkedin`. The script loops short shots and the bed, crossfades shots, ducks music under voice and ends at voice duration. `--fade` sets seconds. Review the output before proposing it to the ledger. See [specs](references/specs.md). Requires ffmpeg and ffprobe.
