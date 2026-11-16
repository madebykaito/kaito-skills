# Kaito Skills

Agent skills for Claude Code and Codex. Design, motion, copy, SEO, video, and code review.

Each skill is a folder with a `SKILL.md`. The agent reads the description and loads the skill when the task matches. Or you call it by name: `/better-ui`.

The work is the proof. Run it yourself.

## Install

```bash
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
for d in */; do ln -sfn "$PWD/${d%/}" ~/.claude/skills/"${d%/}"; done
```

One skill only:

```bash
ln -s "$PWD/better-ui" ~/.claude/skills/better-ui
```

Codex reads `~/.codex/skills`. Same command, different target.

## Skills

### Writing and copy

| Skill | What it does |
|---|---|
| [`ogilvy`](ogilvy/) | Advertising principles: positioning, headlines, promises, brand voice. |
| [`copywriting`](copywriting/) | Marketing copy that is clear and drives action. |
| [`copy-editing`](copy-editing/) | Improve existing copy in focused editing passes. |
| [`stop-slop`](stop-slop/) | Remove AI writing patterns from prose. |

### Design and frontend

| Skill | What it does |
|---|---|
| [`frontend-design`](frontend-design/) | Distinctive, production-grade frontend interfaces. |
| [`web-design-guidelines`](web-design-guidelines/) | Review UI code against web interface guidelines. |
| [`vercel-react-best-practices`](vercel-react-best-practices/) | React and Next.js performance rules. |
| [`app-store-screenshots`](app-store-screenshots/) | App Store screenshots built as ads with Next.js. |
| [`impeccable`](impeccable/) | Design suite: shape, critique, audit, polish, animate, harden. Hooks are opt-in: `/impeccable hooks on`. |
| [`stageshow`](stageshow/) | Faux product UI. Stills and cursor-driven demos with a React kit. |

### Motion and design engineering

| Skill | What it does |
|---|---|
| [`emil-design-eng`](emil-design-eng/) | Core motion rules: press states, popover origin, tooltip timing. Fallback when nothing narrower fits. |
| [`apple-design`](apple-design/) | Fluid, physical motion from Apple's design talks, for the web. |
| [`animate`](animate/) | Build one web animation: whether, purpose, tool, curve, interruption, exit. |
| [`animate-expo`](animate-expo/) | Same for React Native: Reanimated, Gesture Handler, haptics. |
| [`choreograph`](choreograph/) | Several elements moving together: stagger, lead and follow. |
| [`gestures`](gestures/) | Drag, swipe, and sheets that track the finger and carry velocity. |
| [`animation-performance`](animation-performance/) | Find why motion drops frames. |
| [`mobile-native`](mobile-native/) | Web apps on phones: sticky hover, `100vh`, input zoom, safe areas. |
| [`break-ui`](break-ui/) | Worst-case realistic data. Reports every break with its fix. |
| [`find-animation-opportunities`](find-animation-opportunities/) | Read-only. Where motion would help, and what must not move. |
| [`improve-animations`](improve-animations/) | Read-only motion audit into prioritized plans. |
| [`remove-animations`](remove-animations/) | Removes motion that slows the interface. |
| [`animation-vocabulary`](animation-vocabulary/) | "What's it called when..." to the exact term. |
| [`ask-sonner`](ask-sonner/) | Sonner toasts: setup, recipes, common fixes. |
| [`review-animations`](review-animations/) | User-invoked. Strict approve or block motion review. |
| [`prototype`](prototype/) | User-invoked. Several real variants behind a live picker. |
| [`pick-ui-library`](pick-ui-library/) | User-invoked. Library picks after checking `package.json`. |
| [`learn-taste`](learn-taste/) | User-invoked. Turns design corrections into rules. |

### Interface rules

Exact values, clear boundaries. Each domain owns its rules and hands off the rest.

| Skill | What it does |
|---|---|
| [`better-ui`](better-ui/) | Concentric radius, shadow-as-border, icon cross-fades, press scale. |
| [`better-typography`](better-typography/) | Type scale, measure, `text-wrap`, iOS input-zoom fixes. |
| [`better-colors`](better-colors/) | APCA thresholds, ramps, token grammar. Reports, does not repaint. |
| [`better-accessibility`](better-accessibility/) | WCAG 2.2 targets, focus order, reduced motion, live regions. |
| [`better-layout`](better-layout/) | Grouping, clearance, container queries, safe areas. |
| [`better-writing`](better-writing/) | Tone by stakes, consequence-first buttons, error rewrites. |
| [`better-interface`](better-interface/) | Runs every domain above on a screen. One ranked verdict. |
| [`interface-review`](interface-review/) | User-invoked. Change-scoped review. Never edits the tree. |

### Visual styles

| Skill | What it does |
|---|---|
| [`visual-style-presets`](visual-style-presets/) | Nine complete style directions with surfaces, accent rule, motif. |
| [`tailwind-v4`](tailwind-v4/) | CSS-first config, `@theme` tokens, v3 to v4 migration. |
| [`beautiful-shadows`](beautiful-shadows/) | Three layered elevation shadows. |
| [`skeuomorphic-ui`](skeuomorphic-ui/) | Raised and pressed surfaces, embossed text. |
| [`glass-dark-ui`](glass-dark-ui/) | Dark glass with readable contrast. |
| [`container-lines`](container-lines/) | Container guides aligned to the real content edge. |
| [`framed-grid-layout`](framed-grid-layout/) | Corner frames from layered gradients. |
| [`corner-diagonals`](corner-diagonals/) | Chamfered corners with correct `clip-path` math. |
| [`css-border-gradient`](css-border-gradient/) | Gradient borders two ways. |
| [`progressive-blur`](progressive-blur/) | Layered backdrop blur with WebKit fallbacks. |
| [`mesh-gradient-dark-blue-clean`](mesh-gradient-dark-blue-clean/) | Procedural dark navy mesh background. |
| [`liquid-metal-border`](liquid-metal-border/) | Animated metallic borders. |
| [`beam-glow-states`](beam-glow-states/) | Border-beam loading, active, and error states. |
| [`reveal-hover-effect`](reveal-hover-effect/) | Cursor-masked reveal on hover. |
| [`staggered-word-reveal`](staggered-word-reveal/) | Word-by-word reveal, accessible, no dependencies. |
| [`webgl-laser`](webgl-laser/) | Raw WebGL volumetric laser beam. |
| [`thinking-orbs`](thinking-orbs/) | Animated AI thinking-state orbs. |
| [`shaders-cursor-ripples`](shaders-cursor-ripples/) | Cursor ripple shader. Depends on a paid, closed-source package. |

### Image generation

| Skill | What it does |
|---|---|
| [`minimal-zine-poster`](minimal-zine-poster/) | Theme to minimal zine poster, then generates the image. Needs `GEMINI_API_KEY`. |

### Page types

| Skill | What it does |
|---|---|
| [`landing-page`](landing-page/) | Single-intent landing page structure and headlines. |
| [`pricing-page`](pricing-page/) | Value-metric pricing pages. |
| [`product-proof-saas`](product-proof-saas/) | Honest AI product demos. No faked speed. |
| [`operational-enterprise-ai`](operational-enterprise-ai/) | Enterprise buyer pages: permissions, approval, audit, rollback. |
| [`documentary-brutalist-agency`](documentary-brutalist-agency/) | Editorial agency site with real accessibility limits. |
| [`editorial-portfolio-chapters`](editorial-portfolio-chapters/) | Chaptered portfolio with exact grid and timing. |
| [`service-booking-flow`](service-booking-flow/) | Booking flows that survive stale slots and failed payments. |

### SEO and marketing

| Skill | What it does |
|---|---|
| [`seo-audit`](seo-audit/) | Find SEO issues, with fixes. |
| [`schema-markup`](schema-markup/) | schema.org markup for rich results. |
| [`programmatic-seo`](programmatic-seo/) | SEO pages at scale from templates and data. |
| [`content-strategy`](content-strategy/) | Content that earns traffic and leads. |
| [`competitor-alternatives`](competitor-alternatives/) | Competitor comparison pages. |
| [`page-cro`](page-cro/) | Raise conversion on marketing pages. |
| [`analytics-tracking`](analytics-tracking/) | Tracking you can act on. |

### Video (HyperFrames)

Write HTML, render video.

| Skill | What it does |
|---|---|
| [`hyperframes`](hyperframes/) | Compositions, timelines, captions, voiceover, transitions. |
| [`hyperframes-cli`](hyperframes-cli/) | Init, lint, inspect, preview, render. |
| [`hyperframes-media`](hyperframes-media/) | TTS, transcription, background removal. |
| [`hyperframes-registry`](hyperframes-registry/) | Install registry blocks and components. |
| [`website-to-hyperframes`](website-to-hyperframes/) | Turn a website into a video. |
| [`remotion-to-hyperframes`](remotion-to-hyperframes/) | Port a Remotion project. |
| [`contribute-catalog`](contribute-catalog/) | Author a new registry block. |
| [`gsap`](gsap/) · [`animejs`](animejs/) · [`waapi`](waapi/) · [`css-animations`](css-animations/) · [`lottie`](lottie/) · [`three`](three/) · [`typegpu`](typegpu/) · [`tailwind`](tailwind/) | Animation and rendering adapters for HyperFrames. |

### Performance and architecture

| Skill | What it does |
|---|---|
| [`conductor-rewrite-performance`](conductor-rewrite-performance/) | Local-first React desktop apps: re-render cascades, slow lists. |
| [`linear-local-first-architecture`](linear-local-first-architecture/) | Local-first sync and optimistic updates. No spinners. |

### Code review

| Skill | What it does |
|---|---|
| [`adversarial-review`](adversarial-review/) | Assume the diff is broken. Report only findings that survive a refutation pass. |

### Dev workflow

| Skill | What it does |
|---|---|
| [`gstack`](gstack/) | Garry Tan's workflow suite: plan reviews, `/review`, `/qa`, `/ship`, `/cso`, browser QA. Run `./setup` inside `gstack/` after cloning. |

## Known limits

- Some skills overlap. `better-*` gives exact values. `impeccable`, `apple-design`, and `emil-design-eng` give taste. Use both.
- `shaders-cursor-ripples` needs a paid package.
- `minimal-zine-poster` needs a Gemini API key. Without it you get a prompt, not an image.
- `gstack` needs [bun](https://bun.sh) and its own `./setup`, which builds the browser and installs its sub-skills.
- If a skill fires when it shouldn't, that's a bug. Open an issue.

## Credits

Many skills here are adapted from other open-source work. Sources and their licenses are in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## License

MIT for Kaito Junior's own work. See [`LICENSE`](LICENSE). Bundled third-party skills keep their original licenses.

---

Kaito Junior · [github.com/madebykaito](https://github.com/madebykaito) · hello@madebykaito.com
