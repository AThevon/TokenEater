# v5.0.0 autonomous execution prompt

Paste the block below into a fresh Claude Code session launched at the root of the main worktree on the Mac. The agent will then execute the entire release plan end-to-end, creating worktrees, implementing each PR, running tests, pushing, opening PRs, and merging when green - stopping only at explicit checkpoints that require human input.

---

## Prompt to paste into Claude Code

```
You are executing the TokenEater v5.0.0 mega release plan. The full plan is in docs/superpowers/plans/2026-04-16-v5-mega-release.md. The Apple Developer Program migration plan (for context on why the Keychain helper in PR 4 is transitional) is in docs/APPLE_DEV_MIGRATION.md.

## Your authorization

You are fully authorized to, for each PR in the plan:
- Create git worktrees in a sibling directory (e.g. ../te-pr-127, ../te-pr-129, etc.)
- Commit, push to feature branches on origin
- Open pull requests via `gh pr create`
- Trigger CI workflows via `gh workflow run`
- Merge the PR via `gh pr merge` ONCE ALL of these are true:
  (a) CI is green on the PR
  (b) Local Release build with Xcode 16.4 succeeds
  (c) All unit tests pass
  (d) For PRs 1-4: no UI-visual changes that require human validation
  (e) For PR 5 (reset-time UX) and the PR 126 rebase: you have paused and asked the human for visual validation, and received confirmation

You are NOT authorized to:
- Create the final v5.0.0 tag / release (human does this after the final iso-prod validation)
- Bump MARKETING_VERSION in project.yml to 5.0.0 without explicit human confirmation
- Force-push, rebase main, or any destructive git operation on main
- Bypass pre-commit hooks (--no-verify), bypass signing, or bypass code signing requirements
- Modify repository secrets or GitHub Actions workflow permissions

## Execution order (strict)

You will execute in this order, one PR at a time, merging each before starting the next to avoid rebase churn:

1. PR 1 - Sparkle EdDSA signature verification (#127)
2. PR 2 - Session Monitor perf optimization (#129)
3. PR 3 - Rebase and merge external PR #126 (per-bucket pacing, author: Humboldt94)
4. PR 4 - Keychain helper LaunchAgent (#128)
5. PR 5 - Reset time display format + color customization (#130)

Each PR is described in detail in docs/superpowers/plans/2026-04-16-v5-mega-release.md sections "PR 1" through "PR 5". Read the corresponding section in full before starting each PR.

## Setup (do this first, before any PR)

1. Confirm you are in the main worktree, on branch `main`, with a clean status.
2. `git fetch origin main && git status` - confirm up to date.
3. `xcodebuild -version` - confirm Xcode 16.4 is available. If not, `export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer` and re-check. If still not, stop and ask the human to install it.
4. `gh auth status` - confirm GitHub CLI is authenticated.
5. `ls ..` - verify the parent directory exists and is writable; this is where worktrees will live.

## Per-PR flow (apply to each of PR 1 through PR 5)

For PR N:

1. Read the "PR N" section of the plan in full.
2. Create a worktree: `git -C <main worktree> worktree add -b <branch-name> ../te-pr-<n> main`
3. `cd ../te-pr-<n>`
4. Regenerate xcodeproj: `xcodegen generate`
5. Implement each task in the PR section, using TDD where tests are specified (write failing test, verify it fails, implement, verify it passes, commit).
6. Between tasks, run the full unit test suite: `xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test`. All tests must pass.
7. After all tasks complete, build Release with Xcode 16.4:
   ```
   export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
   DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2)
   plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null || true
   xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build
   ```
   A Release build failure is a blocker. Swift 6.1.x has known @Observable issues in Release that are invisible in Debug. If a Release build fails, halt and report.
8. Commit with the exact commit message template from the plan section (the one with `Co-authored-by:` lines).
9. Push: `git push -u origin <branch-name>`
10. Create the PR: `gh pr create --title "..." --body "..."` using the template from the plan.
11. Trigger CI if it doesn't auto-trigger: `gh workflow run ci.yml --ref <branch-name>`
12. Poll CI status every 60 seconds until complete: `gh pr checks <pr-number>`. Do NOT busy-loop - use `sleep 60` between polls.
13. If CI is green AND the PR is in PR 1-4: `gh pr merge <pr-number> --squash --delete-branch`. Then `cd` back to the main worktree and `git pull origin main`.
14. If the PR is PR 5 OR the PR 126 rebase: pause, report what you've built, ask the human to review visually in GitHub UI and merge when satisfied. Wait for human confirmation before proceeding.

## Explicit human-input checkpoints (STOP and ask the human)

These are the only moments you MUST pause for human input:

### Checkpoint A - Start of PR 1 (Sparkle EdDSA)

Task 1.1 of the plan requires the Sparkle EdDSA public key. Before writing any code for PR 1, ask the human:

> "For PR 127 Task 1.1 I need the Sparkle EdDSA public key to embed in the bundle. You have three options: (1) paste the base64 public key string here if you have it saved locally, (2) derive it from the SPARKLE_PRIVATE_KEY GitHub secret using `echo "$SPARKLE_PRIVATE_KEY" | /tmp/bin/generate_keys -p` (you'll need to fetch the secret via `gh secret list` / copy-paste), or (3) regenerate a fresh keypair which invalidates past release signatures (acceptable because none are currently verified). Which path do you want?"

Wait for the human's answer before continuing.

### Checkpoint B - PR 4 Task 4.4 (helper install mechanism)

The plan Task 4.4 anticipates that `Process()` invoking `/bin/launchctl` from the sandboxed main app may be blocked by sandbox rules. If you hit that blocker:

> "The main app cannot spawn launchctl directly from inside the sandbox. Plan B from the release plan is to reuse the TokenEaterInstaller.app AppleScript pattern (same approach as the auto-update install flow, which requires a one-time admin prompt). I propose to implement it that way. Confirm or tell me to take a different approach."

Wait for human confirmation before implementing the fallback.

### Checkpoint C - PR 3 (external PR 126 rebase) conflicts

`gh pr checkout 126 && git rebase origin/main` may produce conflicts. If conflicts arise in non-trivial code paths (Swift logic, not just line-number shifts in Localizable.strings), pause and ask:

> "Rebasing PR 126 on updated main produced conflicts in [files]. Specifically [summary]. Do you want me to: (1) resolve them myself and continue, (2) open a PR asking Humboldt94 to rebase, or (3) cherry-pick the commits into a fresh branch with my own authorship + Humboldt94 as co-author?"

### Checkpoint D - Before visual-validation merge (PR 3 and PR 5)

After pushing PR 3 (per-bucket pacing) and PR 5 (reset time UX) and confirming CI is green, you will NOT auto-merge. Post a comment on the PR body or report in chat:

> "PR #X is ready for human visual validation. Local Release build succeeded and all tests pass, but the changes affect menu bar rendering / dashboard UI which I cannot validate visually. Please install the build (see attached command output) and confirm visuals, then merge on GitHub. I will resume with the next PR once you confirm."

### Checkpoint E - After all 5 PRs merged, before release tag

Once all 5 PRs are merged into main:

1. `cd` to main worktree, `git pull origin main`
2. Report: "All 5 PRs are merged into main. Next step is the iso-prod validation. I'm triggering test-build.yml now."
3. Trigger: `gh workflow run test-build.yml -f branch=main`
4. Poll until complete (may take 10-15 minutes). Do not spam-poll - use 90-second intervals.
5. Download the DMG: `gh run download <run-id> -n TokenEater-test -D /tmp/tokeneater-test/`
6. STOP and ask the human:

> "iso-prod DMG is ready at /tmp/tokeneater-test/TokenEater.dmg. Please:
>   (1) Run the mega-nuke cleanup from CLAUDE.md (full version, not the standard nuke)
>   (2) Install the DMG manually (mount, copy, xattr -cr, lsregister, launch)
>   (3) Validate end-to-end: menu bar rendering, widget, session monitor, helper install flow, auto-update not broken
>   (4) Tell me GO when happy, or report what to fix"

Wait for human GO.

### Checkpoint F - Final release

Once human says GO:

1. Bump `MARKETING_VERSION` in project.yml from current (probably 4.9.3) to `5.0.0`. `xcodegen generate` to propagate.
2. Commit: `chore: bump version to v5.0.0`
3. Push to main: `git push origin main`
4. STOP and ask the human to create the tag themselves:

> "Version bumped to 5.0.0 and pushed to main. I will not create the final tag myself. Please run:
>   git tag v5.0.0
>   git push origin v5.0.0
> This triggers release.yml which builds the signed DMG, updates appcast, and bumps the Homebrew cask. I'll stay idle unless you need me to help with a release.yml failure."

## Rules from CLAUDE.md you must respect

- No `@Observable`, `@Bindable`, or `@Environment(Store.self)`. Use `ObservableObject + @Published + @EnvironmentObject`. See the "Règles SwiftUI" section of CLAUDE.md for the full list of SwiftUI banned patterns.
- All commits and PR bodies in English. Conversation with the human in French (but that's the user's choice; stay on the language the user uses).
- No em dash (-) in commits, code, or prose. Use a hyphen (-) or rephrase.
- No `git checkout main` or `git switch main`. To sync with main, use `git fetch origin main` + `git merge origin/main` or `git rebase origin/main` from the current branch.
- Never commit Co-Authored-By: Claude lines unless the user explicitly asks (the user's CLAUDE.md is explicit on this). Co-author the GitHub reporter of each issue as specified in the plan, but not Claude.
- For tests: Swift Testing framework (import Testing, @Test, #expect), mocks in TokenEaterTests/Mocks/, fixtures in TokenEaterTests/Fixtures/, @MainActor on suites touching stores, .serialized on suites touching UserDefaults.
- When creating commits, use HEREDOC for multi-line messages: `git commit -m "$(cat <<'EOF' ... EOF )"`.

## Reporting format

Between PRs, give a one-paragraph status update: which PR just merged, any notable decisions made, what's next. Don't re-summarize content the human can read in the diff.

At each checkpoint (A through F), state clearly which checkpoint you're at and what you need from the human.

If you hit an unexpected blocker not covered by checkpoints A-E, describe the situation and propose 2-3 options. Don't guess - ask.

## Go

Start with the setup steps. Once setup is verified, begin PR 1 by reading its section in the plan and then asking about the Sparkle public key (Checkpoint A). Do not skip Checkpoint A.
```

---

## Notes for the human

- Keep this Claude Code session in a terminal tab where you can glance at it periodically. The agent will pause at the checkpoints above.
- The agent will create worktrees at `../te-pr-<n>/`. You can `cd` into them and inspect state at any time.
- If the agent produces a git or network error it cannot resolve, it will surface it rather than retry destructively.
- Total wall time estimate: 4-8 hours of agent work + your checkpoint responses + iso-prod validation.
- All PRs will be reviewable on GitHub as they're created. You don't have to wait until the end to see progress.
