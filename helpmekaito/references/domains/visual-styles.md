# Visual styles and effects

Each skill here is one look or one effect. Route only when the user names the look or the effect. Do not add an effect nobody asked for.

Whole-direction skills:

| Skill | Use when |
|---|---|
| `visual-style-presets` | The user wants a complete style direction (dark glass, warm paper, editorial grid and so on) or has no direction yet. Start here when unsure. |
| `mesh-gradient-dark-blue-clean` | A dark navy, mesh-gradient design system across the whole page. |
| `glass-dark-ui` | Dark glassmorphism with readable contrast. |
| `skeuomorphic-ui` | Tactile, pressed, embossed surfaces. |

Single treatments:

| Skill | Effect |
|---|---|
| `beautiful-shadows` | Layered neutral elevation shadows in Tailwind. |
| `css-border-gradient` | Subtle gradient borders. |
| `corner-diagonals` | Chamfered, clipped corners. |
| `container-lines` | Vertical container guide lines with corner squares. |
| `framed-grid-layout` | Framed grid with visible boundary lines and corner brackets. |
| `progressive-blur` | Layered edge blur. |
| `liquid-metal-border` | Animated metallic WebGL borders (`metal-fx`). |
| `beam-glow-states` | Border-beam loading, active and focus states. |
| `thinking-orbs` | AI working and status orbs in place of a spinner. |
| `reveal-hover-effect` | Cursor-following reveal of a second image. |
| `staggered-word-reveal` | Word-by-word text reveal on scroll. |
| `webgl-laser` | Full-screen laser beam background. Laser only. |
| `shaders-cursor-ripples` | Cursor ripple distortion over an image. Needs a paid package: say so before using it. |

Image generation:

| Skill | Use when |
|---|---|
| `minimal-zine-poster` | A theme or sentence becomes a minimal zine-style poster image. Needs `GEMINI_API_KEY`. Without it the user gets a prompt, not an image. |

Overlap rules:
- `container-lines` adds guides to an existing layout. `framed-grid-layout` is the whole layout.
- `css-border-gradient` is static and quiet. `liquid-metal-border` and `beam-glow-states` move.
- A spotlight that reveals an image is `reveal-hover-effect`. A water-like distortion is `shaders-cursor-ripples`.
