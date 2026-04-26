# TokenEater -> Design System MASTER

> Single source of truth for the **window app** design (scope B).
> Does NOT cover the menu bar, the popover, or the widget (those keep their existing identity).

## Founding theses

### Visual Thesis
Dashboard inspired by **CleanMyMac X**: ultra-simplified sidebar (3 modules -> Stats / History / Settings), **tile-based** layout where each tile carries its own ambient gradient (subtle, never loud), translucent **glass surfaces** over a lightly gradiented backdrop, **Inter Display** for hierarchy + Inter for UI + monospaced for numeric data. Neutral blue-tinted palette with module-coded accents. User themes (default / neon / pastel / monochrome) keep colouring **only the gauges / data points**, never the chrome. **Circular visualizations** for the key metrics. Soft 10-16pt radii, deep but soft shadows.

### Interaction Thesis
**Arc-like** motion language: section transitions via fluid slide + fade (`spring(response: 0.5, damping: 0.8)` -> "liquid" feel), card hovers with **progressive lift** (deeper shadow + 2pt translate Y + subtle glow on borders), cross-fade between tile contents, **gradient shifts** on hover, light **cursor-aware spotlight** on cards (a halo that follows the mouse). Timing range 250-500ms depending on the gesture. Respects `reduceMotion`. **Forbidden:** aggressive bounce, loud stagger, parallax scroll.

## Coexistence rule with user themes

| Layer | Owned by | Changes with the theme? |
|---|---|---|
| Chrome (sidebar, cards, panels, typography, spacing) | **MASTER.md** | No -> constant regardless of theme |
| Data points (gauges, pacing dots, metric values) | `ThemeColors` (existing) | Yes -> default / neon / pastel / monochrome / custom |
| Per-module ambient accents (Stats / History / Settings) | **MASTER.md** | No -> fixed per module |

Concretely: a user on the Neon theme sees their gauge in neon green over a **fixed dark glass chrome**. We don't repaint the chrome.

---

## 1. Color palette (Chrome)

### Backgrounds (aligned on tokeneater.athevon.dev)

```swift
// Window
static let bgBase       = Color(hex: "#050505")  // near-black
static let bgElevated   = Color(hex: "#0F0F11")  // card/surface base
static let bgOverlay    = Color(hex: "#1A1A1E")  // dropdowns / modals
static let bgHover      = Color(hex: "#1F1F23")  // row hover
static let bgActive     = Color(hex: "#242428")  // row active / pressed

// Ambient gradient (subtle backdrop behind cards)
static let gradientTopLeft     = Color(hex: "#0F0F11")
static let gradientBottomRight = Color(hex: "#050505")
```

### Surfaces (glass)

```swift
// Glass surface = bgElevated + blur material + subtle border
static let glassFill      = Color.white.opacity(0.03)  // overlay on bgElevated
static let glassBorder    = Color.white.opacity(0.06)  // default border
static let glassBorderHi  = Color.white.opacity(0.12)  // hover / focus border
static let glassBorderLo  = Color.white.opacity(0.03)  // inactive border
```

### Text (exact site values)

```swift
static let textPrimary    = Color(hex: "#F5F5F7")  // titles, critical values
static let textSecondary  = Color(hex: "#A1A1AA")  // body, descriptions
static let textTertiary   = Color(hex: "#63636E")  // labels, meta, hints
static let textDisabled   = Color(hex: "#63636E").opacity(0.4)
```

### Per-module ambient accents

Each module (Stats / History / Settings) has an accent hue that tints its tile gradient + its active state in the sidebar. The 3 colours are native to `tokeneater.athevon.dev` -> zero invented colour. **Never loud**, max fill opacity 0.15.

```swift
// Stats -> brand green (data, confidence)
static let accentStats    = Color(hex: "#32CE6A")

// History -> info blue (time, narrative)
static let accentHistory  = Color(hex: "#60A5FA")

// Settings -> warm orange (config, control)
static let accentSettings = Color(hex: "#FFB347")
```

### Brand primary (green variants)

For primary buttons and call-to-actions sharing the site's identity.

```swift
static let brandPrimary = Color(hex: "#32CE6A")  // default
static let brandPressed = Color(hex: "#28A554")  // pressed / active
static let brandLight   = Color(hex: "#5EDDA0")  // light state / success halo
```

### Semantic (system states)

For notifications, banners, errors. Aligned on the site palette.

```swift
static let semanticSuccess = Color(hex: "#32CE6A")  // same as brand primary
static let semanticWarning = Color(hex: "#FFB347")  // same as accent settings
static let semanticError   = Color(hex: "#F87171")
static let semanticInfo    = Color(hex: "#60A5FA")  // same as accent history
```

---

## 2. Typography

### Stack

- **Inter Display** -> titles, hero values, section headers (fallback system semibold)
- **Inter** -> UI, body, labels (fallback system regular)
- **SF Mono** -> numeric data, tokens, percentages (fallback monospaced system)

### Scale

| Role | Font | Size | Weight | Line-height | Usage |
|---|---|---|---|---|---|
| `display` | Inter Display | 34 | .bold | 1.1 | Hero metric (e.g. "87%") |
| `title1` | Inter Display | 22 | .semibold | 1.2 | Section titles (Stats, History, Settings) |
| `title2` | Inter Display | 17 | .semibold | 1.25 | Card titles |
| `body` | Inter | 13 | .regular | 1.5 | Body text, descriptions |
| `label` | Inter | 11 | .medium | 1.4 | Form labels, captions |
| `micro` | Inter | 10 | .medium | 1.3 | Uppercase tracked labels (letter-spacing: 0.08em) |
| `metricLarge` | SF Mono | 28 | .semibold | 1 | Key metrics (circular viz) |
| `metricInline` | SF Mono | 13 | .regular | 1 | Inline data (table cells) |

### Rules

- Body line length capped at **72 characters**.
- Uppercase tracked is for micro-labels only (e.g. "SESSION - 5H WINDOW"), never for body.
- Tabular numerals (`.monospacedDigit()`) are mandatory on every value that updates live.

---

## 3. Spacing

Base **4pt**, multiplicative scale.

```swift
enum Spacing {
    static let xxs: CGFloat = 4    // micro gaps (icon + text)
    static let xs:  CGFloat = 8    // tight groups
    static let sm:  CGFloat = 12   // default element gap
    static let md:  CGFloat = 16   // card internal padding
    static let lg:  CGFloat = 24   // section gap
    static let xl:  CGFloat = 32   // module gap, header separation
    static let xxl: CGFloat = 48   // hero padding, big vertical breaks
    static let xxxl: CGFloat = 64  // large page sections
}
```

**Rule:** a card uses **a single level** of internal padding (`.md` = 16 by default). Sub-groups breathe with `.xs` / `.sm`.

---

## 4. Radii

```swift
enum Radius {
    static let input:  CGFloat = 8    // text fields, buttons
    static let pill:   CGFloat = 100  // tags, badges
    static let small:  CGFloat = 10   // small cards, badges
    static let card:   CGFloat = 14   // standard tile
    static let cardLg: CGFloat = 20   // hero cards
    static let modal:  CGFloat = 24   // modals, large panels
}
```

**Rule:** the larger the surface, the larger the radius. Never below 8 (breaks the "soft" feel).

---

## 5. Shadows (glass-compatible)

Shadows on dark + glass must be **deep but soft**. No hard visible black shadow -> low alpha, wide blur.

```swift
enum Shadow {
    // Level 0 -> flat (default)
    static let flat = (radius: 0.0, y: 0.0, alpha: 0.0)

    // Level 1 -> subtle (cards at rest)
    static let subtle = (radius: 12.0, y: 4.0, alpha: 0.12)

    // Level 2 -> lift (hover)
    static let lift   = (radius: 24.0, y: 8.0, alpha: 0.20)

    // Level 3 -> elevated (modals, dropdowns)
    static let elev   = (radius: 48.0, y: 16.0, alpha: 0.32)
}

// Arc-like glow (border that lights up on hover)
enum Glow {
    static let subtle  = (radius: 16.0, alpha: 0.25)  // hover
    static let strong  = (radius: 24.0, alpha: 0.40)  // focus / active
}
```

SwiftUI usage:
```swift
.shadow(color: Color.black.opacity(Shadow.subtle.alpha),
        radius: Shadow.subtle.radius, y: Shadow.subtle.y)
```

---

## 6. Motion tokens

### Durations

```swift
enum Duration {
    static let fast:   Double = 0.18   // micro hover, cursor changes
    static let base:   Double = 0.24   // default transitions
    static let slow:   Double = 0.40   // section changes, slide-ins
    static let xslow:  Double = 0.60   // rare, hero entrances
}
```

### Easings & springs

```swift
enum Motion {
    // Standard SwiftUI easings
    static let easeOut     = Animation.easeOut(duration: Duration.base)
    static let easeIn      = Animation.easeIn(duration: Duration.base)
    static let easeInOut   = Animation.easeInOut(duration: Duration.base)

    // Arc-style "liquid" springs
    static let springSnap   = Animation.spring(response: 0.30, dampingFraction: 0.90)  // hover / press
    static let springLiquid = Animation.spring(response: 0.50, dampingFraction: 0.80)  // section change
    static let springSoft   = Animation.spring(response: 0.70, dampingFraction: 0.85)  // modal entry

    // Shimmer on live metrics (subtle 2s pulse)
    static let shimmerPulse = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}
```

### Application rules

- **Card hover** -> `springSnap`, translate Y -2pt + shadow .subtle -> .lift + glow .subtle
- **Card press** -> `springSnap`, scale 0.98
- **Section change** (Stats -> History) -> `springLiquid`, opacity + translate X 8pt
- **Modal in** -> `springSoft`, opacity + scale 0.96 -> 1.0
- **Numeric value change** -> `easeOut`, 180ms cross-fade + tabular numerals
- **Accessibility** -> `@Environment(\.accessibilityReduceMotion)` -> all animations drop to 0s, replaced by a plain `.animation(nil)`.

**Forbidden:**
- `response > 1.0` or `damping < 0.7` (too bouncy)
- Stagger on > 5 elements (loud)
- Parallax scroll (forbidden, incompatible with native AppKit scroll)
- Animating `.frame(width:, height:)` (perf) -> use `.scaleEffect` + `.offset` + `.opacity`.

---

## 7. Base components

### 7.1 Button

3 variants, no more.

| Variant | Background | Text | Border | Usage |
|---|---|---|---|---|
| `primary` | `accentStats` (module-aware) | `textPrimary` | none | Main action |
| `secondary` | `glassFill` | `textPrimary` | `glassBorder` | Secondary actions |
| `ghost` | transparent | `textSecondary` | none | Tertiary, inline |

States: default / hover (background +4% alpha) / pressed (scale 0.97) / disabled (alpha 0.4).

Radius: `Radius.input` (8pt). Padding: `.md` horizontal (16), `.xs` vertical (8) -> 32pt min height.

### 7.2 Card (glass tile)

```
┌──────────────────────────────────────┐
│  [icon]  Title                       │  <- title2, padding .md
│                                      │
│  Content                             │  <- body, padding .md
│                                      │
└──────────────────────────────────────┘
  background: bgElevated + glassFill (material .ultraThinMaterial)
  border: glassBorder (1pt inner stroke)
  radius: Radius.card (14pt)
  shadow: Shadow.subtle at rest, Shadow.lift + Glow.subtle on hover
```

**Cursor-aware spotlight (Arc-like):** a radial gradient overlay following `.onContinuousHover`, max opacity 0.08, blend mode plus-lighter.

### 7.3 Sidebar row

3 states: default / hover / active.

- **Default:** icon + label, `textTertiary`, transparent
- **Hover:** `textSecondary`, `glassFill`, `springSnap`
- **Active:** `textPrimary`, the module's ambient gradient as background (opacity 0.12), 2pt left border in the module accent

Fixed height 44pt. Horizontal padding 12pt. Icon 16pt + 8pt gap + label.

### 7.4 Input

Radius 8pt, background `bgElevated`, border `glassBorder`.
Focus: border `glassBorderHi` + `Glow.subtle` glow in the module accent. Animation `springSnap`.

### 7.5 Badge

Pill, `Radius.pill`. Horizontal padding 8pt, height 20pt.
Variants: status (semantic colors) / count (`glassFill`).

### 7.6 Circular metric (Stats hero)

- SF Mono semibold 28, centered
- Outer ring: gradient of the module accent + the user theme for the fill
- Entry animation: `springLiquid`, fill 0 -> target over 600ms
- Subtle hover glow

---

## 8. Pre-delivery checklist (TokenEater-specific)

Before merging a UI change:

### Visual
- [ ] Every colour comes from `MASTER` tokens or `ThemeColors` (user themes only on data points)
- [ ] No magic hex colour in views
- [ ] No emoji as an icon -> SF Symbols only
- [ ] Cards use `Shadow.subtle` at rest, never flat
- [ ] Glass material: `.ultraThinMaterial` over `bgElevated`
- [ ] Light mode -> not supported in v5.0 (TokenEater stays dark-only, consistent with the menu-bar identity)

### Interaction
- [ ] Every clickable element has a hover state (+ `springSnap`)
- [ ] No animation > 500ms
- [ ] `reduceMotion` respected everywhere
- [ ] Section transitions use `springLiquid`
- [ ] No aggressive `.bounce` and no stagger on > 5 items

### Typography
- [ ] Live numeric values -> `.monospacedDigit()` mandatory
- [ ] Titles -> Inter Display, body -> Inter, data -> SF Mono
- [ ] Uppercase tracked is for micro-labels only, never on body

### Performance
- [ ] No animation on `.frame(width:height:)` -> `.scaleEffect` + `.offset`
- [ ] Glass surfaces capped at 3 levels max (SwiftUI material perf)
- [ ] No animated `LinearGradient` on > 2 views simultaneously

---

## 9. Out of scope (DO NOT TOUCH)

- Menu bar renderer (`MenuBarRenderer.swift`) -> NSAttributedString rendering, independent
- Popover layouts (Classic / Focus / Compact) -> their own identity, consistent with the menu-bar ecosystem
- Widget views (`TokenEaterWidget/`) -> constrained by WidgetKit + sandbox
- `ThemeColors` struct and the 4 presets -> keep colouring the gauges / data points

If any of these needs to evolve, that's a **separate effort** deserving its own design-excellence iteration.
