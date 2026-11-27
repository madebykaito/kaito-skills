# Kaito Skills

Agent skills for Claude Code and Codex. Design, motion, copy, SEO, video, and code review.

Each skill is a folder with a `SKILL.md`. The agent reads the description and loads the skill when the task matches. Or you call it by name: `/better-ui`.

The work is the proof. Run it yourself.

Works on macOS and Linux. Windows is untested. Docs: [install](docs/install.md), [using the skills](docs/using-skills.md), [how it works](docs/how-it-works.md), [troubleshooting](docs/troubleshooting.md).

## Quick start

macOS and Linux:

```bash
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
./setup
```

Windows, in PowerShell (needs Git for Windows and Node; `setup.ps1` tells you what is missing):

```powershell
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
.\setup.ps1
```

Then open a new Claude Code session and ask:

```text
/helpmekaito build a pricing page for a three-tier SaaS plan
```

```text
/better-ui polish the settings screen
```

```text
Review this diff and try to break it before I ship.
```

Call a skill by name, describe the task and let the agent pick, or let `helpmekaito` route it. See [using the skills](docs/using-skills.md).

### Claude Code packs

Install a pack in Claude Code with its marketplace command. Run the normal setup for the shared store and command-line tools.

```text
/plugin install business --marketplace madebykaito/kaito-skills
/plugin install studio --marketplace madebykaito/kaito-skills
/plugin install channels --marketplace madebykaito/kaito-skills
/plugin install design --marketplace madebykaito/kaito-skills
/plugin install engineering --marketplace madebykaito/kaito-skills
/plugin install research --marketplace madebykaito/kaito-skills
```

## Setup

`setup` needs `git`, `node` and `npm`. It does this:

- Copies every skill into `~/.kaito/store` (override with `KAITO_HOME`).
- Links skills per agent. Claude Code gets every skill, listed by name only except `helpmekaito` and your hot list. Codex gets `helpmekaito` plus the hot list. The hot list is the `hot` array in `~/.kaito/config.json`.
- Copies each skill family into one store folder and links its skills by name.
- Builds `gstack` in the store and links it for Claude Code. Needs [bun](https://bun.sh).
- Installs `@colbymchenry/codegraph` at the version in `codegraph.version` and connects it to Claude and Codex.

The name-only listing is a `skillOverrides` entry per skill in `~/.claude/settings.json`. Your other settings are kept, and `--uninstall` removes only the entries setup added.

Setup lists skills you already have under the same name as a kaito skill, and Claude Code plugins that ship one. It asks before replacing a skill (yours is moved to `~/.kaito/backup`, not deleted) or disabling a plugin. The default is no, and a no leaves your copy in place. See [install](docs/install.md#skills-and-plugins-with-the-same-name).

It also sets up tasks: which task manager you use (Trello, Plane, Linear, Obsidian, Asana, Jira, other, none), where memory lives (`memory.path`, default `~/.kaito/memory`, can be inside an Obsidian vault), Trello, Plane or Linear credentials through `kaito-tasks.sh login`, and, if you agree, a sync of your boards' structure and IDs into local memory. With no terminal this stays pending and helpmekaito finishes it in chat on first use. It never asks for a key in chat.

It asks before each optional step. With no terminal, the default is used.

| Prompt | Default |
|---|---|
| Install codegraph and connect it to Claude and Codex | yes |
| Add `.codegraph` to your global git ignore | yes |
| Allow rules for kaito scripts and `~/.kaito` in Claude settings | no |
| One-line `helpmekaito` nudge in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` | no |
| `ponytail` always-on SessionStart hook | no |
| Let Codex write to `~/.kaito` | no |

Flags:

| Flag | Effect |
|---|---|
| `--yes` | Take the default without asking. |
| `--upgrade` | Re-install without asking anything. Every earlier answer is kept and nothing new is turned on. |
| `--duplicates` | Ask again about same-name skills and plugins you said no to. |
| `--no-gstack` | Skip the gstack build and links. |
| `--no-codegraph` | Skip the codegraph install. |
| `--uninstall` | Remove our links, the store, and the settings and config edits setup made. Put back the skills and plugins setup replaced. |
| `--purge` | `--uninstall`, and delete `~/.kaito` too. |

`KAITO_ANSWERS="perms=y,nudge=n"` answers prompts by key (`codegraph`, `gitignore`, `perms`, `nudge`, `ponytail`, `codexwrite`, `tasks_manager`, `tasks_memory`, `tasks_vault`, `tasks_boards`, `tasks_discover`, `tasks_change`). It beats `--yes`. Secrets are never taken from it.

Upgrades are automatic. At the start of a task `helpmekaito` looks for a newer release, at most once a day, moves your clone to that release tag and runs `./setup --upgrade` in the background, so your task does not wait. A later task says what changed. It never asks. To be asked first or to turn it off: `sh ~/.kaito/store/helpmekaito/scripts/kaito-self.sh mode ask` or `mode off`. Or say "upgrade kaito" in chat. If you `git pull` by hand, run `./setup` again.

To uninstall, run `./setup --uninstall`, or say "uninstall kaito" in chat: it shows what would be removed and asks first.

Only one setup runs at a time. It stops before changing anything if `settings.json` or `state.json` is not valid JSON.

## Skills

### Start here

| Skill | What it does |
|---|---|
| [`helpmekaito`](helpmekaito/) | Router. Picks the right skill or chain for a task, and the model for delegated work from the agent CLIs on your machine. Keeps your tasks in sync with Trello, Plane, Linear or Obsidian and helps do them. Learns each repo, its local skills and how you work. Reports your token usage and estimated cost. Tag it: `/helpmekaito build me a pricing page`. |

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
| [`frontend-design`](frontend-design/) | Distinctive, intentional visual design for new or reshaped UI. |
| [`web-design-guidelines`](web-design-guidelines/) | Review UI code against web interface guidelines. |
| [`vercel-react-best-practices`](vercel-react-best-practices/) | React and Next.js performance rules. |
| [`app-store-screenshots`](app-store-screenshots/) | App Store screenshots built as ads with Next.js. |
| [`impeccable`](impeccable/) | Design suite: shape, critique, audit, polish, animate, harden. Hooks are opt-in: `/impeccable hooks on`. |
| [`stageshow`](stageshow/) | Faux product UI. Stills and cursor-driven demos with a React kit. |
| [`design-taste-frontend`](design-taste-frontend/) | Anti-slop company and product sites from a bundled kit, checked in a real browser. Needs Node 22+ and Chrome. |
| [`stitch-design-taste`](stitch-design-taste/) | DESIGN.md files for Google Stitch with strict type, color, and layout rules. |
| [`image-to-code`](imagegen/image-to-code/) | Generate the design images first, then build the site to match. |
| [`brandkit`](imagegen/brandkit/) | Brand-guidelines boards and logo systems as generated images. |
| [`banner-design`](banner-design/) | Banners for social, ads, hero sections, and print. Several art directions. |

### Motion and design engineering

| Skill | What it does |
|---|---|
| [`emil-design-eng`](emil-design-eng/) | Core motion rules: press states, popover origin, tooltip timing. Fallback when nothing narrower fits. |
| [`apple-design`](apple-design/) | Fluid, physical motion from Apple's design talks, for the web. |
| [`animate`](animate/animate/) | Build one web animation: whether, purpose, tool, curve, interruption, exit. |
| [`animate-expo`](animate/animate-expo/) | Same for React Native: Reanimated, Gesture Handler, haptics. |
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
| [`better-ui`](better/better-ui/) | Concentric radius, shadow-as-border, optical alignment, icon states. |
| [`better-motion`](better/better-motion/) | What should animate, with exact duration, easing, scale and distance. |
| [`better-typography`](better/better-typography/) | Type scale, measure, `text-wrap`, iOS input-zoom fixes. |
| [`better-colors`](better/better-colors/) | APCA thresholds, ramps, token grammar. Reports, does not repaint. |
| [`better-accessibility`](better/better-accessibility/) | WCAG 2.2 targets, focus order, reduced motion, live regions. |
| [`better-layout`](better/better-layout/) | Grouping, clearance, container queries, safe areas. |
| [`better-writing`](better/better-writing/) | Tone by stakes, consequence-first buttons, error rewrites. |
| [`better-interface`](better/better-interface/) | Runs every domain above on a screen. One ranked verdict. |
| [`interface-review`](better/interface-review/) | User-invoked. Change-scoped review. Never edits the tree. |

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
| [`imagegen-frontend-web`](imagegen/imagegen-frontend-web/) | Website design references, one image per section. |
| [`imagegen-frontend-mobile`](imagegen/imagegen-frontend-mobile/) | App-native screen concepts and flows for iOS and Android. |

### Media (Higgsfield)

Image, video, audio, and sites through the Higgsfield CLI. Needs a Higgsfield account and credits.

| Skill | What it does |
|---|---|
| [`higgsfield-generate`](higgsfield/higgsfield-generate/) | Images, video, 3D, audio, and ads. Default entry point. |
| [`higgsfield-soul-id`](higgsfield/higgsfield-soul-id/) | Train a Soul Character on a face for consistent identity. |
| [`higgsfield-product-photoshoot`](higgsfield/higgsfield-product-photoshoot/) | Brand-quality product photos, ads, and lifestyle shots. |
| [`higgsfield-marketplace-cards`](higgsfield/higgsfield-marketplace-cards/) | Marketplace listing images and A+ style modules. |
| [`higgsfield-youtube-thumbnail`](higgsfield/higgsfield-youtube-thumbnail/) | YouTube thumbnails and vertical covers. |
| [`higgsfield-faceless-video`](higgsfield/higgsfield-faceless-video/) | Faceless explainers, documentaries, and story videos. |
| [`higgsfield-video-explainer`](higgsfield/higgsfield-video-explainer/) | Legacy entry for the old explainer skill. Use `higgsfield-faceless-video`. |
| [`higgsfield-brandkit`](higgsfield/higgsfield-brandkit/) | Full brand systems: logo marks, palettes, mockups, decks. |
| [`higgsfield-websites`](higgsfield/higgsfield-websites/) | Build and deploy websites, apps, and games. |

### Local stills (mflux)

Images made on this Mac with mflux. No account or credits.

| Skill | What it does |
|---|---|
| [`keyframes`](keyframes/) | Styled stills and same-face stills with Z-Image-Turbo and FLUX.2 klein, sized for Reels, with a sidecar per image and an optional likeness score. |

### Media (this Mac, local)

Video and music made on your own machine through ComfyUI. No account, no credits. Needs Comfy Desktop and the model files.

| Skill | What it does |
|---|---|
| [`local-video`](local-video/) | Image to video and text to video (MiniMax H3, LTX), SeedVR2 upscale, Ken Burns from stills. |
| [`music`](music/) | Instrumental beds with ACE-Step, several takes with different styles, 48 kHz WAV. |

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
| [`schema`](schema/) | schema.org markup for rich results. |
| [`programmatic-seo`](programmatic-seo/) | SEO pages at scale from templates and data. |
| [`content-strategy`](content-strategy/) | Content that earns traffic and leads. |
| [`competitors`](competitors/) | Competitor comparison pages. |
| [`cro`](cro/) | Raise conversion on marketing pages and forms. |
| [`analytics`](analytics/) | Tracking you can act on. |
| [`cold-email`](cold-email/) | Write cold outreach emails. |
| [`prospecting`](prospecting/) | Find and qualify prospects. |
| [`social`](social/) | Plan and write social content. |
| [`emails`](emails/) | Build email sequences. |
| [`launch`](launch/) | Plan a product launch. |
| [`lead-magnets`](lead-magnets/) | Create offers that capture leads. |
| [`referrals`](referrals/) | Build referral programs. |
| [`ads`](ads/) | Plan paid advertising campaigns. |
| [`ad-creative`](ad-creative/) | Write and test ad creative. |
| [`influencer-marketing`](influencer-marketing/) | Plan creator partnerships. |
| [`marketing-plan`](marketing-plan/) | Build a marketing plan. |
| [`ab-testing`](ab-testing/) | Design marketing experiments. |
| [`churn-prevention`](churn-prevention/) | Reduce customer churn. |

### Video (HyperFrames)

Write HTML, render video.

| Skill | What it does |
|---|---|
| [`hyperframes`](hyperframes/hyperframes/) | Compositions, timelines, captions, voiceover, transitions. |
| [`hyperframes-cli`](hyperframes/hyperframes-cli/) | Init, lint, inspect, preview, render. |
| [`hyperframes-media`](hyperframes/hyperframes-media/) | TTS, transcription, background removal. |
| [`hyperframes-registry`](hyperframes/hyperframes-registry/) | Install registry blocks and components. |
| [`website-to-hyperframes`](hyperframes/website-to-hyperframes/) | Turn a website into a video. |
| [`remotion-to-hyperframes`](hyperframes/remotion-to-hyperframes/) | Port a Remotion project. |
| [`contribute-catalog`](contribute-catalog/) | Author a new registry block. |
| [`media-cleanup`](media-cleanup/) | Keep the final and the rebuild inputs, move the rest of a job folder to a dated trash, remove clean merged worktrees. |
| [`gsap`](gsap/) · [`animejs`](animejs/) · [`waapi`](waapi/) · [`css-animations`](css-animations/) · [`lottie`](lottie/) · [`three`](three/) · [`typegpu`](typegpu/) · [`tailwind`](tailwind/) | Animation and rendering adapters for HyperFrames. |

### Voice and captions (studio)

Voice and caption tracks for Reels, Shorts and ads. Local first, ffmpeg required.

| Skill | What it does |
|---|---|
| [`voiceover`](voiceover/) | Rewrites a script for the ear, then svara-TTS, Indic Parler-TTS or Sarvam per line. Writes a 48 kHz voice and timed parts. |
| [`captions`](captions/) | Caption PNGs drawn by headless Chrome so Indic conjuncts shape, timed from the parts. whisper.cpp transcripts of existing video. |

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
| [`gstack`](gstack/) | Garry Tan's workflow suite: plan reviews, `/review`, `/qa`, `/ship`, `/cso`, browser QA. Built and linked by `./setup`. |
| [`systematic-debugging`](systematic-debugging/) | Find the root cause before proposing a fix. |
| [`test-driven-development`](test-driven-development/) | Write the failing test first, then the code. |
| [`using-git-worktrees`](using-git-worktrees/) | Isolated workspace for feature work. |
| [`ponytail`](ponytail/ponytail/) | Pushes toward the smallest solution that works. Levels: lite, full, ultra. |
| [`ponytail-review`](ponytail/ponytail-review/) | Diff review for over-engineering. What to delete. |
| [`ponytail-audit`](ponytail/ponytail-audit/) | Whole-repo over-engineering audit. |
| [`ponytail-debt`](ponytail/ponytail-debt/) | Lists every `ponytail:` shortcut comment as a debt ledger. |

### Research

For long, source-heavy research projects. From research-superpowers.

| Skill | What it does |
|---|---|
| [`brainstorming-research`](brainstorming-research/) | Shapes a research question, method and scope into an approved design doc. |
| [`writing-research-plan`](writing-research-plan/) | Turns the design into a plan with a hypothesis, tasks and checks. |
| [`executing-research-plan`](executing-research-plan/) | Runs the plan task by task with subagents and a review per task. |
| [`scaffold-research-project`](scaffold-research-project/) | Creates a research project folder from the template. No terminal needed. |
| [`literature-review`](literature-review/) | Systematic literature search. Ends in a graded source guide and BibTeX. |
| [`acquire-sources`](acquire-sources/) | Downloads open-access PDFs for graded sources. Lists the rest for manual download. |
| [`add-to-library`](add-to-library/) | Adds one PDF to the shared library with verified metadata. |
| [`ingest-source`](ingest-source/) | Reads one source under a focus into a wiki page, entities and BibTeX. |
| [`wiki-lint`](wiki/wiki-lint/) | Checks wiki frontmatter, links and orphans. |
| [`semantic-wiki-review`](semantic-wiki-review/) | Audits wiki content for contradictions, stale claims and weak support. |
| [`wiki-graph`](wiki/wiki-graph/) | Maps the wiki as a graph: hubs, bridges, gaps. |
| [`drift-report`](drift-report/) | Checks the library, wiki and projects for drift. On demand. |
| [`drafting-manuscript`](drafting-manuscript/) | Plans the argument and evidence before drafting a chapter or article from the wiki. |
| [`revising-manuscript`](revising-manuscript/) | Revises an existing draft with an on-disk revision ledger. |
| [`requesting-peer-review`](requesting-peer-review/) | Two-stage review of a draft: constructive, then adversarial. |
| [`grant-finder`](grant-finder/) | Finds German and European funding programs for a topic. |
| [`finishing-a-research-project`](finishing-a-research-project/) | Final checklist before submission, publication or archive. |

### Business

Run several brands from one Mac, one owner at a time.

| Skill | What it does |
|---|---|
| [`social-publish`](social-publish/) | Publish approved LinkedIn, X and YouTube posts through a self-hosted Postiz. |
| [`business`](business/) | Owner records and the rules for business work: every job names its owner first, loads only that owner's memory, and sends nothing without your approval of the exact payload. `kaito-owner.mjs` adds, lists, binds and resolves owners. |
| [`reel-assemble`](reel-assemble/) | Assemble vertical videos and check delivery specs. |
| [`shortform-video`](shortform-video/) | Generate shorts with MoneyPrinterTurbo and run preflight. |
| [`instagram-publish`](instagram/instagram-publish/) | Publishes approved Instagram images, Reels, Stories and carousels now or at a scheduled time. |
| [`instagram-insights`](instagram/instagram-insights/) | Pulls Instagram account and media metrics into the business ledger. |
| [`email-send`](email-send/) | Drafts email and sends approved messages through SMTP, SES or listmonk. |
| [`support-inbox`](support-inbox/) | Triages an owner’s inbox, ranks FAQ reply drafts and adds items to the today queue. |
| [`sales-qualify`](sales/sales-qualify/) | Qualify leads and record account briefs. |
| [`sales-outreach`](sales/sales-outreach/) | Draft outreach for qualified leads. |
| [`sales-review`](sales/sales-review/) | Review sales material before sending. |
| [`sales-retro`](sales/sales-retro/) | Record outcomes and improve the next sales cycle. |
| [`marketing-brief`](marketing/marketing-brief/) | Sets the buyer, message, proof, action and target before drafting. |
| [`marketing-review`](marketing/marketing-review/) | Checks a draft against its brief and owner evidence. |
| [`marketing-retro`](marketing/marketing-retro/) | Compares actual results with the brief and records lessons. |
| [`money`](money/) | Owner-scoped quotes, GST invoices, credit notes and payment reminders. Issues approved documents with a gapless financial-year series. |
| [`channel-retro`](channel-retro/) | Review a week of website and Instagram metrics for an owner. |

## Known limits

- `reel-assemble` needs ffmpeg and ffprobe. `shortform-video` needs a running local MoneyPrinterTurbo API, local material and configured TTS; Edge TTS uses a cloud service.

- Website metrics in `channel-retro` need an Umami API key. Instagram metrics come from the Insights pull.
- Twenty sync needs a configured Kaito Lead object and a per-owner API key. See [Twenty setup](business/references/twenty.md).

- Some skills overlap. `better-*` gives exact values. `impeccable`, `apple-design`, and `emil-design-eng` give taste. Use both.
- `shaders-cursor-ripples` needs a paid package.
- `minimal-zine-poster` needs a Gemini API key. Without it you get a prompt, not an image.
- Node and npm are required for `./setup`.
- Windows: not tested by CI; reports and fixes are welcome. Setup runs in Git Bash (`setup.ps1` starts it). A user folder with a space in its name is not supported; use WSL. gstack tools are blocked by Smart App Control.
- Bun is required only for `gstack`. Use `--no-gstack` to skip it.
- Higgsfield skills need a Higgsfield account and credits.
- `voiceover` needs ffmpeg and Python 3, and a TTS engine: svara-TTS through mlx-audio (Apple silicon), Indic Parler-TTS, or Sarvam with an API key. Sarvam is a cloud call and needs the owner's consent. svara ignores tone. Run one heavy model at a time.
- `captions` needs ffmpeg and a Chromium browser (Chrome, Chromium or Edge; or set `CHROME`). Transcripts need whisper.cpp (`whisper-cli`) and a ggml model, which are not installed for you.
- `keyframes` needs mflux (`uv tool install mflux`), Python 3 and ffmpeg. The first run of each model downloads several GB of weights to the Hugging Face cache, and a run needs about 16 GB of free RAM, so run one heavy model at a time. The pinned weights (Z-Image-Turbo, FLUX.2 klein 4B) are Apache-2.0; non-commercial weights are refused unless you pass `--noncommercial-ok`. The likeness score needs a python with dlib that you set up yourself (`LIKENESS_PYTHON`).
- `local-video` and `music` run on Apple silicon through ComfyUI (Comfy Desktop) and need the model files downloaded by hand: MiniMax H3 is about 37 GB, SeedVR2 about 4 GB, ACE-Step about 10 GB, LTX is optional. They want a Mac with 48 GB; one heavy model runs at a time and a run is refused (exit 3) when free memory is below its need. An H3 clip takes about 9 minutes and a SeedVR2 upscale about 17 minutes per 5 s shot.
- MiniMax H3 is under the MiniMax H3 Community License: not for use in the US, EU, UK or South Korea, and commercial use of the outputs needs a MiniMax licence. `local-video` prints it and needs `--license-ok`. The Ken Burns command and ffmpeg need no licence.
- Skill hooks (`careful`, `freeze`, `guard`) work on Claude Code only.
- Skill hooks last only for the session that loaded the skill.
- Research hooks are not installed. `drift-report` runs on demand.
- `business` owners are set up by hand with `kaito-owner.mjs add`. With several owners, work outside a bound folder stops until you name one. Scheduled sends use the Mac LaunchAgent. The optional Worker requires a Cloudflare deployment and owner consent. [Scheduler setup](business/references/scheduler.md)
- Instagram publishing and Insights need your own Meta app and a professional account. Publishing also needs a public HTTPS media host and ffprobe for video.
- `social-publish` needs a configured Postiz server, platform integrations and an API key.
- `email-send` delivery needs an owner key file for SMTP, SES or listmonk. `support-inbox` needs a Maildir or mbox export, or an owner IMAP key file. Both use Python 3.
- Sales voice profiles need a sent-mail mbox or Maildir export and Python 3; review the generated profile before use.
- `money` needs an owner billing profile and a Chromium-family browser for PDFs.
- Some research skills use optional MCP servers for citation checks. They run without them.
- Research scripts need Python 3.10 or newer. `grant-finder`, `literature-review` and `requesting-peer-review` mention upstream `research-skills/` files that are not bundled; they fall back to live search.
- Memory is read-only on Codex unless you allow `~/.kaito` as a writable root in setup.
- `helpmekaito` only delegates to models your machine can reach. Other vendors need their CLI (`codex`, `cursor-agent`, `opencode`, `gemini`) or an API key. Tiers come from a rule on the model family name; a model the rule cannot place (Grok, most open-weight ids) falls back to the host's model.
- Ollama is a local runner for bulk drafts and translation (`kaito-ollama.mjs`). It needs a running Ollama server (`OLLAMA_HOST`) and at least one pulled model; the `ollama` CLI is not required. Small local models need a native read for Bengali or Hindi.
- The usage report's prices are list-price estimates from a file refreshed at each release, not a bill. Cursor usage cannot be read.
- Trello needs an API key and token (`kaito-tasks.sh login`). They live in `~/.kaito/.env`. An agent running as you can still read that file; setup only stops auto-allowing it.
- Plane needs a personal API key and your workspace slug (`kaito-tasks.sh login`), stored the same way; set a URL there for a self-hosted Plane. Without a key it works through the Plane MCP connector. A project with more than 3000 work items needs a module mapping.
- Plane has no checklists, so a checklist item is a sub work item.
- Linear needs a personal API key (`kaito-tasks.sh login`), stored the same way, or read from `~/.config/linear/.env`. Without a key it works through the Linear connector. The API allows 2,500 requests an hour; a team with more than 2,000 open issues needs a project mapping. A checklist item is a sub-issue.
- A repo's trackers and whether to track work there are remembered per repo and per machine, in the memory folder. Checkouts and worktrees of one repo share them when the repo has a network remote; a repo without one is remembered per checkout. A second machine asks again.
- First-use detection only reads local evidence (branch, commits, docs, stored board names). It finds nothing for a tracker whose structure was never synced, and then helpmekaito asks.
- Asana, Jira and other task managers work only through their MCP connector.
- Moving `memory.path` later is manual: move the folder, then change the key.
- Automatic upgrades use the clone setup ran from and install only release tags. The clone must be on its default branch with no modified or staged tracked files.
- Disabling a plugin that ships a same-name skill turns off the whole plugin, not just that skill. Matching is by exact name only.
- If a skill fires when it shouldn't, that's a bug. Open an issue.

## Contributing

Fixes and new skills are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md), then pick an issue labeled [`good first issue`](https://github.com/madebykaito/kaito-skills/labels/good%20first%20issue) or open one. Security reports go through [`SECURITY.md`](SECURITY.md). Everyone follows the [Code of Conduct](CODE_OF_CONDUCT.md). Changes are listed in [`CHANGELOG.md`](CHANGELOG.md).

## Credits

Many skills here are adapted from other open-source work. Sources and their licenses are in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## License

MIT for Kaito Junior's own work. See [`LICENSE`](LICENSE). Bundled third-party skills keep their original licenses.

---

Kaito Junior · [github.com/madebykaito](https://github.com/madebykaito) · hello@madebykaito.com
