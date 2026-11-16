# Interface rules

Exact values and clear boundaries. Each `better-*` skill owns one discipline and hands off the rest.

| Skill | Owns |
|---|---|
| `better-ui` | Visual detail: concentric radius, shadows as borders, icons, hover and press states, enter and exit. |
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
- Two or more disciplines, or "review this screen": `better-interface`. Do not run the six skills by hand.
- Marketing copy is not interface text: see [writing.md](writing.md).
- `better-*` gives exact values. `impeccable`, `apple-design` and `emil-design-eng` give taste. For a polish pass, use one of each.
