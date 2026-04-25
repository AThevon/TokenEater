# TokenEater Coloring System

Reference doc for how colors are computed across the app. Three independent systems coexist, each answering a different question.

## Overview

| System | Question it answers | Where it applies |
|---|---|---|
| **Threshold gauge** | "How full is this bucket right now?" | Fallback when smart is OFF, or when no `resetDate` is available |
| **Smart gauge** | "Will I overshoot before the next reset?" | Default ON. Drives the gauge / percentage colors when `Smart Color` is enabled in Themes |
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

## 2. Smart gauge (composite : threshold + pacing, with reset-imminent override)

The default since v5.0. Couples the two independent severity signals (threshold band + pacing zone) and surfaces the worst of the two, while a short-cycle override pulls everything back to green when a reset is imminent.

### Decision tree

```text
1. utilization >= 100                          -> critical   (hard limit hit)
2. remainingFraction < imminentThreshold       -> normal     (reset arriving, ignore band)
   imminentThreshold = 0.10  on 5h windows     (last ~30 min)
                     = 0.05  on 7d windows     (last ~8h)
3. otherwise:
   absolute = green (<warning%) | orange (>=warning%) | red (>=critical%)
   pacing   = green (chill / onTrack)
            | orange (delta in (margin, 2×margin])
            | red    (delta > 2×margin)
   smart    = max(absolute, pacing)
```

`absolute` reuses the threshold-gauge logic (system 1). `pacing` is computed inline from the same inputs the pacing system uses (delta = utilization - elapsedFraction × 100, vs the user's `pacingMargin`). `windowDuration` is the rolling window length:
- `5h` for the `fiveHour` bucket
- `7d` for `sevenDay`, `sevenDaySonnet`, `sevenDayDesign`

### Why this shape

The pre-v5.1 smart formula was `risk = utilization × remainingFraction` with breakpoints at 20 / 30. It tripped orange far too eagerly: at 33% util with 64% of the window remaining, risk = 21 -> orange while the user was calmly on track. The user-visible signal felt out of step with the pacing pill in the same view.

Coupling threshold + pacing instead, with `max` as the combinator, keeps the safety net (high utilization or hot pacing always escalates) without the false positives in early-cycle low-util zones.

### Cheat sheet for the 5h session

| Util | Time in cycle | Pacing zone | Absolute | Smart |
|---|---|---|---|---|
| 33% | 1h49 in (36% elapsed) | onTrack | green (<60) | **green** |
| 95% | 4h58 in (99% elapsed) | onTrack | red (>=85) | **green** (reset imminent) |
| 100% | any | n/a | red | **red** (limit hit) |
| 70% | 2h in (40% elapsed) | hot (delta +30) | orange | **red** |
| 75% | 4h in (80% elapsed) | onTrack | orange | **orange** |
| 30% | 30 min in (10% elapsed) | hot (delta +20) | green | **red** |

### When the formula is bypassed

- `utilization >= 100` -> immediate critical (override).
- `resetDate == nil` -> falls back to the threshold gauge (system 1).
- `windowDuration <= 0` -> falls back to the threshold gauge.

## 3. Pacing zones (delta-based, 4 zones)

Independent system. Compares actual usage to the expected usage at the same point in the window. Drives the pacing badges, dots, track bars, and the "On track / Watch out" labels.

### Formula

```swift
elapsedFraction = elapsed / windowDuration   // 0..1
expectedUsage   = elapsedFraction × 100      // ideal pace at this moment
delta           = actualUsage − expectedUsage   // points

delta < -margin            -> chill   (green) - ahead of pace, healthy
-margin <= delta <= +margin -> onTrack (blue)  - at the ideal pace
+margin <  delta <= 2×margin -> warning (orange) - drifting fast, watch out
delta > 2×margin           -> hot     (red)   - burning much faster than ideal
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
- **Smart** : "Will I run out before reset ?" -> based on projected risk.

Concrete example : 30% used in the first hour of a 7-day window.
- Pacing: expected ~0.6%, delta = +29.4 -> **hot** (red).
- Smart : risk = 30 × 0.99 = 29.7 -> **warning** (orange) close to red.

Both make sense from their own angle. The Stats card shows pacing in the sub-row separately from the gauge color so the user can read both signals without conflict.

## Color tokens

Per-theme, defined in `ThemeColors`. Each preset (default / monochrome / neon / pastel / custom) provides its own values for these slots :

| Token | Used by | Default preset value |
|---|---|---|
| `gaugeNormal`   | Threshold + smart (normal band)   | `#22C55E` |
| `gaugeWarning`  | Threshold + smart (warning band)  | `#F97316` |
| `gaugeCritical` | Threshold + smart (critical band) | `#EF4444` |
| `pacingChill`   | Pacing chill    | `#32D74B` |
| `pacingOnTrack` | Pacing onTrack  | `#0A84FF` |
| `pacingWarning` | Pacing warning  | `#FF9500` |
| `pacingHot`     | Pacing hot      | `#FF453A` |

`pacingWarning` was added in v5.0 with the 4-zone extension. Older custom themes that omit it decode silently to `#FF9500` (handled by a custom `init(from:)` on `ThemeColors`).

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
| Notification levels (orange / red banners) | yes | n/a | indirect |

## User-facing toggle

`Settings -> Themes -> Smart Color` controls the smart vs threshold path globally. Default ON since v5.0. The chrome of the toggle includes a popover (info icon) explaining the system with two visual examples (`95% / 2min` stays green, `50% / 5h` warns red).

The toggle is mirrored to the shared file (`SharedFileService.smartColorEnabled`) so the sandboxed widget reads the same state without round-tripping through the app process.

## Edge cases & recoveries

1. **No reset date returned by the API** : usage bucket without `resets_at`. Smart falls back to threshold-based color, pacing returns nil and the pacing UI degrades gracefully (zone glyph -> `sparkles`, no track).

2. **Window duration unknown / zero** : smart falls back to threshold.

3. **Custom theme without `pacingWarning`** : custom decoder substitutes `#FF9500`. The user can edit it later via the custom-theme color picker.

4. **`utilization` exceeds 100** : both threshold and smart return critical (red). Pacing also lands hot due to `delta > 2×margin`.

5. **Reduce-motion preference** : color transitions are still applied (this is information, not motion). Spring animations on value changes are reduced as documented in `MASTER.md`.

## File map

| File | Role |
|---|---|
| `Shared/Models/PacingModels.swift`        | `PacingZone` enum (4 cases) |
| `Shared/Helpers/PacingCalculator.swift`   | Pacing zone computation |
| `Shared/Models/ThemeModels.swift`         | `ThemeColors` + `gaugeColor` / `smartGaugeColor` / `pacingColor` |
| `Shared/Helpers/MenuBarRenderer.swift`    | Menu bar coloring (NSColor variants) |
| `TokenEaterApp/MonitoringView.swift`      | Stats hero + tiles + pacing sub-rows |
| `TokenEaterApp/Popover/*.swift`           | Popover layouts (Classic / Compact / Focus) |
| `TokenEaterWidget/UsageWidgetView.swift`  | Widget gauges + bars |
| `Shared/Services/SharedFileService.swift` | `smartColorEnabled` propagation to the widget process |

## Related

- `docs/design/MASTER.md` -> chrome / typography / spacing / motion design tokens.
- `docs/v5.0-post-cert-checklist.md` -> Apple Dev migration steps.
