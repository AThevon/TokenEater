# Usage API contract check

TokenEater decodes the Claude and Codex usage responses tolerantly: a renamed key or a changed type empties a card instead of failing. This canary catches that once a week and turns it into a pull request, with no babysitting.

| Part | Where it runs | What it watches |
|------|---------------|-----------------|
| `contract-check` (Swift, `Sources/`) | The maintainer's Mac, hourly launchd job, real check weekly | The live Claude usage response, and the live Codex one when a Codex login exists |
| `contract-upstream.yml` | GitHub Actions, Mondays | The openai/codex model files that define the Codex payload (no credential) |
| `contract-heartbeat.yml` | GitHub Actions, daily | That the local job is still reporting |
| `contract-drift-pr.yml` | GitHub Actions, on push | Turns the local job's drift branch into a PR, deletes bot branches after merge |

The Claude check has to run locally: the usage endpoint only accepts the Claude Code login (a `claude setup-token` token lacks the `user:profile` scope), and copying that login to CI would break the laptop session. It only reads the login, exactly like the app: Keychain through `/usr/bin/security` first, then `~/.claude/.credentials.json`. It never refreshes a token.

## Install

Requirements: Xcode command line tools, and `gh` logged in with the `repo` scope (`gh auth status`).

```bash
Tools/contract-check/install.sh
```

This compiles the checker into `~/Library/Application Support/TokenEaterContractCheck/`, writes `~/Library/LaunchAgents/dev.athevon.tokeneater.contract-check.plist` with the absolute path of `gh` and a full `PATH`, and loads it. The job runs at load, then every hour at :17. Each provider is checked once every 7 days, at the first hour its token is usable (non-expired), and the job exits silently the rest of the time. The gate is per provider, so an expired Claude token never turns a Codex login into an hourly check. Rerun `install.sh` after changing `Sources/`.

Check that it works:

```bash
tail -f ~/Library/Logs/tokeneater-contract-check.log
launchctl print gui/$(id -u)/dev.athevon.tokeneater.contract-check | grep -E "state|last exit"
```

Uninstall:

```bash
Tools/contract-check/install.sh --uninstall
```

## One-time setup on GitHub

1. Settings > Actions > General > Workflow permissions: tick **Allow GitHub Actions to create and approve pull requests**. Without it the two PR workflows fail (visibly) at `gh pr create`.
2. Push from a `gh` login that has the `workflow` scope (`gh auth refresh -s workflow`), since this adds workflow files.
3. Install the local job soon after merging: the heartbeat watchdog opens an issue on its first daily run if the `CONTRACT_CHECK_HEARTBEAT` variable does not exist yet.

## What lands where

| Thing | Location |
|-------|----------|
| Committed baselines | `baselines/claude-usage.json`, `baselines/codex-usage.json` (created by the first Codex capture) |
| Paths the app decodes | `read-set.json` (`scripts/check-docs.py` fails when a `CodingKey` name ends no path here; it matches names, not parents, so a known key decoded under a new parent still needs its path added by hand) |
| openai/codex watch lock | `upstream/codex.lock.json` |
| Pending drift | branch `bot/contract-drift`, PR labelled `contract-drift` |
| Pending upstream change | branch `bot/contract-upstream`, PR labelled `contract-upstream` |
| Last acknowledged drift report | `reports/latest-drift.md` (lands on main with the merge) |
| Heartbeat | repository variable `CONTRACT_CHECK_HEARTBEAT` (statuses and dates only) |
| Job down | issue labelled `contract-check-down`, closed automatically once the job reports again |
| Local state and log | `~/Library/Application Support/TokenEaterContractCheck/state.json`, `~/Library/Logs/tokeneater-contract-check.log` |

A baseline records, for every JSON path, the set of types it has been seen with (`object`, `array`, `string`, `number`, `bool`, `null`, `absent`). Values are recorded only for classification fields (limit kinds and groups, model display names, Codex plan types, window durations, per-model limit names). Never emails, ids, tokens or amounts.

## How drift is graded

| Severity | Meaning | Effect |
|----------|---------|--------|
| Breaking | A path in `read-set.json` is missing, or holds a type the decoder does not accept | Opens or updates the drift PR |
| Active | A new non-null path, a null path that filled up, a new field on an object the app reads, a new kind, model, window or plan | Opens or updates the drift PR |
| Dormant | A new key that is only ever null, or an unread key gone quiet | Never opens a PR alone, rides along with the next one |

The local job writes the new baseline and the report to `bot/contract-drift` through the GitHub API (no git command, no worktree touched), and `contract-drift-pr.yml` opens the PR as github-actions[bot], so the notification reaches the maintainer. Merging the PR acknowledges the drift: the baseline on main moves forward and those changes stop being reported. Closing it without merging only dismisses it, the same drift comes back the next week.

## Manual runs

```bash
# Fetch and grade now, print the result, write nothing anywhere
~/Library/Application\ Support/TokenEaterContractCheck/contract-check --dry-run

# Same, against this checkout instead of main, saving the live signatures
~/Library/Application\ Support/TokenEaterContractCheck/contract-check --dry-run \
  --local Tools/contract-check --save /tmp/contract

# Grade two signature files offline
~/Library/Application\ Support/TokenEaterContractCheck/contract-check \
  --compare old.json new.json --provider claude

# Run the scheduled path now, ignoring the weekly gate
~/Library/Application\ Support/TokenEaterContractCheck/contract-check --force
```

`--provider claude|codex` limits any of these to one provider. The upstream and heartbeat workflows can be started by hand from the Actions tab.

To rehearse the publishing path without touching this repo or calling an endpoint, point it at a fork, a scratch state folder and saved raw responses (`claude-usage.json`, `codex-usage.json`):

```bash
CONTRACT_CHECK_REPO=you/TokenEater-fork CONTRACT_CHECK_HOME=/tmp/cc-state \
CONTRACT_CHECK_REPLAY=/tmp/cc-responses \
  ~/Library/Application\ Support/TokenEaterContractCheck/contract-check --force
```

## When something goes wrong

- **A `contract-check-down` issue opened.** Most often Claude Code has not been opened for a while and its token expired: open it once and the next hourly run catches up. Otherwise check the log, `gh auth status`, and that the job is loaded.
- **The job logs `gh not found`.** `gh` moved; rerun `install.sh`.
- **GitHub disabled a scheduled workflow for inactivity.** The local job turns `contract-heartbeat.yml` and `contract-upstream.yml` back on each time it writes the heartbeat: after each weekly check, and at most daily while waiting for a token.
- **The upstream workflow fails with a missing file.** openai/codex moved a model file: point `upstream/codex.lock.json` at the new path by hand.
