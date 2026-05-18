# Contributing to TokenEater

Hey, thanks for thinking about contributing ! Bug reports, feature ideas, code PRs, all of it helps a ton

TokenEater is a side project so this guide is more "here's how things tend to work" than a strict ruleset

Couple of small things to know:

- Everything on GitHub (issues, PRs, commits, branches) should be in English
- For bigger features, opening an issue first is usually a good idea so we can sanity-check the scope before you spend time on it. For small fixes or obvious bugs, just go ahead

## Reporting bugs

Use the **Bug report** template, it'll walk you through it. The more info you give, the easier the bug is to track down. The most useful stuff:

- macOS version
- TokenEater version (in *Settings -> About* or the menu bar tooltip)
- Repro steps if you have them
- A screenshot or recording for anything visual
- Console logs from `Console.app` (filter by `TokenEater`) for anything mysterious

If you can't reproduce reliably that's fine, just say so

## Suggesting features

Use the **Feature request** template. Mostly I want to understand the *problem* you're trying to solve, more than a specific implementation. If you also have an idea for how you'd build it, great, but it's totally optional

## Contributing code

### Setup

See [`SETUP.md`](SETUP.md). TL;DR: macOS 14+, Xcode 16.4 (specifically, newer versions can surface Swift 6.1 bugs that don't repro locally, see [`CLAUDE.md`](CLAUDE.md) for details), and `brew install xcodegen`

### Workflow

1. Fork the repo and clone your fork
2. Create a branch off `main`. Branch names are flexible, something like `feat/short-description` or `fix/short-description` works great
3. Code
4. Run the tests (see below), and try a manual build if you touched anything visual
5. Open a PR

If you're not sure about something, don't stress, I'd rather give feedback in a PR than have you spend an hour worrying about getting things perfect

### A few things worth knowing about the code

- Architecture is MV + Repository pattern with `ObservableObject` + `@Published`, there's a quick map in [`README.md`](README.md)
- A few hard-earned SwiftUI rules, the big ones:
  - **Don't use `@Observable`** (Swift Observation framework). The whole codebase uses `ObservableObject` + `@Published`. There's a Release-only freeze bug under Swift 6.1.x that's invisible in Debug
  - **No `@StateObject` in the `App` struct**, use `private let store = Store()` instead
  - **No bindings to computed properties** or `Binding(get:set:)`, they cause infinite loops
  - Full list and reasoning in [`CLAUDE.md`](CLAUDE.md)

### Commits

[Conventional Commits](https://www.conventionalcommits.org/) format is preferred (`feat:`, `fix:`, `chore:`, `docs:`, etc) since it makes generating changelogs easier later. Don't sweat it too much tho, if you mess up a commit message I can fix it on merge

Examples:

```
feat: add keyboard shortcut to toggle agent watchers
fix: refresh slider hidden under popover edge
chore: bump Sparkle to 2.6.4
```

### Tests

For changes in `Shared/` (stores, services, helpers), please run the unit tests:

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test
```

For SwiftUI or widget changes, manual testing matters more, build a Release version and try it. The *Build + Nuke + Install* one-liner in [`CLAUDE.md`](CLAUDE.md) is what I use locally

> **External contributors**: that one-liner hardcodes my Apple Developer Team ID (`DEVELOPMENT_TEAM=S7B8M9JYF4`), so it won't work on your machine as-is. Two options:
>
> - Skip signing entirely with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` (same flags as the test command above). Builds fine, but macOS Gatekeeper will block the first launch, just right-click -> Open the first time
> - Use your own free Personal Team: replace `DEVELOPMENT_TEAM=S7B8M9JYF4` with your own team ID (find it in Xcode > Settings > Accounts)
>
> If you can't build a Release version at all, that's OK too. Push your changes, mention it in the PR, and I'll do the visual validation on my side before merging

CI runs the tests automatically on PRs so you'll see if anything broke

## Questions

- General questions or ideas in progress: [GitHub Discussions](https://github.com/AThevon/TokenEater/discussions)
- Security issues: please email me directly at [adrien.thevon@pictarine.com](mailto:adrien.thevon@pictarine.com) rather than opening a public issue

That's it, thanks for being here 🤘
