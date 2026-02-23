# TokenEater Linux — Design Document
_Date: 2026-02-23_

## Context

TokenEater is a native macOS widget + menu bar app that displays Claude (Anthropic) usage limits in real-time. This document describes the design of the Linux port, initially targeting Ubuntu with GNOME Shell, with a multi-distro architecture in mind.

## Goals

- Display Claude usage (session 5h, weekly, Sonnet, pacing) in the GNOME Shell top bar
- Send desktop notifications on usage threshold transitions (60% / 85% / reset)
- Lay the groundwork for other desktop environments (KDE Plasma, XFCE, etc.) without duplicating core logic

## Non-Goals (for now)

- CI/CD and GitHub Releases for Linux — deferred
- KDE Plasma, XFCE, or other DE plugins — architecture supports them, but not implemented yet
- SOCKS5 proxy support — can be added later to the daemon
- Localization — English only for the first version

## Architecture

```
linux/
  daemon/              # Go service — core engine
    main.go            # Entry point, refresh loop (5 min)
    api.go             # GET https://api.anthropic.com/api/oauth/usage
    token.go           # Read ~/.claude/.credentials.json → accessToken
    pacing.go          # Port of PacingCalculator.swift
    notifications.go   # Threshold logic + notify-send via os/exec
    dbus.go            # D-Bus server (io.tokeneater.Daemon)

  gnome-extension/     # GNOME Shell extension (GJS)
    metadata.json      # Extension metadata (UUID, GNOME version range)
    extension.js       # Lifecycle (enable/disable)
    panel.js           # PanelMenu.Button — icon + session % in top bar
    popup.js           # PopupMenu — detailed view with progress bars
    dbus.js            # Gio.DBusProxy client
    stylesheet.css     # Colors (green/orange/red) and layout
```

## Component Details

### Daemon (Go)

**Token reading**
- Path: `~/.claude/.credentials.json`
- JSON structure: `{ claudeAiOauth: { accessToken: "..." } }`
- File is re-read on each refresh cycle to pick up automatic token refreshes from Claude Code

**API call**
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
```
Response buckets: `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_oauth_apps`, `seven_day_opus`.
Each bucket: `{ utilization: 0-100, resets_at: "ISO8601" }`.

**Pacing calculation** (port of `PacingCalculator.swift`)
- Uses `seven_day` bucket
- `elapsed = (now - (resets_at - 7d)) / 7d`
- `delta = utilization - elapsed * 100`
- Zones: chill (delta < -10), onTrack (-10 ≤ delta ≤ 10), hot (delta > 10)

**Notifications** (port of `UsageNotificationManager.swift`)
- Thresholds: green < 60%, orange 60-84%, red ≥ 85%
- Only notifies on level transitions (state persisted in `~/.cache/tokeneater/state.json`)
- Uses `notify-send` via `os/exec` — universally available on Linux desktop systems
- Metrics checked: session (5h), weekly (7d), Sonnet

**D-Bus interface: `io.tokeneater.Daemon`**
- Object path: `/io/tokeneater/Daemon`
- Session bus (not system bus)
- Properties:
  - `State` (string): JSON payload with all metrics
- Signals:
  - `StateChanged(state string)`: emitted after each successful fetch
- Methods:
  - `Refresh()`: triggers an immediate fetch cycle

**State JSON payload**
```json
{
  "fiveHour":   { "utilization": 67.0, "resetsAt": "2026-02-23T18:00:00Z" },
  "sevenDay":   { "utilization": 28.0, "resetsAt": "2026-02-25T12:00:00Z" },
  "sevenDaySonnet": { "utilization": 42.0, "resetsAt": "2026-02-25T12:00:00Z" },
  "pacing": { "delta": 12.0, "zone": "hot", "expectedUsage": 55.0 },
  "fetchedAt": "2026-02-23T14:32:00Z",
  "error": null
}
```

**Lifecycle**
- Installed as a systemd user service: `~/.config/systemd/user/tokeneater.service`
- Refresh loop: every 5 minutes
- Graceful shutdown on SIGTERM

### GNOME Extension (GJS)

**Top bar indicator**
- `PanelMenu.Button` in the status area (right side, next to network/clock)
- Label: icon + session percentage, e.g. `◉ 67%`
- Label color: green (#57c758) < 60%, orange (#f5a623) 60-84%, red (#e74c3c) ≥ 85%
- Subscribes to D-Bus `StateChanged` signal for reactive updates

**Popup menu (click on indicator)**
```
┌─────────────────────────────────┐
│  ◉ TokenEater                   │
├─────────────────────────────────┤
│  Session (5h)                   │
│  ████████████░░░░  67%          │
│  Resets in 2h 14m               │
│                                 │
│  Weekly — All                   │
│  ████░░░░░░░░░░░░  28%          │
│                                 │
│  Weekly — Sonnet                │
│  ██████░░░░░░░░░░  42%          │
│                                 │
│  Pacing: 🔥 +12% ahead          │
├─────────────────────────────────┤
│  [Refresh]      Last: 14:32     │
└─────────────────────────────────┘
```

**Error states**
- Token not found: "Claude Code not found — run `claude /login`"
- Daemon not running: "TokenEater service not running" with a [Start] button
- API error: last known state shown greyed out + timestamp

**D-Bus client startup**
- On extension enable, connects to `io.tokeneater.Daemon`
- If daemon absent, retries every 30 seconds
- Reads `State` property on connect, then listens for `StateChanged` signals

## Data Flow

```
Claude Code
  └── ~/.claude/.credentials.json (token)
        │
        ▼
tokeneater-daemon (Go, every 5 min)
  ├── GET api.anthropic.com/api/oauth/usage
  ├── Compute pacing
  ├── Check thresholds → notify-send (system notifications)
  └── Emit D-Bus StateChanged signal
        │
        ▼
GNOME extension (GJS)
  ├── Update top bar label + color
  └── Update popup menu on open
```

## Installation (manual, for development)

```bash
# Build daemon
cd linux/daemon && go build -o ~/.local/bin/tokeneater-daemon .

# Install systemd user service
cp linux/tokeneater.service ~/.config/systemd/user/
systemctl --user enable --now tokeneater

# Install GNOME extension
cp -r linux/gnome-extension/ \
  ~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater/
gnome-extensions enable tokeneater-gnome@io.tokeneater
```

## File Layout in Repo

```
linux/                           # All Linux-specific code
  daemon/                        # Go daemon
  gnome-extension/               # GNOME Shell extension
  tokeneater.service             # systemd unit template
  README.md                      # Linux-specific install instructions
```

The macOS code (`ClaudeUsageApp/`, `ClaudeUsageWidget/`, `Shared/`) is untouched.

## Future Extensions (not in scope now)

- KDE Plasma widget (QML) — same daemon, different UI adapter
- XFCE panel plugin — same daemon
- SOCKS5 proxy support in the daemon
- `install.sh` + packaged releases (deb, rpm, AUR)
- CI/CD on GitHub Actions for Linux binaries
