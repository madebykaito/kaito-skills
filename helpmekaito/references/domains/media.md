# Media: images, video, brand assets

Generated images, video, audio and brand systems. For video built from HTML see [video.md](video.md). For a poster image see `minimal-zine-poster` in [visual-styles.md](visual-styles.md).

## Higgsfield

Every `higgsfield-*` skill runs the Higgsfield CLI and needs a Higgsfield account with credits. Say so before the first run. Without them, say so and offer a non-Higgsfield route if one fits.

| Skill | Use when |
|---|---|
| `higgsfield-generate` | One image, video, 3D asset, sound or music clip; editing or animating an image; an ad or UGC clip. The default. |
| `higgsfield-soul-id` | Training a model on a person's face for consistent identity. Then `higgsfield-generate` uses it. |
| `higgsfield-product-photoshoot` | Brand product photos: studio, lifestyle, model holding the product, ad creative. |
| `higgsfield-marketplace-cards` | Marketplace listing images: main image, secondary cards, A+ modules. |
| `higgsfield-youtube-thumbnail` | A YouTube thumbnail or vertical video cover. |
| `higgsfield-faceless-video` | A finished narrated faceless video: explainer, documentary, story, kids' song. |
| `higgsfield-video-explainer` | Only when the user names it or continues its old workflow. New explainers go to `higgsfield-faceless-video`. |
| `higgsfield-brandkit` | A full brand system made with Higgsfield: palette, logo, type, mockups, brandbook PPTX or PDF. |
| `higgsfield-websites` | A site, app or game built and hosted on Higgsfield, or game art such as spritesheets. Only when the user wants Higgsfield hosting. |

## Design reference images

| Skill | Use when |
|---|---|
| `imagegen-frontend-web` | Design reference images for a website, one image per section, for a coding model to rebuild. |
| `imagegen-frontend-mobile` | The same for mobile app screens. |
| `brandkit` | A brand-guidelines board or identity deck as images: logo concepts, type, mockups. |

## Cleanup

| Skill | Use when |
|---|---|
| `media-cleanup` | A studio job is done and its folder is full of takes, keyframes and intermediate clips; freeing disk space; emptying old trash; removing git worktrees that are clean and merged. Dry run first, moves to a dated trash, never deletes without a yes. |

Overlap rules:
- `brandkit` makes presentation boards to look at. `higgsfield-brandkit` makes working files: SVG marks, palettes, PPTX or PDF brandbooks. Boards or a moodboard: `brandkit`. Files to hand a team: `higgsfield-brandkit`.
- A product shot for a listing is `higgsfield-marketplace-cards`. Anywhere else it is `higgsfield-product-photoshoot`.
- A landing page in the user's own repo is [pages.md](pages.md). `higgsfield-websites` only when it lives on Higgsfield.
- A narrated video from a topic is `higgsfield-faceless-video`. A video composed from HTML is `hyperframes` in [video.md](video.md).
- Images and then code to match is `image-to-code` in [frontend.md](frontend.md).
