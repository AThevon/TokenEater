<!-- contract-drift severity=active -->
The live usage responses no longer match the committed baselines in `Tools/contract-check/baselines/`. TokenEater decodes them tolerantly, so this would otherwise go unnoticed until a card silently empties.

| Provider | Breaking | Active | Dormant |
|----------|----------|--------|---------|
| Claude | 0 | 5 | 11 |

### Claude (`GET https://api.anthropic.com/api/oauth/usage`)

**Active: new data, or data that came back**

- new field `extra_usage.credits_can_pay` (`string`) on `extra_usage`, which TokenEater reads
- `seven_day_breakdown` is now `object` (was `null`)
- new `seven_day_breakdown.as_of` (`string`)
- new `seven_day_breakdown.rows` (`array`), with 5 nested paths
- new `seven_day_breakdown.window_started_at` (`string`)

**Dormant: batched, no action needed**

- new `amber_cistern_offer` (`null`)
- `five_hour` is now `null` (was `object`)
- new `granite_teacup` (`null`)
- new `indicator` (`null`)
- new `maple_sundial` (`null`)
- new `message_limit` (`null`)
- new `pace` (`null`)
- new `promo_credits` (`null`)
- new `starry_waterfall` (`null`)
- new `usage_credits_settings_path` (`null`)
- new `usage_scopes` (`null`)

### What to do

- Breaking: fix the decoder (`Shared/Models/UsageModels.swift` or `Shared/Models/CodexUsageModels.swift`) in a separate PR, then merge this one.
- Active: decide whether TokenEater should use it. Either way, merging this PR acknowledges it.
- Dormant entries ride along and need nothing.

Merging moves the committed baseline forward, so these changes stop being reported. Closing without merging only dismisses the PR: the same drift opens a new one at the next weekly run.

_Captured by `Tools/contract-check` at 2026-11-25T12:17:12Z (build 40986b2)._
