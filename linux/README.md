# TokenEater — Linux / GNOME

Monitor your Claude AI usage limits from the GNOME Shell status bar.

## Requirements

- Ubuntu 22.04+ / Fedora 38+ (GNOME 42+)
- Claude Code installed and authenticated (`claude /login`)
- Go 1.22+ (to build from source)
- `notify-send` — `sudo apt install libnotify-bin` (Debian/Ubuntu)

## Build & Install (from source)

```bash
# 1. Build daemon
cd linux/daemon
go build -o ~/.local/bin/tokeneater-daemon ./...

# 2. Install GNOME extension
EXT=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT"
cp -r linux/gnome-extension/. "$EXT/"

# 3. Install systemd user service
mkdir -p ~/.config/systemd/user
cp linux/tokeneater.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater

# 4. Enable extension
#    On X11:  gnome-extensions enable tokeneater-gnome@io.tokeneater
#    On Wayland: log out and log back in, then enable via GNOME Extensions app
```

## Verify

```bash
# Check daemon is running
systemctl --user status tokeneater

# Query state directly via D-Bus
gdbus call --session \
  --dest io.tokeneater.Daemon \
  --object-path /io/tokeneater/Daemon \
  --method io.tokeneater.Daemon.GetState
```

## Architecture

See `docs/plans/2026-02-23-linux-gnome-design.md` for the full design.

```
linux/
  daemon/              # Go daemon — core engine
  gnome-extension/     # GNOME Shell extension (GJS, GNOME 42+)
  tokeneater.service   # systemd user service
```

- **`daemon/`** — reads `~/.claude/.credentials.json`, calls the Anthropic API,
  exposes data via D-Bus (`io.tokeneater.Daemon`), sends `notify-send` alerts.
- **`gnome-extension/`** — GNOME Shell extension: subscribes to D-Bus signals,
  renders usage in the status bar (icon + session %), detailed popup on click.
- **`tokeneater.service`** — systemd user service, auto-starts with your session.

## Supported metrics

| Metric | Source |
|--------|--------|
| Session (5h) | `five_hour` bucket |
| Weekly — All | `seven_day` bucket |
| Weekly — Sonnet | `seven_day_sonnet` bucket |
| Pacing | computed from `seven_day` elapsed time |

## Notifications

Threshold transitions trigger a desktop notification via `notify-send`:

| Level | Threshold | Urgency |
|-------|-----------|---------|
| ⚠️ Warning | ≥ 60% | normal |
| 🔴 Critical | ≥ 85% | critical |
| 🟢 Recovery | back to < 60% | low |

## Future (not yet implemented)

- KDE Plasma widget — same daemon, QML UI
- XFCE panel plugin — same daemon
- `install.sh` + packaged releases (`.deb`, AUR)
- SOCKS5 proxy support in the daemon
