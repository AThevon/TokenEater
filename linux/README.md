# TokenEater — Linux / GNOME

Monitor your Claude AI usage limits from the GNOME Shell status bar.

## Requirements

- Ubuntu 22.04+ / Fedora 38+ (GNOME 42+)
- Claude Code installed and authenticated (`claude /login`)
- `curl` and `tar` (pre-installed on all distros)
- `notify-send` — `sudo apt install libnotify-bin` (Debian/Ubuntu) — optional, for desktop notifications

## Install

No repo clone required. Run this one-liner:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AThevon/TokenEater/main/linux/install.sh)
```

The script downloads the pre-built daemon binary for your architecture (x86\_64 or aarch64), installs the GNOME extension, the systemd user service, and the D-Bus activation file.

**Uninstall:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AThevon/TokenEater/main/linux/install.sh) --uninstall
```

<details>
<summary>Build from source (advanced)</summary>

If you prefer to build the daemon yourself, clone the repo and run:

```bash
# 1. Build daemon
cd linux/daemon && go build -o ~/.local/bin/tokeneater-daemon ./...

# 2. Install GNOME extension
EXT=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT" && cp -r linux/gnome-extension/. "$EXT/"

# 3. Install D-Bus activation file
mkdir -p ~/.local/share/dbus-1/services
cat > ~/.local/share/dbus-1/services/io.tokeneater.Daemon.service <<EOF
[D-BUS Service]
Name=io.tokeneater.Daemon
Exec=$HOME/.local/bin/tokeneater-daemon
SystemdService=tokeneater.service
EOF

# 4. Install systemd user service
mkdir -p ~/.config/systemd/user
cp linux/tokeneater.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater

# 5. Enable extension
#    On X11:     gnome-extensions enable tokeneater-gnome@io.tokeneater
#    On Wayland: log out / log back in, then enable via GNOME Extensions app
```

Requires Go 1.22+.

</details>

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
- Packaged releases (`.deb`, AUR)
- SOCKS5 proxy support in the daemon

