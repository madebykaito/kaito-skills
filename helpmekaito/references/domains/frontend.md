# Design and frontend

Building and reviewing interfaces as a whole. For one visual treatment see [visual-styles.md](visual-styles.md). For exact rules per discipline see [interface-rules.md](interface-rules.md). For motion see [motion.md](motion.md).

| Skill | Use when | Not when |
|---|---|---|
| `frontend-design` | Building a new page, component or app UI that must not look generic. The default builder. | Reviewing existing UI. |
| `impeccable` | A full design pass on a frontend: shape, critique, audit, polish, harden, or a `DESIGN.md` design system. Also native iOS and Android screens. | A single narrow rule question: use the matching `better-*` skill. |
| `web-design-guidelines` | A quick compliance review of UI code against the Web Interface Guidelines. | A ranked, cross-discipline verdict: `better-interface`. |
| `vercel-react-best-practices` | Writing or reviewing React or Next.js code for performance: data fetching, bundles, re-renders. | Local-first desktop apps: see [engineering.md](engineering.md). |
| `tailwind-v4` | Setting up, upgrading or debugging Tailwind v4 in a real project. | Tailwind inside a HyperFrames video: `tailwind` in [video.md](video.md). |
| `app-store-screenshots` | App Store marketing screenshots for an iOS app. | Faux product UI for a web page: `stageshow`. |
| `stageshow` | Faux product UI for marketing: app windows, dashboards, phones, cursor-driven demos. | The real product UI. |
| `prototype` | The user wants several real variants of one UI piece to flip between. User-invoked: suggest it, the user types `/prototype`. | One clear direction is already chosen. |
| `pick-ui-library` | Choosing a library for a frontend task. User-invoked: suggest it. | The project already has the library. |
| `learn-taste` | Turning this session's design corrections into lasting rules. User-invoked: suggest it. | No corrections were given. |
| `break-ui` | Stress-testing a UI with worst-case data. | Functional QA: `gstack` in [engineering.md](engineering.md). |
| `mobile-native` | A web app feels like a website on a phone: sticky hover, `100vh`, input zoom, safe areas. | React Native: `animate-expo` in [motion.md](motion.md). |

Overlap rule: `frontend-design` and `impeccable` both build. Use `frontend-design` for a fresh build from a brief. Use `impeccable` when there is an existing frontend to critique, polish or systematize, or when the user wants its staged workflow.

Pairs:
- New UI: `frontend-design`, then `better-interface` for the verdict, then `break-ui`.
- Existing UI that looks off: `impeccable`, with `better-ui` for exact values.
