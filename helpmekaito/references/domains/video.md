# Video (HyperFrames)

Write HTML, render video. Everything here is for HyperFrames compositions, not product UI.

Entry points:

| Skill | Use when |
|---|---|
| `hyperframes` | Authoring any composition: scenes, captions, voiceover, audio-reactive visuals, transitions. The default. |
| `website-to-hyperframes` | The user gives a URL and wants a video, promo or social ad from that site. |
| `remotion-to-hyperframes` | The user explicitly asks to port an existing Remotion project. Only then. |

Tooling:

| Skill | Use when |
|---|---|
| `hyperframes-cli` | Running the pinned HyperFrames CLI: init, check, inspect, preview, render, doctor. |
| `hyperframes-media` | Sourcing and making media, including voiceover, transcription, and background removal. |
| `hyperframes-registry` | Installing registry blocks and components with `hyperframes add`. |
| `contribute-catalog` | Contributing a new block upstream to the public catalog. Only then. |

Studio (make a voice and captions for a Reel, Short or ad, local first):

| Skill | Use when |
|---|---|
| `voiceover` | A script must be spoken: rewrite for the ear, TTS per line (svara, Indic Parler, Sarvam), `voice.wav` at 48 kHz and a timed parts JSON. |
| `captions` | A video needs caption PNGs that shape Bengali and other Indic scripts, timed from the voiceover parts, or a whisper.cpp transcript of existing video. |

Animation adapters, picked by the library in use:

| Skill | Library |
|---|---|
| `gsap` | GSAP |
| `animejs` | Anime.js |
| `waapi` | Web Animations API |
| `css-animations` | CSS keyframes |
| `lottie` | Lottie and dotLottie |
| `three` | Three.js and WebGL |
| `typegpu` | TypeGPU and WebGPU |
| `tailwind` | Tailwind v4 browser runtime inside a composition |

Rules:
- Load `hyperframes` first, then one adapter. Do not load several adapters unless the composition mixes libraries.
- `tailwind` here is for compositions only. A normal project uses `tailwind-v4`.
- `gsap` here is the HyperFrames reference. For GSAP in product UI, use `animate` in [motion.md](motion.md).
- A product demo video usually needs faux UI first: `stageshow`, then `hyperframes`.
