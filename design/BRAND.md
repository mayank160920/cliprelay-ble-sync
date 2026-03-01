# ClipRelay Brand & Design Language

## Color Palette

### Primary: Neon Aqua
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `aqua-neon`       | `#00FFD5` | Primary brand color, icon backgrounds    |
| `aqua-gradient`   | `#00DDC0` | Gradient endpoint, secondary accent      |

### Dark Tints (for on-dark surfaces)
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `board-dark`      | `#0A3A34` | Clipboard board fill (dark theme)        |
| `board-darker`    | `#082A26` | Clipboard body fill (dark theme)         |

### Teal Accents (Android UI)
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `teal-dark`       | `#00796B` | Dark teal accent                         |
| `teal-title`      | `#00695C` | Title text on light backgrounds          |
| `teal-text`       | `#00897B` | Body text on light backgrounds           |
| `teal-icon`       | `#009688` | Icon tint on light backgrounds           |

### Light Backgrounds (Android UI)
| Token             | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| `bg-unpaired`     | `#E8F5F3` | Top section, unpaired state              |
| `bg-connected`    | `#D6F5EF` | Top section, connected state             |

### Dark UI Surfaces (used in logo-concepts.html)
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
| Glow              | `feGaussianBlur stdDeviation="4"` + merge       | Beam arc glow effect     |
| Title Gradient    | `linear-gradient(135deg, #fff 30%, #00FFD5)`    | Display heading text     |

---

## Logo: "Beam Refined" Concept

The logo is a **clipboard board with clamp** (representing clipboard/paste) combined with **three concentric signal arcs** emanating to the right (representing wireless BLE data transfer).

### Anatomy
```
  ┌──────┐         Clamp (top, centered on board)
  │ ╶──╴ │         Clamp screw / rivet
┌─┴──────┴─┐
│ ═══════  │  )))   Board with text lines + 3 beam arcs
│ ═════    │  ))
│ ══════   │  )
│ ════     │
└──────────┘
```

### SVG Variants (in this directory)

| File                     | Size     | Description                                   |
|--------------------------|----------|-----------------------------------------------|
| `logo-full-dark.svg`     | 120x120  | Full logo for dark backgrounds, aqua glow     |
| `logo-full-light.svg`    | 120x120  | Full logo for light backgrounds, teal + shadow |
| `logo-android-icon.svg`  | 120x120  | Circular aqua-gradient bg, black arcs         |
| `logo-menubar.svg`       | 120x120  | Stroke-only, for macOS menu bar (monochrome)  |
| `logo-share-icon.svg`    | 120x120  | Circular aqua bg, compact for share sheets    |

### Design Rules
- **On dark backgrounds**: Use aqua-colored strokes/fills with glow filter
- **On colored (aqua) backgrounds**: Use black arcs, white text-line fills
- **Menu bar / monochrome**: Stroke-only in `#00FFD5` (or template-mode white)
- Beam arcs always face **right** (signal radiating outward)
- Three arcs at increasing radii (20, 32, 44 in the 120-unit viewBox)
- Arcs are semicircular (`A` commands spanning ~100 degrees)
- Stroke-linecap is always `round`

---

## Animation

### Beam Pulse (CSS)
Three staggered keyframe animations give the arcs a pulsing "broadcasting" effect:

```css
@keyframes beamPulse1 {
  0%, 100% { opacity: 0.9; transform: translateX(0); }
  50%      { opacity: 1;   transform: translateX(2px); }
}
@keyframes beamPulse2 {
  0%, 100% { opacity: 0.55; transform: translateX(0); }
  50%      { opacity: 0.75; transform: translateX(3px); }
}
@keyframes beamPulse3 {
  0%, 100% { opacity: 0.3; transform: translateX(0); }
  50%      { opacity: 0.5; transform: translateX(4px); }
}

.beam-arc-1 { animation: beamPulse1 2s ease-in-out infinite; }
.beam-arc-2 { animation: beamPulse2 2s ease-in-out 0.25s infinite; }
.beam-arc-3 { animation: beamPulse3 2s ease-in-out 0.5s infinite; }
```

- Inner arc is most opaque/least movement; outer arc is most transparent/most movement
- Stagger delays: 0s, 0.25s, 0.5s
- Duration: 2s per cycle

### Text Shimmer (CSS)
Clipboard text lines pulse subtly:

```css
@keyframes beamTextShimmer {
  0%, 100% { opacity: 0.4; }
  40%      { opacity: 0.6; }
}
.beam-text-line { animation: beamTextShimmer 3s ease-in-out infinite; }
/* Stagger each line by 0.4s */
```

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

The original logo concept (pre-Beam Refined) used **two overlapping clipboards** with sync arrows, representing Mac-to-Android relay. This was replaced by the current single-clipboard + beam-arcs design which is simpler and reads better at small sizes. The old SVGs are preserved in git history if needed (`git show HEAD~2:logo.svg` etc.).
