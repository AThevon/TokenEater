# Usage API contract checker

A maintainer canary for the Anthropic usage endpoint (`/api/oauth/usage`).

TokenEater decodes that response tolerantly: every field is `try?`, so when
Anthropic renames or removes a key, the matching bucket silently becomes `nil`
and a card just goes empty (this is exactly how the Design bucket disappeared).
That robustness hides upstream contract changes. This tool makes them loud: it
fetches the live response, reduces it to a **value-free shape signature**, and
diffs it against a committed baseline. On a meaningful change it opens (or
comments on) a GitHub issue labelled `contract-drift`.

## Why local, not CI

The endpoint needs your personal OAuth token, which Claude Code keeps refreshed
in `~/.claude/.credentials.json` (or the `Claude Code-credentials` Keychain
item). Reading that locally is trivial. Shipping a rotating personal token into
CI secrets would be fragile (the access token expires in hours) and a security
smell, so the checker runs on your machine via `launchd`, and only reaches
GitHub through your already-authenticated `gh`.

## What counts as drift

The signature captures only structure, never usage values:

- top-level keys and their types,
- the nested key set of each top-level object,
- for `limits[]`: the entry key set, the set of `kind` and `group`, and the set
  of model `display_name`s.

An issue is triggered by **breaking** changes (a key or field removed, a type
changed, a `kind` gone, the `limits` array missing) and by **additive** changes
(a new key, field, or `kind`). Model display names only track which models you
used this period, so they are reported for context but never trigger on their
own. Repeated daily runs of the same unresolved drift do not re-notify.

### What lands where (names stay private)

The field, kind and model names, and the full shape, can include Anthropic's
unreleased API codenames, so they never leave your machine: the full diff and
signature go to the local log (`~/Library/Logs/tokeneater-contract-check.log`)
and `--dry-run` output. The **public GitHub issue only gets a redacted category
summary** ("1x New top-level key, 3x New field"), never the names.

### Known limitation: a field silently going null

A field flipping to `null` is intentionally **not** an alert, only a note. From a
single snapshot the tool cannot tell "Anthropic emptied/retired this field" (the
Design/`seven_day_omelette` bucket case) from "this account just didn't use it
this period", and treating every null flip as drift would be pure noise. So a
bucket quietly becoming null is surfaced as a note when something else already
triggered, but will not, on its own, open an issue. Removed keys, new keys, type
changes and new limit kinds are all still caught normally.

## First-time setup

Requirements: Xcode toolchain (`xcrun swift`), and `gh` authenticated
(`gh auth status`).

1. Capture the current contract as the baseline (do this while Claude Code has a
   fresh token, i.e. after using it recently):

   ```bash
   Tools/contract-check/run.sh --update-baseline
   ```

   The baseline is **git-ignored on purpose**: it reflects the buckets and
   models your own account currently sees, and it can contain Anthropic's
   internal feature codenames, so it stays local rather than being published.

2. Sanity-check the diff logic (prints a report, touches nothing):

   ```bash
   Tools/contract-check/run.sh --dry-run
   ```

3. Install the daily schedule (09:00):

   ```bash
   Tools/contract-check/install-launchd.sh
   ```

   Run it once immediately to confirm it works:

   ```bash
   launchctl kickstart -k gui/$(id -u)/dev.athevon.tokeneater.contract-check
   tail ~/Library/Logs/tokeneater-contract-check.log
   ```

## When an issue fires

1. Read the diff in the issue.
2. Adapt `Shared/Models/UsageModels.swift` (and anything downstream).
3. Re-capture the baseline (local only, nothing to commit):

   ```bash
   Tools/contract-check/run.sh --update-baseline
   ```

4. Close the issue. The checker clears its dedup state automatically once the
   live response matches the baseline again.

## Commands

| Command | Effect |
|---------|--------|
| `run.sh` | Fetch, compare, open/comment an issue on drift. |
| `run.sh --dry-run` | Fetch, compare, print the report. Touches nothing else. |
| `run.sh --update-baseline` | Capture the current shape as the new baseline. |
| `run.sh --print` | Print the current shape signature. |
| `install-launchd.sh` | Install + load the daily job. |
| `install-launchd.sh --uninstall` | Stop + remove the job. |

## Moving to another machine

Clone the repo, make sure `gh` is authenticated and Claude Code has run once
(so the token exists), then re-capture the baseline and re-install:

```bash
Tools/contract-check/run.sh --update-baseline
Tools/contract-check/install-launchd.sh
```

The baseline is local (git-ignored), so it does not travel with the repo: that
one `--update-baseline` is all you carry over.
