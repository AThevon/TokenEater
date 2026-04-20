# Popover Customization & Settings Harmonization

**Date**: 2026-04-20
**Status**: design — awaiting user review
**Scope target**: v4.11.0

---

## Context

The TokenEater popover (menu bar dropdown) currently hardcodes its content: two rings (Session 5h + Weekly, or hero + 2 satellites when Sonnet is pinned), two pacing bars, a watchers block, a timestamp, and an "Open TokenEater" / Quit footer.

Two issues drive this redesign:

1. **martinlukk (#139)** asked for the reset countdown to be visible in the popover without having to pin it to the menu bar. The current coupling forces `.sessionReset` to be either shown in both menu bar and popover or in neither.

2. The broader settings architecture has drifted. "Display" only customises the menu bar, "Themes" touches menu bar text colours, the popover has no config section, and the codebase has grown past the point where ad-hoc additions feel right.

## Goals

1. Give the popover a customisation model that matches the menu bar's (pins, display format) without forcing the two surfaces to stay coupled.
2. Add **3 layout variants** (Classic, Compact, Focus) so different usage patterns (quick glance, data-dense, time-conscious) each get a first-class layout.
3. Make every non-critical block **individually toggleable and reorderable** within its zone, with a live preview.
4. Surface the reset countdown prominently for **both 5h and weekly** buckets, fulfilling the original reporter's ask.
5. Rename `Display` → `Menu bar` and add a dedicated `Popover` section, so the sidebar mental model becomes "one surface = one section".

## Non-goals (out of scope for this spec)

- Customising the Widgets (medium/large/small) — they have almost no config today and no open request warranting a redesign. Deferred.
- Drag-and-drop **between** zones (e.g. promoting a pacing bar into the hero slot). Intra-zone drag only. The variant itself defines zone boundaries.
- Theming variants independently (e.g. a custom colour scheme only for the Compact variant). Themes stay global.
- Per-variant sync interval or refresh behaviour.

---

## Architecture

### Sidebar restructure

```
Before             After
─────              ─────
Dashboard     →    Dashboard
Display       →    Menu bar      (renamed; scope unchanged)
Themes        →    Themes        (unchanged)
                   Popover       (new)
Agent Watchers →   Agent Watchers
Performance   →    Performance
Settings      →    Settings
```

**`AppSection` enum** gets a new `popover` case inserted between `themes` and `agentWatchers`. The `display` raw value stays `"display"` to avoid breaking persisted `lastSelectedSection` UserDefault; only the user-facing label changes.

### Popover data model

```swift
enum PopoverVariant: String, Codable, CaseIterable {
    case classic, compact, focus
}

/// Every block that can appear in a zone and be independently
/// toggled / reordered. Variant-specific blocks coexist in the same
/// enum so the editor / renderer use one shared type.
enum PopoverBlockID: String, Codable, CaseIterable {
    // Classic hero
    case sessionRing, weeklyRing
    // Classic middle
    case sessionPaceBar, weeklyPaceBar
    // Compact minicards (fused hero+middle zone)
    case sessionChip, weeklyChip, sessionPaceTile, weeklyPaceTile
    // Focus middle minis
    case sessionPaceMini, weeklyPaceMini
    // Shared middle
    case watchers, timestamp
    // Footer
    case openTokenEaterButton, quitButton
}

/// Focus-only: which of four candidates gets rendered as the big
/// hero piece. Not mixed with `PopoverBlockID` because these don't
/// appear in drag lists - they're radio-selected.
enum FocusHeroChoice: String, Codable, CaseIterable {
    case sessionReset, weeklyReset, sessionValue, weeklyValue
}

enum PopoverZone: String, Codable {
    case hero, middle, footer
}

struct BlockState: Codable, Equatable {
    let id: PopoverBlockID
    var hidden: Bool
}

struct VariantLayout: Codable, Equatable {
    var hero: [BlockState]
    var middle: [BlockState]
    var footer: [BlockState]
}

struct PopoverConfig: Codable, Equatable {
    var activeVariant: PopoverVariant
    var classic: VariantLayout
    var compact: VariantLayout
    var focus: VariantLayout
    /// Which candidate is promoted to the big hero slot in the Focus
    /// variant. The other 3 are auto-rendered as 2 satellite cards
    /// (the 2 most relevant to the hero choice).
    var focusHero: FocusHeroChoice
}
```

The `PopoverConfig` is stored under a single `UserDefaults` key (`popoverConfig`) as JSON. Switching variants never touches the other variants' layouts, so every user can keep 3 distinct preferences.

### Variant specifications

**Variant A — Classic (default)**

- `hero` = `[sessionRing, weeklyRing]` — 2 blocks, drag-reorderable, each toggleable off. Hiding both is rejected by validation.
- `middle` = `[sessionPaceBar, weeklyPaceBar, watchers, timestamp]` — 4 blocks, drag-reorderable, each toggleable off (zero is fine, the zone collapses).
- `footer` = `[openTokenEaterButton, quitButton]` — 2 blocks, drag-reorderable, each toggleable off.
- **Reset countdown placement**: a small "in 1h25" (5h) caption below the session ring, and "resets Thu 19:00" below the weekly ring. Always visible when the corresponding ring is visible. No separate toggle for the countdowns — they're part of the ring block.

**Variant B — Compact ticker**

- `hero` is unused (empty array).
- `middle` is a **single zone** containing all minicards and non-footer blocks: `[sessionChip, weeklyChip, sessionPaceTile, weeklyPaceTile, watchers, timestamp]` — 6 blocks, freely reorderable between themselves. Putting `sessionChip` at index 0 and resizing via CSS isn't supported; if the user wants a "big hero", they switch to Focus.
- `footer` = `[openTokenEaterButton, quitButton]`.
- **Reset countdown placement**: inside each chip/tile. `sessionChip` shows "1h25 left" as subtitle, `weeklyChip` shows "resets Thu".

**Variant C — Focus reset**

- `hero` is a **radio choice** over 4 candidates (`FocusHeroChoice` enum). The chosen one renders as the big centrepiece (arc + large typo):
    - `.sessionReset` — "1h25 until reset" as main typo, arc showing 5h progress
    - `.weeklyReset` — "3d 14h until reset" (or "Thu 19:00") as main typo, arc showing 7d progress
    - `.sessionValue` — "53%" as main typo, ring of session util
    - `.weeklyValue` — "75%" as main typo, ring of weekly util
- Immediately below the hero, a fixed **2-card satellites row** auto-renders the 2 most relevant non-hero metrics given the hero choice. This is **not user-configurable** (not in the drag list, not individually toggleable) - it's a reflex of the hero choice:

    | Hero choice        | Sat card 1     | Sat card 2     |
    |--------------------|----------------|----------------|
    | `.sessionReset`    | Session 53%    | Weekly 75%     |
    | `.weeklyReset`     | Weekly 75%     | Session 53%    |
    | `.sessionValue`    | 1h25 reset     | Weekly 75%     |
    | `.weeklyValue`     | 3d 14h reset   | Session 53%    |

- `middle` = `[sessionPaceMini, weeklyPaceMini, watchers, timestamp]` - 4 blocks, drag-reorderable, each toggleable off.
- `footer` = `[openTokenEaterButton, quitButton]`.
- The radio picker for `focusHero` is a distinct control at the top of the Hero zone in settings, not part of any drag list.

### Settings section UI

`PopoverSectionView` structure (top to bottom):

1. **Variant picker** — segmented control with 3 options (Classic / Compact / Focus).
2. **Live preview** — the real `MenuBarPopoverView` rendered as a sub-view, bound to the same `PopoverConfig` the user is editing. Updates in real time on every toggle, drag, or variant switch.
3. **Reset to defaults** — button that restores the default layout **for the active variant only** (not all 3).
4. **Zones** — 3 scrollable sub-sections (Hero / Middle / Footer), each rendering a `BlockListEditor`.

For Focus specifically, the Hero zone renders as a radio group with 4 rows (one per hero candidate) plus a "Promoted" indicator on the active one, and the list is not drag-reorderable (only the radio choice matters).

### `BlockListEditor` component

Generic SwiftUI view that takes a `Binding<[BlockState]>` and renders a reorderable list. Each row is:

```
[☰ drag handle]  [☑ toggle]  [block label]
```

Uses `List { ForEach ... }.onMove { ... }` for native drag. `List` is wrapped in a bounded-height container (`.listStyle(.plain)` + explicit height) so it doesn't fight the outer `ScrollView`.

### Transition animations

- **Variant switch**: cross-fade 120ms + scale 0.97 → 1.0 on the new layout. Respects `prefers-reduced-motion` (transitions become instant when the system setting is on).
- **Drag reorder**: default SwiftUI `.onMove` spring (unchanged).
- **Block toggle on/off**: fade + collapse in 150ms.

### Persistence & migration

**Keys:**

| Key | Type | Meaning |
|-----|------|---------|
| `popoverConfig` | Data (Codable JSON) | The whole `PopoverConfig` |
| `pinnedMetrics` | [String] | Unchanged. Still drives menu bar pins only. |

**Migration at first launch of v4.11.0:**

If `popoverConfig` is absent, build default `PopoverConfig`:
- `activeVariant = .classic`
- `classic.hero = [sessionRing (visible), weeklyRing (visible)]`
- `classic.middle = [sessionPaceBar (visible), weeklyPaceBar (visible), watchers (visible), timestamp (visible)]`
- `classic.footer = [openTokenEaterButton (visible), quitButton (visible)]`
- `compact.middle = [sessionChip, weeklyChip, sessionPaceTile, weeklyPaceTile, watchers, timestamp]` (all visible)
- `compact.hero = []` (unused)
- `compact.footer = [openTokenEaterButton, quitButton]`
- `focus.hero = []` (drives the layout via `focusHero`, not a drag list)
- `focus.middle = [sessionPaceMini, weeklyPaceMini, watchers, timestamp]` (all visible)
- `focus.footer = [openTokenEaterButton, quitButton]`
- `focusHero = .sessionReset`

Users coming from v4.10.x see no visible change — Classic with all blocks visible matches the existing popover.

**Writes are debounced** on drag: `onMove` updates an in-memory `@Published` copy of the config, but UserDefaults is only written on `onDrop` / on settings change. Prevents frame-rate-coupled writes during a live drag.

### Validation rules

- Classic: `hero` cannot have zero visible blocks. Toggle is disabled on the last visible ring.
- Compact: `middle` cannot have zero visible blocks.
- Focus: `hero` always has exactly one promoted block (radio forces it).
- `footer` can be empty in any variant.
- Invariant enforced in `PopoverConfig` setter/validator (not just UI).

### Reset countdown formatting (shared)

A new helper `ResetCountdownFormatter` centralises:

- 5h relative: `1h25`, `25min`, `now`
- 5h absolute: `20:30`, `Fri 08:00`
- 7d relative: `3d 14h`, `14h`, `now`
- 7d absolute: `Thu 19:00`, `Apr 24 19:00` (if > 6 days out)
- Both: `1h25 - 20:30` / `3d 14h - Thu 19:00`

This replaces the inline formatting in `UsageStore.refreshResetCountdown` for the 5h bucket and adds the weekly path. The formatter takes a `ResetDisplayFormat` (the existing `.relative / .absolute / .both` enum is reused, not duplicated per surface).

### Per-surface display format (deferred to v4.12 if ever needed)

The user kept the format global (menu bar and popover share `resetDisplayFormat`). If a future request asks for per-surface formats, split into `menuBarResetFormat` and `popoverResetFormat` then. Not baked in now to avoid adding a setting with no matching ask.

---

## Components map

| Component | Purpose | Location |
|-----------|---------|----------|
| `PopoverVariant`, `PopoverBlockID`, `FocusHeroChoice`, `VariantLayout`, `PopoverConfig` | Data model | `Shared/Models/PopoverLayoutModels.swift` (new) |
| `ResetCountdownFormatter` | 5h + 7d countdown formatting | `Shared/Helpers/ResetCountdownFormatter.swift` (new) |
| `PopoverConfigStore` OR settings extension | Load / save / migrate | `Shared/Stores/SettingsStore.swift` (extended, new `@Published var popoverConfig`) |
| `MenuBarPopoverView` (refactored) | Dispatch on `popoverConfig.activeVariant` | `TokenEaterApp/MenuBarView.swift` |
| `ClassicLayoutView`, `CompactLayoutView`, `FocusLayoutView` | One per variant | `TokenEaterApp/Popover/` (new folder) |
| `PopoverBlockView` | Maps a `PopoverBlockID` to its rendered view | `TokenEaterApp/Popover/PopoverBlockView.swift` |
| `PopoverSectionView` | Settings section root | `TokenEaterApp/PopoverSectionView.swift` (new) |
| `VariantPickerView` | Segmented control | `TokenEaterApp/Popover/VariantPickerView.swift` |
| `BlockListEditor` | Reorderable toggle list | `TokenEaterApp/Popover/BlockListEditor.swift` |
| `FocusHeroPicker` | Radio for Focus hero choice | `TokenEaterApp/Popover/FocusHeroPicker.swift` |
| `LivePopoverPreview` | Framed popover preview inside settings | `TokenEaterApp/Popover/LivePopoverPreview.swift` |
| `AppSidebar`, `AppSection` | Add `popover` case + label `Menu bar` for `display` | `Shared/Models/AppSection.swift`, `TokenEaterApp/AppSidebar.swift` |

---

## Data flow

```
SettingsStore.popoverConfig  (@Published)
    │
    ├─► MenuBarPopoverView ──► Variant dispatch ──► ClassicLayoutView (or Compact/Focus)
    │                                                    │
    │                                                    └─► ForEach(middle) { PopoverBlockView(id:) }
    │
    └─► PopoverSectionView ──► VariantPickerView (sets activeVariant)
                              ├─► LivePopoverPreview (renders MenuBarPopoverView bound to same config)
                              └─► BlockListEditor (per zone) ──► .onMove / toggle ──► writes back to config
```

## Error handling

- Invalid persisted config (e.g. a `PopoverBlockID` raw value that no longer exists after a future enum rename) falls back to defaults on decode failure.
- If `focusHero` decodes to an unknown raw value (schema drift), reset to `.sessionReset` on load.
- Validation failures on toggle attempts are silently prevented by disabling the offending control in the UI (no error dialog).

## Testing

- Snapshot tests for `ClassicLayoutView`, `CompactLayoutView`, `FocusLayoutView` at each default config + edge cases (everything hidden except the required minimum).
- Unit tests for `PopoverConfig` encoding / decoding round-trip.
- Unit tests for migration: no prior `popoverConfig` key → produces valid defaults that match v4.10.x visual output exactly.
- Unit tests for `ResetCountdownFormatter`: 5h cases, 7d cases, absolute-date rollover at the week boundary.
- Interactive validation: mega-nuke + install, verify all 3 variants render correctly, drag works, reset countdown shows for both buckets.

## Build sequence (rough)

1. Data model + persistence + migration.
2. Split `MenuBarPopoverView` into a dispatcher + 3 variant views. Wire v4.10.x behaviour into Classic.
3. Add `ResetCountdownFormatter` and the weekly countdown rendering.
4. Compact and Focus variant views.
5. `PopoverSectionView` shell + `VariantPickerView`.
6. `LivePopoverPreview` (just a scoped render of the dispatcher with a preview-only state container).
7. `BlockListEditor` with drag + toggle.
8. `FocusHeroPicker`.
9. Sidebar rename + new `popover` case.
10. Localizations (en + fr) for all new labels.
11. Tests.
12. Documentation updates in `tokeneater-site` (features + FAQ).

## Known risks / open questions

- The Focus variant's arc + large typo requires care to match the existing app's visual weight (glow, font). Expect iteration in implementation.
- Drag gesture inside a scrolled settings pane on macOS can fight the outer scroll. SwiftUI's `List` handles this natively — if we ever move off `List` for the editor, we'll need to tune the hit region manually.
- On the smaller popover (320 px), Compact's 6-chip middle with 2 columns can get vertically tall (~400 px). Acceptable, but if it becomes cramped we may drop one block by default and add it via the editor.
