# TokenEater Coloring System

Reference doc for how colors are computed across the app. Three independent systems coexist, each answering a different question.

## Overview

| System | Question it answers | Where it applies |
|---|---|---|
| **Threshold gauge** | "How full is this bucket right now?" | Fallback when smart is OFF, or when no `resetDate` is available |
| **Smart gauge v2** | "What's my real risk of overshooting before the next reset?" | Default ON. Drives the gauge / percentage colors when `Smart Color` is enabled in Themes |
| **Pacing zone** | "Am I keeping up with the ideal pace?" | Pacing badges, dots, pacing track bars, sub-rows |

Threshold and smart are alternatives (one or the other for a given gauge). Pacing is always its own thing, independent and complementary.

## 1. Threshold gauge (static)

Maps the raw utilization percentage to one of 3 colors using two user-configurable thresholds (`warningPercent`, `criticalPercent`).

```
util >= criticalPercent (default 85)  -> critical (red)
util >= warningPercent  (default 60)  -> warning  (orange)
else                                   -> normal   (green)
```

Default thresholds : `60` warning / `85` critical. Configurable in Settings -> Themes -> Thresholds.

**Used when** : `smartColorEnabled = false`, or `resetDate` is missing.

## 2. Smart gauge v2 (continuous risk model)

The default since v5.0. Replaces the v1 threshold+pacing/`max` combinator + reset-imminent override that produced cliffs and false negatives (e.g. 98% used / 30 min remaining stayed green because the override fired late). v2 is fully continuous across `[0, 1]` with no discrete decision points.

### Architecture

```text
projectionHealth = smoothstep(0.7, 1.0, u / e)
risk = max(absoluteRisk × projectionHealth,
           projectionRisk × confidence,
           pacingRisk × confidence)
```

Three independent components, each producing a `[0, 1]` score, combined via `max` so the worst signal always wins. The two time-derived components are weighted by a confidence factor that grows from 0 at window start to ~1 at window end, so a 5% used / 1% elapsed burst doesn't trigger a panic alarm.

The absolute component is dampened by `projectionHealth`: when the current rate projects a comfortable finish under the limit (`u/e ≤ 0.7`), the multiplier drops to 0 and the "you've burnt a lot" signal is suppressed. At `u/e ≥ 1.0` (you'll hit or overshoot), the multiplier saturates to 1 and absolute fires at full strength. This keeps the 98% / 30min hard flag intact while quieting the false alarm at e.g. 72% with calm pacing where `u/e ≈ 0.86` and the user is on track to finish ~86% — no real risk.

The continuous score then drives the gauge color via linear RGBA interpolation across 4 anchor stops (chill / chill / warning / critical at 0.0 / 0.30 / 0.55 / 0.85), so the user sees a smooth color ramp rather than discrete bands.

### The three risk components

#### A. Absolute risk -> "How close to the limit ?"

```text
absoluteRisk = smoothstep(absoluteLower, absoluteUpper, u)
  u             = utilization (0..1)
  absoluteLower = profile-defined bound (Balanced: 0.50)
  absoluteUpper = profile-defined bound (Balanced: 1.00)
```

The bounds are owned by the chosen profile, **not** by the user's threshold sliders (which only drive threshold-mode coloring now). Below `absoluteLower` returns 0; above `absoluteUpper` returns 1; smoothly ramped (Hermite C¹ continuous) in between - no cliff. Independent of pacing.

This is what makes 98% used always feel red, regardless of how much time is left.

#### B. Projection risk -> "Will I overshoot at this rate ?"

```text
projected     = u / e                       // where would I land if I kept this rate ?
                                            // e = elapsed fraction (0..1)
projectionRaw = smoothstep(1.0, projUpper, projected)
projectionRisk = projectionRaw × confidence(e, k)
```

`projected` is the linear extrapolation of current usage to the end of the window. If `u/e <= 1`, you'll finish under the limit -> 0. As `projected` grows past 1, the risk ramps up; saturates at the profile-dependent `projUpper` (e.g. 1.4 means "you'll hit 140% of the limit" reads as full risk).

`confidence(e, k) = 1 - exp(-k × e)` damps early-window noise. At `e = 0.01` (1% elapsed), even a wild `u/e = 5` ratio is multiplied by `confidence ≈ 0.05` (with default `k = 5`), so the projection risk stays near 0. By `e = 0.50` confidence is ~0.92, by `e = 1.0` it's ~0.99.

#### C. Pacing risk -> "Am I burning faster than the linear pace, beyond my margin ?"

```text
delta       = u - e
pacingRaw   = smoothstep(m, m + 0.15, delta)
pacingRisk  = pacingRaw × confidence(e, k)
  m = pacingMargin / 100   (default 0.10)
```

Same shape as projection but anchored on the absolute delta from the linear pace rather than the projected overflow. Inside the user-configured margin -> 0. Past the margin, ramps to 1 over a 15-percentage-point band. Same confidence damping as projection.

### Color interpolation

The continuous risk maps to a color via linear RGBA interpolation across 4 anchor stops :

```text
r ≤ 0.30   -> normal (chill)
0.30..0.55 -> normal -> warning (smooth interpolation)
0.55..0.85 -> warning -> critical (smooth interpolation)
r ≥ 0.85   -> critical
```

No discrete bands - the gauge ramps smoothly through the spectrum.

### Profiles (user-facing temperaments)

Three presets ship in Settings -> Themes -> Smart Color -> Sensitivity. Each tunes the algorithm's parameters to match a different appetite for risk.

| Profile | k (confidence) | projUpper | Absolute bounds | Zone thresholds (rising) | Feel |
|---|---|---|---|---|---|
| **Patient**  | 3.0 | 1.6 | 0.55 / 1.05 | 0.38 / 0.62 / 0.85 | Trusts bursts, alarms late |
| **Balanced** | 5.0 | 1.4 | 0.50 / 1.00 | 0.30 / 0.55 / 0.78 | Default tuning, validated against the test matrix |
| **Vigilant** | 8.0 | 1.2 | 0.45 / 0.90 | 0.22 / 0.45 / 0.68 | Reads early signals as risk, alarms sooner |

`k` controls how fast the time-derived components gain confidence in the rate. `projUpper` controls how aggressively the projection saturates - a lower value means a smaller projected overflow already screams. Zone thresholds control where the discrete `PacingZone` mapping switches (used by notifications + the pacing pill).

Profiles are persisted in `UserDefaults` and mirrored to the shared file so the widget process picks up the same value (`SharedFileService.smartColorProfile`).

### Hysteresis (zone discretization only)

The continuous risk score is also discretized into 4 zones (chill / onTrack / warning / hot) for the pacing pill + notifications. This discretization uses a 5pp falling buffer to prevent flicker when the risk oscillates around a band boundary :

```text
rising thresholds:  chill < 0.30 <= onTrack < 0.55 <= warning < 0.78 <= hot   (Balanced profile)
falling thresholds: keep onTrack until r < 0.25
                    keep warning until r < 0.50
                    keep hot     until r < 0.73
```

This only affects the discrete zone derivation. The continuous risk score itself has no hysteresis - the gauge color follows the score directly.

### Validation matrix

Edge cases the v2 algorithm gets right (and v1 did not). All scenarios assume `θw = 0.60`, `θc = 0.85`, `m = 0.10`, Balanced profile :

| Scenario | u | e | Expected | v1 wrong because | v2 result |
|---|---|---|---|---|---|
| Just started, healthy burst | 0.05 | 0.01 | chill | n/a | risk ≈ 0.04 -> chill ✅ |
| 80% used, 50% elapsed | 0.80 | 0.50 | hot | n/a | absolute = 0.90, projHealth = 1 -> red ✅ |
| **98% used, 30 min left on 5h** | 0.98 | 0.90 | hot | reset-imminent override pulled it green | risk = 1.0 -> red ✅ |
| **75% used at 1h01 vs 59min on 5h** | 0.75 | 0.79 / 0.80 | same band | discrete cliff between two adjacent samples | continuous, no cliff ✅ |
| **72% used at 4h12 on 5h, calm pacing** | 0.72 | 0.84 | chill | absolute fired alone despite safe projection | projHealth ≈ 0.53, absolute damped to 0.25 -> chill ✅ |
| 50% used, 90% elapsed | 0.50 | 0.90 | chill | n/a | absolute = 0, projHealth ≈ 0 -> chill ✅ |
| Hard cap | 1.0 | any | hot | n/a | risk = 1.0 (hard cap) ✅ |

The v1 cliffs all came from `if`-based ladders (threshold band, pacing band, override gate). v2's smoothstep + max + continuous interpolation eliminates them by construction.

### When the formula is bypassed

- `utilization >= 100` -> immediate `risk = 1.0` (hard cap, short-circuits all components).
- `resetDate == nil` -> falls back to absolute-only (no projection, no pacing).
- `windowDuration <= 0` -> falls back to absolute-only.

## 3. Pacing zones (delta-based, 4 zones)

Independent system. Compares actual usage to the expected usage at the same point in the window. Drives the pacing badges, dots, track bars, and the "On track / Watch out" labels.

### Formula

```swift
elapsedFraction = elapsed / windowDuration   // 0..1
expectedUsage   = elapsedFraction × 100      // ideal pace at this moment
delta           = actualUsage − expectedUsage   // points

delta < -margin             -> chill   (green) - ahead of pace, healthy
-margin <= delta <= +margin -> onTrack (blue)  - at the ideal pace
+margin <  delta <= 2×margin -> warning (orange) - drifting fast, watch out
delta > 2×margin            -> hot     (red)   - burning much faster than ideal
```

Default `margin` : 10 points. Configurable via the **Pacing Sensitivity** slider (Settings -> Themes -> Pacing margin, range 5..30 in steps of 5). The warning threshold is automatically `2 × margin` so a single slider drives both bounds.

### Iconography

| Zone | Color | Icon |
|---|---|---|
| chill   | green  | `leaf.fill`  |
| onTrack | blue   | `bolt.fill`  |
| warning | orange | `hare.fill`  |
| hot     | red    | `flame.fill` |

The hare is the visual signal "you're going faster than ideal but not yet on fire". Between bolt (on-pace) and flame (overheating).

### Why pacing and smart can disagree

They answer different questions :

- **Pacing** : "Am I drifting from the ideal pace right now ?" -> based on `delta` vs `expected`.
- **Smart** : "What's my real risk of overshooting ?" -> based on the continuous risk model (absolute + projection + pacing combined via `max`).

Concrete example : 30% used in the first hour of a 7-day window.
- Pacing : expected ~0.6%, delta = +29.4 -> **hot** (red).
- Smart : `absolute = 0` (well below threshold), `projection = u/e = 30 -> saturated raw 1.0` but `confidence(0.006, k=5) ≈ 0.03` -> projection ≈ 0.03. `pacing` similarly damped. Overall risk near 0 -> **chill** (green).

Both make sense from their own angle. The v2 confidence weighting is what lets smart stay calm in this scenario where v1 would have screamed - the rate is unreliable so early in the window. The pacing pill shows the raw delta truthfully, the gauge reflects calibrated risk.

## Color tokens

Per-theme, defined in `ThemeColors`. Each preset (default / monochrome / neon / pastel / custom) provides its own values for these slots :

| Token | Used by | Default preset value |
|---|---|---|
| `gaugeNormal`   | Threshold + smart anchor 0.0 / 0.30 | `#22C55E` |
| `gaugeWarning`  | Threshold + smart anchor 0.55       | `#F97316` |
| `gaugeCritical` | Threshold + smart anchor 0.85 / 1.0 | `#EF4444` |
| `pacingChill`   | Pacing chill    | `#32D74B` |
| `pacingOnTrack` | Pacing onTrack  | `#0A84FF` |
| `pacingWarning` | Pacing warning  | `#FF9500` |
| `pacingHot`     | Pacing hot      | `#FF453A` |

The smart gauge interpolates between the three `gauge*` tokens on the [0, 1] risk axis. `pacingWarning` was added in v5.0 with the 4-zone extension. Older custom themes that omit it decode silently to `#FF9500` (handled by a custom `init(from:)` on `ThemeColors`).

## Where each system applies

| Surface | Threshold | Smart | Pacing |
|---|---|---|---|
| Menu bar percentages (5h, 7d, sonnet, design) | fallback | yes | n/a |
| Menu bar reset countdown text | fallback | yes | n/a |
| Menu bar pacing pill / dot | n/a | n/a | yes |
| Stats hero ring + value | fallback | yes | n/a |
| Stats hero zone glyph (centered) | n/a | n/a | yes |
| Stats metric tiles (weekly, sonnet, design) | fallback | yes | n/a |
| Stats pacing sub-row + track | n/a | n/a | yes |
| Popover hero / satellite / equal rings | fallback | yes | n/a |
| Popover compact chips | fallback | yes | n/a |
| Popover focus hero / satellites | fallback | yes | n/a |
| Popover pacing rows / bars | n/a | n/a | yes |
| Widget circular gauges | fallback | yes | n/a |
| Widget large bars | fallback | yes | n/a |
| Notification levels (orange / red banners) | fallback | yes (via legacy 3-level mapping) | indirect |

## User-facing toggle + profile picker

`Settings -> Themes -> Smart Color` controls the smart vs threshold path globally. Default ON since v5.0.

When ON, three card-style chips let the user choose between `Patient` / `Balanced` / `Vigilant` profiles. Each card carries an icon + label + tagline so the temperament reads at a glance. The popover info icon expands into a 3-signal breakdown (absolute / projection / pacing) + a `combined via max` note + a profile reminder.

**Threshold sliders are hidden when smart is ON.** The profile owns full calibration in smart mode (k, projUpper, absolute bounds, zone thresholds). The threshold sliders only drive the threshold-mode coloring (when Smart Color is OFF) - which is conceptually correct, since "where exactly does red fire" is a threshold-mode concern. Smart users delegate that decision to their chosen profile.

The toggle + profile are both mirrored to the shared file (`SharedFileService.smartColorEnabled` + `SharedFileService.smartColorProfile`) so the sandboxed widget reads the same state without round-tripping through the app process.

## Edge cases & recoveries

1. **No reset date returned by the API** : usage bucket without `resets_at`. Smart falls back to absolute-only (no projection / pacing component). Pacing returns nil and the pacing UI degrades gracefully (zone glyph -> `sparkles`, no track).

2. **Window duration unknown / zero** : smart falls back to absolute-only.

3. **Custom theme without `pacingWarning`** : custom decoder substitutes `#FF9500`. The user can edit it later via the custom-theme color picker.

4. **`utilization` exceeds 100** : both threshold and smart return critical (red, hard cap). Pacing also lands hot due to `delta > 2×margin`.

5. **Reduce-motion preference** : color transitions are still applied (this is information, not motion). Spring animations on value changes are reduced as documented in `MASTER.md`.

## File map

| File | Role |
|---|---|
| `Shared/Helpers/SmartColor.swift`         | Pure functional v2 risk model: smoothstep, confidence, the 3 components, max combinator, color interpolation, zone hysteresis, legacy 3-level mapping |
| `Shared/Models/SmartColorProfile.swift`   | `SmartColorProfile` enum + `SmartColorParameters` struct (k, projUpper, zone thresholds) |
| `Shared/Models/PacingModels.swift`        | `PacingZone` enum (4 cases) |
| `Shared/Helpers/PacingCalculator.swift`   | Pacing zone computation |
| `Shared/Models/ThemeModels.swift`         | `ThemeColors` + the public smart wrappers (`smartRisk`, `smartGaugeColor`, `smartGaugeNSColor`, `smartGaugeGradient`, `smartLevel`, `smartZone`) |
| `Shared/Helpers/MenuBarRenderer.swift`    | Menu bar coloring (NSColor variants, profile-aware) |
| `TokenEaterApp/MonitoringView.swift`      | Stats hero + tiles + pacing sub-rows |
| `TokenEaterApp/Popover/*.swift`           | Popover layouts (Classic / Compact / Focus) |
| `TokenEaterWidget/UsageWidgetView.swift`  | Widget gauges + bars |
| `Shared/Services/SharedFileService.swift` | `smartColorEnabled` + `smartColorProfile` propagation to the widget process |
| `TokenEaterTests/SmartColorTests.swift`   | Validation matrix (continuity, monotonicity, hysteresis, end-to-end via ThemeColors) |

## Related

- `docs/design/MASTER.md` -> chrome / typography / spacing / motion design tokens.
- `docs/v5.0-post-cert-checklist.md` -> Apple Dev migration steps.
