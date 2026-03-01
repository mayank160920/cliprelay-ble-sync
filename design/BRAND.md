# ClipRelay Brand & Design Language

## Color Palette

### Brand Tokens (5 core colors)
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `aqua`            | `#00FFD5` | Primary brand color, icon backgrounds    |
| `aqua-gradient`   | `#00DDC0` | Gradient endpoint, secondary accent      |
| `teal`            | `#00796B` | Primary accent, text, icons              |
| `board-dark`      | `#0A3A34` | Clipboard board fill (dark theme)        |
| `board-darker`    | `#082A26` | Clipboard body fill (dark theme)         |

### UI Theme (app-specific, not brand)
| Token               | Hex       | Usage                                  |
|---------------------|-----------|----------------------------------------|
| `bg-top-unpaired`   | `#E8F5F3` | Top section, unpaired state            |
| `bg-top-connected`  | `#D6F5EF` | Top section, connected state           |
| `bg-bottom-unpaired`| `#F0F0F0` | Bottom section, unpaired state         |
| `bg-bottom-connected`| `#F0F7F5`| Bottom section, connected state        |

### Dark UI Surfaces (used in logo-concepts pages)
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `bg`              | `#0A0A0F` | Page background                          |
| `surface`         | `#13131A` | Card / panel surface                     |
| `border`          | `#1E1E2A` | Subtle borders                           |
| `text`            | `#E8E8ED` | Primary text                             |
| `text-dim`        | `#6B6B7B` | Secondary / dimmed text                  |

---

## Gradients

| Name              | Definition                                      | Usage                    |
|-------------------|-------------------------------------------------|--------------------------|
| Aqua Gradient     | `linear-gradient(135deg, #00FFD5, #00DDC0)`     | Icon backgrounds         |
| Board Gradient    | `linear-gradient(to bottom-right, #0A3A34, #082A26)` | Clipboard fill (dark) |
| Arc Gradient      | `linear-gradient(to bottom-right, #00FFD5, #00DDC0)` | Beam arc strokes     |
| Glow              | `feGaussianBlur stdDeviation="3"` + merge       | Beam arc glow effect     |
| Title Gradient    | `linear-gradient(135deg, #fff 30%, #00FFD5)`    | Display heading text     |

---

## Logo: "Beam Simplified" Concept

The logo is a **clipboard board with clamp** (representing clipboard/paste) combined with **two concentric signal arcs** emanating to the right (representing wireless BLE data transfer). Text lines have been removed for clarity at small sizes.

### Anatomy
```
  ┌────┐            Clamp (narrowed, centered on board)
  │╶──╴│            Rivet
┌─┴────┴─┐
│          │  ))    Board + 2 beam arcs
│          │  )
│          │
│          │
└──────────┘
```

### Canonical Geometry (120x120 viewBox)
```
Board:       rect x="14" y="26" w="58" h="78" rx="10"
Clamp base:  rect x="26" y="18" w="34" h="12" rx="5"
Clamp top:   rect x="32" y="14" w="22" h="8"  rx="4"
Rivet:       rect x="39" y="22" w="8"  h="3"  rx="1.5"
Arc 1 (inner): path d="M78 44 A 24 24 0 0 1 78 82"
Arc 2 (outer): path d="M90 35 A 36 36 0 0 1 90 91"
```

All variants share these exact coordinates. Only styling (fills, strokes, effects) differs.

### SVG Variants (in this directory)

| File                     | Size     | Description                                     |
|--------------------------|----------|-------------------------------------------------|
| `logo-mark.svg`          | 120x120  | Bare canonical geometry, no fills/strokes        |
| `logo-full-dark.svg`     | 120x120  | Dark board + aqua gradient arcs + glow           |
| `logo-full-light.svg`    | 120x120  | Aqua-filled board + teal arcs + drop shadow      |
| `logo-android-icon.svg`  | 120x120  | Aqua circle bg, dark board, black arcs           |
| `logo-menubar.svg`       | 120x120  | Stroke-only monochrome, for macOS menu bar       |
| `logo-share-icon.svg`    | 120x120  | Aqua circle bg, thicker arcs for small sizes     |

### Design Rules
- **On dark backgrounds**: Use aqua-colored strokes/fills with glow filter
- **On light backgrounds**: Use aqua-filled board with teal arcs and drop shadow
- **On colored (aqua) backgrounds**: Use black arcs, dark semi-transparent fills
- **Menu bar / monochrome**: Stroke-only in `#00FFD5` (or template-mode white)
- Beam arcs always face **right** (signal radiating outward)
- Two arcs at radii 24 and 36 (in the 120-unit viewBox)
- Arcs are semicircular (`A` commands spanning ~180 degrees)
- Stroke-linecap is always `round`

---

## Animation

### Beam Pulse (CSS)
Two staggered keyframe animations give the arcs a pulsing "broadcasting" effect:

```css
@keyframes beamPulse1 {
  0%, 100% { opacity: 0.9; transform: translateX(0); }
  50%      { opacity: 1;   transform: translateX(2px); }
}
@keyframes beamPulse2 {
  0%, 100% { opacity: 0.55; transform: translateX(0); }
  50%      { opacity: 0.75; transform: translateX(3px); }
}

.beam-arc-1 { animation: beamPulse1 2s ease-in-out infinite; }
.beam-arc-2 { animation: beamPulse2 2s ease-in-out 0.25s infinite; }
```

- Inner arc is most opaque/least movement; outer arc is more transparent/more movement
- Stagger delays: 0s, 0.25s
- Duration: 2s per cycle

### Android (Compose)
The Android app implements equivalent animations in Jetpack Compose using `rememberInfiniteTransition()` with `animateFloat` for arc alpha pulsing. See `ClipRelayScreen.kt:LogoIcon()`.

---

## Typography (Brand / Marketing)

| Role    | Family             | Weight | Notes                          |
|---------|--------------------|--------|--------------------------------|
| Display | Instrument Serif   | 400    | Headlines, logo lockup text    |
| Body    | DM Sans            | 300/500/700 | UI text, descriptions     |

Google Fonts import:
```
https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,500;0,9..40,700;1,9..40,300&family=Instrument+Serif:ital@0;1&display=swap
```

---

## Color Selection Rationale

**Why Neon Aqua over Neon Green or Ice Cyan?**

- **Neon Green (#39FF14)**: Maximum visibility but strong battery/power app association (AccuBattery, Greenify, etc.). At small icon sizes users pattern-match on color before reading the silhouette.
- **Neon Aqua (#00FFD5)**: Distinctive in Android share menus (dominated by blues and grays), no wrong-category associations, naturally conveys data transfer / connectivity.
- **Ice Cyan (#00E5FF)**: Clean and modern but too close to the blues that dominate Android share sheets (Messages, Drive, Chrome, Duo) — would blend in rather than stand out.

---

## Legacy

### Beam Refined (pre-Simplified)
The previous iteration used **three concentric arcs** (radii 20, 32, 44) and included **four text lines** on the clipboard board. The text lines became sub-pixel mush at small sizes and the third arc added visual noise without improving recognition. The light variant used a washed-out teal board that lacked brand energy.

### Beam Simplified (current)
Reduces to **two arcs** (radii 24, 36), removes text lines, narrows/centers the clamp, uses an **aqua-filled board** for the light variant, and collapses the palette from ~20 colors to 5 brand tokens + UI theme colors.

### Original (pre-Beam)
The original logo concept used **two overlapping clipboards** with sync arrows, representing Mac-to-Android relay. This was replaced by the single-clipboard + beam-arcs design which is simpler and reads better at small sizes. The old SVGs are preserved in git history.
