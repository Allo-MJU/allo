---
name: ALLO Book Collection UI
description: Landscape open-book visual system for the Unity phone dex and inventory screens.
colors:
  book-ink: "#493D2D"
  book-muted: "#756244"
  book-gold: "#C69137"
  book-paper: "#F5E4C4"
  book-outline: "#6D533B"
  button-primary: "#E5BC65"
  button-secondary: "#EDDBB7"
  bookmark-dex-active: "#A95A35"
  bookmark-idle: "#66734F"
  selected-slot: "#E8CD8D"
typography:
  page-title:
    fontFamily: "Do Hyeon, sans-serif"
    fontSize: "29px"
  slot-label:
    fontFamily: "Do Hyeon, sans-serif"
    fontSize: "21px"
  button-label:
    fontFamily: "Do Hyeon, sans-serif"
    fontSize: "21px"
  quantity:
    fontFamily: "Do Hyeon, sans-serif"
    fontSize: "18px"
components:
  button-primary:
    backgroundColor: "{colors.button-primary}"
    textColor: "{colors.book-ink}"
    height: "52px"
  button-secondary:
    backgroundColor: "{colors.button-secondary}"
    textColor: "{colors.book-ink}"
    height: "52px"
---

# Design System: ALLO Book Collection UI

## Overview

**Creative North Star: "The Field Guide Book"**

The dex and inventory are browsed as one warm, illustrated field guide. Paper, a visible spine and page layers give the collection a physical book frame; the UI remains a compact game interface inside it. This scope covers only the Unity phone dex, inventory and their shared book navigation. It does not prescribe the home, camp, cabin or other routes.

**Key Characteristics:**
- Landscape book with paired pages
- Warm paper, brown ink and restrained gold selection
- Compact Korean game controls

## Colors

The palette uses dark brown for readable copy, muted brown for secondary text, and gold to mark selection and primary actions.

### Primary
- **Book Ink** (`{colors.book-ink}`): Main page headings, copy and enabled button labels.
- **Book Gold** (`{colors.book-gold}`): Selected-slot border and corner marker.

### Secondary
- **Primary Button Gold** (`{colors.button-primary}`): Primary book action surface.
- **Dex Bookmark Clay** (`{colors.bookmark-dex-active}`): Active dex bookmark.
- **Bookmark Moss** (`{colors.bookmark-idle}`): Inactive bookmark.

### Neutral
- **Book Paper** (`{colors.book-paper}`): Fallback page surface behind the open-book artwork.
- **Book Muted** (`{colors.book-muted}`): Supporting copy and portrait fallback.
- **Book Outline** (`{colors.book-outline}`): Brown outline tone.
- **Secondary Button Paper** (`{colors.button-secondary}`): Standard book action surface.
- **Selected Slot Paper** (`{colors.selected-slot}`): Selected slot fill.

## Typography

**Display Font:** Do Hyeon (fallback: sans-serif)
**Body Font:** Do Hyeon (fallback: sans-serif)

**Character:** The embedded Do Hyeon-Regular font provides a friendly, sturdy Korean game voice. The title and slot labels use compact sizes suited to the paired-page layout.

### Hierarchy
- **Page title** (29px): Book page headings.
- **Button and slot label** (21px): Actions and collection labels.
- **Quantity** (18px, auto-fit down to 14px): Item count badges.

## Layout

The UI is landscape and uses a height-matched 1600×720 reference canvas (`matchWidthOrHeight = 1`) inside a safe-area root. The shared open-book image is 1881×836 px, with the spine near 44% of its width. Page content stays inside left-page normalized x=.055–.414 and right-page x=.49–.95, y=.095–.91. The narrow center band protects the spine; page titles and scroll viewports reserve their own vertical room. Tabs sit just outside the book's left edge. Each page scrolls vertically with a visible, low-contrast indicator; dex and inventory sub-tabs retain separate scroll positions. Inventory offers material and food tabs. Right-page grids use two to four columns according to available page width.

## Elevation & Depth

Depth comes from the open-book illustration, spine, page edges and a dimmed reading backdrop. Content surfaces remain restrained and rely on tonal contrast and fine outlines rather than layered card shadows.

## Shapes

Book pages follow the artwork's rectangular page field. Slots use a fine brown outline; the selected slot gains a gold outline and small corner marker. Portraits may be clipped to a circular mask when face crops are available.

## Components

- **Book bookmarks:** Vertical dex and inventory tabs at the book's left edge; active and inactive states use separate earth tones.
- **Book buttons:** 52px tall; primary action uses gold, ordinary action uses pale paper, and labels use book ink. Disabled text uses muted brown.
- **Collection slots:** Portrait or item art, a short caption and optional top-right quantity. Selection uses a gold outline, pale gold fill and corner mark.
- **Page scroller:** Clamped vertical scrolling with an auto-hiding, non-interactive indicator.

## Do's and Don'ts

### Do:
- **Do** keep dex and inventory content within the open-book page bounds and preserve the center spine gap.
- **Do** keep quantity badges legible and selection visible through both fill and outline.
- **Do** use the explicit “그림 준비 중” fallback when portrait art is unavailable.

### Don't:
- **Don't** apply this book treatment to other app routes; this system is scoped to dex and inventory.
- **Don't** replace ALLO collection data or introduce content from the reference game images.
- **Don't** present missing character art as finished portrait artwork; the current upstream set contains only 6 of 12 character images.
