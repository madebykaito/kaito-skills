# Motion and design engineering

Motion in real product UI. Motion inside rendered video belongs to [video.md](video.md).

Pick by verb first.

| The user wants to | Skill |
|---|---|
| Build one animation on the web | `animate` |
| Build animation in React Native or Expo | `animate-expo` |
| Make several elements move together: stagger, hero entrance, view swap | `choreograph` |
| Build drag, swipe, sheet or dismiss interactions | `gestures` |
| Fix jank, dropped frames, or choose a cheap property | `animation-performance` |
| Find where motion is missing | `find-animation-opportunities` (read-only) |
| Audit all motion and get a prioritized plan | `improve-animations` (read-only) |
| Remove motion that slows the interface | `remove-animations` |
| Get a strict approve or block on motion code | `review-animations` (user-invoked: suggest it) |
| Name an effect they can only describe | `animation-vocabulary` |
| Work with Sonner toasts | `ask-sonner` |

Taste references, used alongside the skills above:

| Skill | Use when |
|---|---|
| `emil-design-eng` | Interaction polish on a component: press and hover states, popover origin, tooltip timing. The fallback when nothing narrower fits. |
| `apple-design` | Physical, spring-driven, interruptible motion and materials in the Apple style. |

Overlap rules:
- `animate` writes code. `find-animation-opportunities` and `improve-animations` only plan. If the user says "improve the animations" and wants edits, run `improve-animations` first and then execute its plans.
- "Feels slow" with lots of motion is `remove-animations`. "Stutters" is `animation-performance`.
- `improve-animations` writes plans meant for cheaper models. Its execution step is a good light or standard tier delegation.

Pairs:
- A gesture-driven sheet: `gestures` with `apple-design`.
- A page entrance: `choreograph`, then `animation-performance` if it drops frames.
