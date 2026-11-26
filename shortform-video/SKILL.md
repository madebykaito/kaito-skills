---
name: shortform-video
description: Generate a short video from a topic with local MoneyPrinterTurbo and preflight the resulting file.
---

# Shortform video

For brand work resolve the owner through `business` first. Start MoneyPrinterTurbo's local API with its own setup and select an Edge voice. Supply the narration from the host LLM, or use a locally installed Ollama model. Provide local material paths visible to the server. No automatic publishing takes place.

```sh
python3 <store>/shortform-video/scripts/shortform-video.py --topic 'Tea brewing' --script 'Host-written narration.' --material clip.mp4 --audio voice.wav --out short.mp4
```

Use `--ollama-model MODEL` instead of `--script` for local script generation. `--api` defaults to `http://127.0.0.1:8080`; only local HTTP is accepted. `--voice`, `--target` and `--timeout` override the defaults. `--audio` supplies local narration instead of TTS and disables MoneyPrinterTurbo subtitles. MoneyPrinterTurbo handles its configured TTS and rendering; Edge TTS sends text to Microsoft. Without `--audio`, pass `--owner` after the owner has granted `edge-tts` cloud consent in the engine registry. Preflight failure returns nonzero and leaves the file for inspection. Review the video and use the business ledger before publishing.
