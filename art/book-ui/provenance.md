# Open book UI background provenance

- Created: 2026-11-14
- Tool: built-in `image_gen.imagegen`, transparent_background=true; no reference images supplied.
- Source: `/Users/seokamoto/.codex/generated_images/01a1d8d9-1283-7b40-9a18-f40148fc8677/exec-931b8fa6-d963-4874-892c-05b705a0f5e8.png`
- Asset: `unity/allo_explore/Assets/Resources/Book/OpenBook.png`
- Metadata: exact generation prompt embedded with Impeccable after copying; pixel content unchanged.
- Dimensions: 1881 × 836 pixels (2.25:1), PNG with alpha. Copied without pixel edits.
- Unity: Default Texture2D, no mipmaps, Clamp, alpha transparency enabled; load with Resources.Load<Texture2D>("Book/OpenBook").
- Visual QA: inspected using view_image. Empty cream pages, brown leather rim, mild paper edge texture, transparent outer margin; no text or icons. Generated spine lies around x44%, close to requested x45%.
- Recommended clean overlay bounds (normalized canvas coordinates from top left): left x0.05–0.415, right x0.49–0.95, y0.075–0.91. Keep headings/buttons away from gutter and rounded corners.

## Exact generation prompt

Use case: stylized-concept
Asset type: Unity game UI background sprite, an EMPTY open adventure journal.
Primary request: Original illustrated open book, horizontal landscape about 2.25:1 aspect ratio, straight-on orthographic top-down. Book fills canvas almost completely with a small transparent margin. Two blank cream paper pages with a narrow warm brown leather cover rim. The binding spine is at EXACTLY 45 percent of canvas width; left page is 45 percent, right page 55 percent. Entire pages are flat readable UI surfaces. Left usable blank rectangle x4%-42%, right usable blank rectangle x49%-96%, both y6%-94%. Keep these areas extremely clean almost solid warm ivory, with very subtle paper texture only, suitable for overlaying game interface text and a grid of icons.
Style/medium: Polished friendly hand-painted children's adventure game journal, softly shaded 2D illustration, restrained texture, elegant rounded page corners, subtle layered paper edges and mild wear limited to outer edges. Warm cream paper and medium brown cover.
Constraints: GENUINELY transparent outside book, alpha background. Spine vertical, narrow, flat, subtle shading confined to center gutter. No dramatic perspective, no large curling pages, no cast shadow far outside book. No environment. NO TEXT, NO writing, NO lines, NO symbols, NO characters, NO illustrations on pages, NO badges, NO tabs, NO bookmarks, NO decorative objects, NO interface elements. Empty usable paper is the central requirement. Do not copy any existing game's artwork.
