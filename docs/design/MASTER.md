# TokenEater -> Design System MASTER

> Source unique de vérité pour le design de la **window app** (scope B).
> Ne concerne PAS le menu bar, le popover, ni le widget (qui conservent leur identité actuelle).

## Thèses fondatrices

### Visual Thesis
Dashboard à la **CleanMyMac X** : sidebar ultra-simplifiée (3 modules -> Stats / History / Settings), layout **tile-based** où chaque tile a son gradient d'ambiance propre (subtil, jamais criard), **glass surfaces** translucides sur backdrop légèrement gradienté, typo **Inter Display** pour hiérarchie + Inter pour UI + mono pour la data chiffrée. Palette neutre bleutée avec accents color-coded par section. Les thèmes utilisateur (default/neon/pastel/monochrome) continuent de colorer **uniquement les gauges/data points**, pas le chrome. **Circular visualizations** pour les key metrics. Rayons doux 10-16px, shadows profondes mais douces.

### Interaction Thesis
Motion language **Arc-like** : transitions de section via slide + fade fluides (`spring(response: 0.5, damping: 0.8)` -> sensation "liquide"), hover sur cards avec **lift progressif** (shadow qui se creuse + 2px translate Y + glow subtil sur borders), cross-fade entre contenus de tile, **gradient shifts** au survol, **cursor-aware spotlight** léger sur les cards (halo qui suit la souris). Timing range 250-500ms selon le geste. Respect `reduceMotion`. **Interdits :** bounce agressif, stagger voyant, parallax scroll.

## Règle de cohabitation avec les thèmes utilisateur

| Layer | Géré par | Change selon le thème ? |
|---|---|---|
| Chrome (sidebar, cards, panels, typo, spacing) | **MASTER.md** | Non -> constant quel que soit le thème |
| Data points (gauges, pacing dots, metric values) | `ThemeColors` (existant) | Oui -> default / neon / pastel / monochrome / custom |
| Accents d'ambiance par module (Stats / History / Settings) | **MASTER.md** | Non -> fixe par module |

Concrètement : un utilisateur en thème Neon voit sa gauge en vert néon sur un **chrome dark glass fixe**. On ne repeint pas le chrome.

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
// Glass surface = bgElevated + blur material + border subtil
static let glassFill      = Color.white.opacity(0.03)  // overlay sur bgElevated
static let glassBorder    = Color.white.opacity(0.06)  // border par défaut
static let glassBorderHi  = Color.white.opacity(0.12)  // border hover/focus
static let glassBorderLo  = Color.white.opacity(0.03)  // border inactif
```

### Text (exact site values)

```swift
static let textPrimary    = Color(hex: "#F5F5F7")  // titles, critical values
static let textSecondary  = Color(hex: "#A1A1AA")  // body, descriptions
static let textTertiary   = Color(hex: "#63636E")  // labels, meta, hints
static let textDisabled   = Color(hex: "#63636E").opacity(0.4)
```

### Accents d'ambiance par module

Chaque module (Stats / History / Settings) a une teinte d'accent qui colore son gradient de tile + son état actif dans la sidebar. Les 3 couleurs sont natives au site `tokeneater.athevon.dev` -> zéro couleur inventée. **Jamais criard**, opacity max 0.15 en fill.

```swift
// Stats -> brand green (data, confiance)
static let accentStats    = Color(hex: "#32CE6A")

// History -> info blue (temporel, récit)
static let accentHistory  = Color(hex: "#60A5FA")

// Settings -> warm orange (config, contrôle)
static let accentSettings = Color(hex: "#FFB347")
```

### Brand primary (variantes vert)

Pour les primary buttons et call-to-actions partageant l'identité du site.

```swift
static let brandPrimary = Color(hex: "#32CE6A")  // default
static let brandPressed = Color(hex: "#28A554")  // pressed / active
static let brandLight   = Color(hex: "#5EDDA0")  // light state / success halo
```

### Semantic (états système)

Pour notifications, banners, erreurs. Alignés sur la palette du site.

```swift
static let semanticSuccess = Color(hex: "#32CE6A")  // same as brand primary
static let semanticWarning = Color(hex: "#FFB347")  // same as accent settings
static let semanticError   = Color(hex: "#F87171")
static let semanticInfo    = Color(hex: "#60A5FA")  // same as accent history
```

---

## 2. Typography

### Stack

- **Inter Display** -> titres, hero values, section headers (fallback system semibold)
- **Inter** -> UI, body, labels (fallback system regular)
- **SF Mono** -> data chiffrée, tokens, percentages (fallback monospaced system)

### Scale

| Role | Font | Size | Weight | Line-height | Usage |
|---|---|---|---|---|---|
| `display` | Inter Display | 34 | .bold | 1.1 | Hero metric (ex: "87%") |
| `title1` | Inter Display | 22 | .semibold | 1.2 | Section titles (Stats, History, Settings) |
| `title2` | Inter Display | 17 | .semibold | 1.25 | Card titles |
| `body` | Inter | 13 | .regular | 1.5 | Body text, descriptions |
| `label` | Inter | 11 | .medium | 1.4 | Form labels, captions |
| `micro` | Inter | 10 | .medium | 1.3 | Uppercase tracked labels (letter-spacing: 0.08em) |
| `metricLarge` | SF Mono | 28 | .semibold | 1 | Key metrics (circular viz) |
| `metricInline` | SF Mono | 13 | .regular | 1 | Data inline (table cells) |

### Rules

- Line-length max **72 caractères** pour le body.
- Uppercase tracked uniquement pour les micro-labels (ex: "SESSION - 5H WINDOW"), jamais pour du body.
- Numerals tabulaires (`.monospacedDigit()`) obligatoires sur toute valeur qui change en live.

---

## 3. Spacing

Base **4pt**, scale multiplicative.

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

**Règle :** une card n'utilise qu'**un seul niveau** de padding interne (`.md` = 16 par défaut). Les sous-groupes respirent avec `.xs` / `.sm`.

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

**Règle :** plus la surface est grande, plus le rayon est grand. Jamais de rayon < 8 (casse le feeling "soft").

---

## 5. Shadows (glass-compatible)

Shadows sur fond dark + glass doivent être **profondes mais douces**. Pas de shadow dure noire visible -> alpha faible, blur large.

```swift
enum Shadow {
    // Level 0 -> flat (default)
    static let flat = (radius: 0.0, y: 0.0, alpha: 0.0)

    // Level 1 -> subtle (cards au repos)
    static let subtle = (radius: 12.0, y: 4.0, alpha: 0.12)

    // Level 2 -> lift (hover)
    static let lift   = (radius: 24.0, y: 8.0, alpha: 0.20)

    // Level 3 -> elevated (modals, dropdowns)
    static let elev   = (radius: 48.0, y: 16.0, alpha: 0.32)
}

// Glow Arc-like (border qui s'éclaire au hover)
enum Glow {
    static let subtle  = (radius: 16.0, alpha: 0.25)  // hover
    static let strong  = (radius: 24.0, alpha: 0.40)  // focus / active
}
```

Usage SwiftUI :
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
    // Easing standard SwiftUI
    static let easeOut     = Animation.easeOut(duration: Duration.base)
    static let easeIn      = Animation.easeIn(duration: Duration.base)
    static let easeInOut   = Animation.easeInOut(duration: Duration.base)

    // Springs "liquides" à la Arc
    static let springSnap   = Animation.spring(response: 0.30, dampingFraction: 0.90)  // hover / press
    static let springLiquid = Animation.spring(response: 0.50, dampingFraction: 0.80)  // section change
    static let springSoft   = Animation.spring(response: 0.70, dampingFraction: 0.85)  // modal entry

    // Shimmer sur metrics live (pulse 2s, subtle)
    static let shimmerPulse = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}
```

### Règles d'application

- **Hover card** -> `springSnap`, translate Y -2pt + shadow .subtle -> .lift + glow .subtle
- **Press card** -> `springSnap`, scale 0.98
- **Section change** (Stats -> History) -> `springLiquid`, opacity + translate X 8pt
- **Modal in** -> `springSoft`, opacity + scale 0.96 -> 1.0
- **Numeric value change** -> `easeOut`, cross-fade 180ms + numerals tabulaires
- **Accessibility** -> `@Environment(\.accessibilityReduceMotion)` -> toutes les anims tombent à 0s, remplacées par simple `.animation(nil)`.

**Forbidden :**
- `response > 1.0` ou `damping < 0.7` (trop bounce)
- Stagger sur > 5 éléments (voyant)
- Parallax scroll (interdit, incompatible avec AppKit scroll naturel)
- Animation sur `.frame(width:, height:)` (perf) -> utiliser `.scaleEffect` + `.offset` + `.opacity`.

---

## 7. Base components

### 7.1 Button

3 variants seulement. Pas plus.

| Variant | Background | Text | Border | Usage |
|---|---|---|---|---|
| `primary` | `accentStats` (module-aware) | `textPrimary` | none | Action principale |
| `secondary` | `glassFill` | `textPrimary` | `glassBorder` | Actions secondaires |
| `ghost` | transparent | `textSecondary` | none | Tertiaires, inline |

States : default / hover (background +4% alpha) / pressed (scale 0.97) / disabled (alpha 0.4).

Radius : `Radius.input` (8pt). Padding : `.md` horizontal (16), `.xs` vertical (8) -> hauteur 32pt min.

### 7.2 Card (glass tile)

```
┌──────────────────────────────────────┐
│  [icon]  Title                       │  <- title2, padding .md
│                                      │
│  Content                             │  <- body, padding .md
│                                      │
└──────────────────────────────────────┘
  background: bgElevated + glassFill (material .ultraThinMaterial)
  border: glassBorder (1pt stroke inner)
  radius: Radius.card (14pt)
  shadow: Shadow.subtle at rest, Shadow.lift + Glow.subtle on hover
```

**Cursor-aware spotlight (Arc-like)** : overlay radial gradient qui suit `.onContinuousHover`, opacity 0.08 max, blend mode plus-lighter.

### 7.3 Sidebar row

3 états : default / hover / active.

- **Default** : icon + label, `textTertiary`, transparent
- **Hover** : `textSecondary`, `glassFill`, `springSnap`
- **Active** : `textPrimary`, gradient d'ambiance du module en fond (opacity 0.12), bordure gauche 2pt de l'accent module

Hauteur fixe 44pt. Padding horizontal 12pt. Icon 16pt + gap 8pt + label.

### 7.4 Input

Radius 8pt, background `bgElevated`, border `glassBorder`.
Focus : border `glassBorderHi` + glow `Glow.subtle` en accent module. Animation `springSnap`.

### 7.5 Badge

Pill, `Radius.pill`. Padding horizontal 8pt, hauteur 20pt.
Variants : status (semantic colors) / count (`glassFill`).

### 7.6 Circular metric (Stats hero)

- SF Mono semibold 28, centré
- Anneau extérieur : gradient de l'accent module + thème utilisateur pour le fill
- Animation entrée : `springLiquid`, fill 0 -> target en 600ms
- Glow subtil au hover

---

## 8. Pre-delivery checklist (TokenEater-specific)

Avant de merger un changement UI :

### Visual
- [ ] Toutes les couleurs viennent de `MASTER` tokens ou `ThemeColors` (thèmes utilisateurs sur data points uniquement)
- [ ] Aucune magic color hex dans les views
- [ ] Pas d'emoji comme icône -> SF Symbols uniquement
- [ ] Cards utilisent `Shadow.subtle` au repos, jamais flat
- [ ] Glass material : `.ultraThinMaterial` sur fond `bgElevated`
- [ ] Light mode -> non supporté v5.0 (TokenEater reste dark-only, cohérent avec l'identité menu-bar)

### Interaction
- [ ] Chaque élément cliquable a un hover state (+ `springSnap`)
- [ ] Aucune animation > 500ms
- [ ] `reduceMotion` respecté partout
- [ ] Transitions de section en `springLiquid`
- [ ] Pas de `.bounce` agressif ni stagger sur > 5 items

### Typography
- [ ] Valeurs numériques live -> `.monospacedDigit()` obligatoire
- [ ] Titres -> Inter Display, body -> Inter, data -> SF Mono
- [ ] Micro-labels uppercase tracked uniquement, jamais sur body

### Performance
- [ ] Pas d'animation sur `.frame(width:height:)` -> `.scaleEffect` + `.offset`
- [ ] Glass surfaces limitées à 3 niveaux max (perf SwiftUI material)
- [ ] Pas de `LinearGradient` animé sur > 2 views simultanées

---

## 9. Hors-scope (NE PAS TOUCHER)

- Menu bar renderer (`MenuBarRenderer.swift`) -> rendu NSAttributedString, indépendant
- Popover layouts (Classic / Focus / Compact) -> identité propre, cohérente avec l'écosystème menu bar
- Widget views (`TokenEaterWidget/`) -> contraint par WidgetKit + sandbox
- `ThemeColors` struct et les 4 presets -> continuent de colorer les gauges / data points

Si l'un de ces éléments doit évoluer, c'est un **autre chantier** qui mérite sa propre itération de design excellence.
