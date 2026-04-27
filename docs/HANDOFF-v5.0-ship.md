# v5.0.0 ship handoff

Temporary file. Delete after `v5.0.0` is published on GitHub Releases.

State at handoff (2026-04-27 evening) -> the rc.1 build is unblocked code-side but Apple's notary service was saturated and refused to give a verdict (`status=In Progress` for 60+ min straight on a 4 MB DMG). Recommendation was to retry the next morning (US business hours) when their backend is less loaded.

The branch is `feat/apple-dev-migration`. The PR is #144.

---

## What's already done

- All Apple Dev migration code on the branch (PR #144)
- Local cert + provisioning installed on previous Mac
- 5 GitHub secrets in place: `APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` (`S7B8M9JYF4`)
- `release.yml` hardened: explicit polling instead of `notarytool --wait`, get-task-allow stripped, AppleScript applet re-signed with hardened runtime, codesign deep verify, spctl Gatekeeper assertion, prerelease tags skip Sparkle / appcast / brew cask publishing
- `project.yml` set to Automatic + `DEVELOPMENT_TEAM=S7B8M9JYF4` for local dev
- Site (`/Users/athevon/projects/tokeneater-site`) updated and pushed: new `/docs/coloring` page, refreshed `/docs/features` for v5.0, post-hero redesign in 3 acts (Features sticky scroll, SmartColor live demo, magnetic CTA Climax)
- Release notes drafted at `docs/release-notes-v5.0.0.md` in the repo (use this for the GitHub release body when v5.0.0 ships)

## What's NOT done yet

1. rc.1 has to actually finish notarization (last attempt timed out)
2. Manual smoke test of the rc.1 DMG on the new Mac
3. Bump `MARKETING_VERSION: "5.0.0-rc.1"` -> `"5.0.0"` for the final tag
4. Tag + push `v5.0.0`
5. Curate the GitHub release body using `docs/release-notes-v5.0.0.md`
6. Close GitHub issues fixed in this release (with @ mentions)
7. Update the homebrew-tokeneater repo (separate, drop the `postflight xattr -cr`)
8. Delete this handoff file

---

## Step 1 - Retrigger rc.1 from the new Mac

You need git access to push tags. The `feat/apple-dev-migration` branch is already on GitHub.

```bash
cd /path/to/TokenEater   # or fresh clone
git fetch origin
git checkout feat/apple-dev-migration
git pull
```

Then nuke the previous rc.1 tag + release and retag:

```bash
# Delete local tag, remote tag, and the GitHub release
git tag -d v5.0.0-rc.1 2>/dev/null
git push origin :refs/tags/v5.0.0-rc.1 2>/dev/null
gh release delete v5.0.0-rc.1 -y 2>/dev/null

# Retag the current HEAD of feat/apple-dev-migration
git tag v5.0.0-rc.1 HEAD
git push origin v5.0.0-rc.1
```

The release workflow will run automatically on the tag push.

Watch progress:

```bash
gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Expected timing on a healthy Apple notary day: build ~3 min, sign + DMG ~1 min, **notarize 5-15 min**, staple + spctl ~10s.

If it stays at `In Progress` for 60 min again, Apple is still saturated -> retry later in the day or the next morning.

---

## Step 2 - Smoke test the rc.1 DMG on the new Mac

Once the workflow shows green:

1. Download the DMG from `https://github.com/AThevon/TokenEater/releases/tag/v5.0.0-rc.1`
2. Open it -> drag TokenEater to Applications
3. Launch `/Applications/TokenEater.app` -> **expected: opens directly, no Gatekeeper prompt at all**
4. Onboarding shows up (fresh install)
5. Complete onboarding -> menu bar gauge appears -> popover opens -> dashboard with 3 spaces (Monitoring / History / Settings)
6. Optional but recommended: add the desktop widget, verify it shows usage

If something looks off, check `~/Library/Logs/TokenEater/` for crash logs.

If you want to test the **upgrade path from v4.x** instead of fresh install:
1. Install v4.12.2 first (`brew install --cask tokeneater` or DL the DMG from old releases)
2. Use it briefly (complete onboarding, pin a couple metrics, change theme)
3. Install v5.0.0-rc.1 on top -> verify settings carry over (no re-onboarding) and the v4 LaunchAgent helper is gone (`launchctl list | grep tokeneater` should be empty)

---

## Step 3 - Ship v5.0.0 final

Once rc.1 smoke test passes:

```bash
# Bump MARKETING_VERSION from "5.0.0-rc.1" to "5.0.0"
# Edit project.yml line 16 manually OR:
sed -i '' 's/MARKETING_VERSION: "5.0.0-rc.1"/MARKETING_VERSION: "5.0.0"/' project.yml

git add project.yml
git commit -m "bump: v5.0.0"
git push

# Merge PR #144 on GitHub UI (squash) -> this gets v5.0 onto main
# Then tag main:
git fetch origin main
git tag v5.0.0 origin/main
git push origin v5.0.0
```

The release workflow runs again, this time:
- DMG signed + notarized + stapled
- Sparkle EdDSA signature added to `docs/appcast.xml`
- `appcast.xml` committed back to main automatically
- homebrew-tokeneater cask bumped automatically (version + sha256)

---

## Step 4 - Curate the GitHub release body

The auto-generated notes will be too thin. Use the prepared release body:

```bash
# Pre-written release notes are at docs/release-notes-v5.0.0.md
# Pipe them to gh release edit:
gh release edit v5.0.0 --notes-file docs/release-notes-v5.0.0.md
```

Verify the release on https://github.com/AThevon/TokenEater/releases/tag/v5.0.0.

---

## Step 5 - Close issues with @ mentions

Issues fixed in v5.0 + their authors (handle):

- **#43** Add Launch at Login setting (no specific tagger needed)
- **#99** Context usage on watcher tile (`@MartySalade`)
- **#112** Always asked to give permissions (`@saajz-code`)
- **#145** Historical token usage graphs from local JSONL (`@dsayerdp`)
- **#151** Add link to GitHub Issues page in Settings (`@brokvolchansky`)
- **#152** Items in menubar disappear (`@brokvolchansky`) -> defensive fix, ask the reporter to confirm

Suggested closing comment template (English):

> v5.0.0 ships this fix - landed in [#144]. Thanks for the report @<author>! If you upgrade and the issue persists, please reopen with your macOS version and a fresh repro.

For #145 and #99 (feature requests):

> Shipped in v5.0.0 - see [the History feature](https://github.com/AThevon/TokenEater/blob/main/docs/release-notes-v5.0.0.md) / [the watcher context bar](...). Thanks @<author> for the suggestion!

For #152 specifically -> the fix is defensive (we addressed the most likely cause but couldn't reproduce locally). Ask the reporter to verify on v5.0.0:

> Hey @brokvolchansky, v5.0 ships a defensive fix that ensures the menu bar always falls back to the logo if the pinned metrics ever filter out to nothing. Could you confirm whether this resolves the issue on your end? If you still see the items disappearing after upgrade, please drop your macOS version + which pins you have active and we'll dig deeper.

---

## Step 6 - Homebrew cask cleanup (separate repo)

The `AThevon/homebrew-tokeneater` repo has a `postflight` block that strips the notarization ticket via `xattr -cr`. Since v5.0 is notarized + stapled, this block does more harm than good (strips the ticket, can flag the widget as malware on first launch).

Already cloned at `/Users/athevon/projects/homebrew-tokeneater` (per the previous Mac). On the new Mac, fresh clone:

```bash
gh repo clone AThevon/homebrew-tokeneater /tmp/cask
cd /tmp/cask
```

Edit `Casks/tokeneater.rb`:

```ruby
# REMOVE this block:
postflight do
  system_command "/usr/bin/xattr",
                 args: ["-cr", "#{appdir}/TokenEater.app"]
end

# UPDATE the zap section to clean v5.0 paths:
zap trash: [
  "~/Library/Application Support/com.tokeneater.shared",
  "~/Library/Application Support/com.claudeusagewidget.shared",
  "~/Library/Group Containers/S7B8M9JYF4.group.com.tokeneater",
  "~/Library/Preferences/com.tokeneater.app.plist",
  "~/Library/Preferences/com.tokeneater.app.widget.plist",
  "~/Library/Containers/com.tokeneater.app",
  "~/Library/Containers/com.tokeneater.app.widget",
  "~/Library/Containers/com.claudeusagewidget.widget",
]
```

Note the version + sha256 will get auto-bumped by the release workflow when v5.0.0 ships -> don't manually update those, just edit the `postflight` and `zap` blocks.

```bash
git add Casks/tokeneater.rb
git commit -m "chore: drop xattr postflight + update zap for v5.0"
git push
```

Brew users on `brew upgrade tokeneater` will pick up both changes (the cask version bump + the postflight removal) in one go.

---

## Step 7 - Delete this file

After v5.0.0 is published and validated:

```bash
git rm docs/HANDOFF-v5.0-ship.md
git commit -m "docs: drop v5.0 ship handoff"
git push
```

---

## If something goes wrong

| Symptom | Probable cause | Fix |
|---|---|---|
| rc.1 build fails at Notarize with "Invalid" | New entitlement or signing regression in a recent commit | Check the Apple log printed by the workflow (it auto-fetches on Invalid). Common culprits: get-task-allow back, missing hardened runtime on a new bundle, unsigned helper |
| rc.1 stuck at "In Progress" 60+ min | Apple notary saturated again | Wait, retry later in the day |
| Smoke test: Gatekeeper still blocks | Stapler didn't run or ticket got stripped | Re-download the DMG, don't use `xattr -cr` on it. Check the workflow's "Notarize + staple" step output for the staple validate result |
| Smoke test: app crashes on launch | Probably a code issue, not signing | Check `~/Library/Logs/DiagnosticReports/TokenEater*.crash` |
| Brew install: widget flagged as malware | Old cask postflight still in place | Update the cask repo first (Step 6), then `brew upgrade tokeneater` |

For deeper context, see:
- `docs/v5.0-post-cert-checklist.md` -> the full post-cert plan
- `docs/v5.0.1-followup.md` -> known gaps deferred to v5.0.1
- `docs/design/COLORING.md` -> Smart Color v2 reference
- `CLAUDE.md` -> build + nuke + install commands
