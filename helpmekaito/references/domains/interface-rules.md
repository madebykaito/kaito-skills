# Interface rules

Exact values and clear boundaries. Each `better-*` skill owns one discipline and hands off the rest.

| Skill | Owns |
|---|---|
| `better-ui` | Visual detail: concentric radius, shadows as borders, optical alignment, icons and their states. |
| `better-motion` | What should animate and exact values: duration, easing, scale, distance; enters, exits, icon swaps, shared layout animation, drag. |
| `better-typography` | Fonts, type scale, measure, wrapping, truncation, heading hierarchy. |
| `better-colors` | Palettes, token names, light and dark themes, contrast. Reports, does not repaint. |
| `better-accessibility` | Focus, keyboard, ARIA, forms, screen readers, reduced motion. |
| `better-layout` | Grouping, alignment, spacing, reading order, breakpoints, RTL. |
| `better-writing` | Interface text: button labels, errors, empty states, onboarding, notifications. |

Routers inside this domain:

| Skill | Use when |
|---|---|
| `better-interface` | A whole screen, flow or feature needs one ranked verdict across every discipline above. |
| `interface-review` | The review target is a change (uncommitted work, a branch, a PR), not a screen. User-invoked: suggest it. Never edits the tree. |

Overlap rules:
- One discipline named: go straight to that `better-*` skill.
- Two or more disciplines, or "review this screen": `better-interface`. Do not run the seven skills by hand.
- `better-motion` gives exact motion values inside an interface pass. Building or auditing animation as its own task is [motion.md](motion.md).
- Marketing copy is not interface text: see [writing.md](writing.md).
- `better-*` gives exact values. `impeccable`, `apple-design` and `emil-design-eng` give taste. For a polish pass, use one of each.
