#!/usr/bin/env bash
# TokenEater — Linux install script
# Supports GNOME 42+ on Ubuntu 22.04+ / Fedora 38+
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Uninstalling TokenEater..."
    systemctl --user disable --now tokeneater.service 2>/dev/null || true
    rm -f ~/.local/bin/tokeneater-daemon
    rm -f ~/.config/systemd/user/tokeneater.service
    rm -f ~/.local/share/dbus-1/services/io.tokeneater.Daemon.service
    rm -rf ~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
    systemctl --user daemon-reload
    gnome-extensions disable tokeneater-gnome@io.tokeneater 2>/dev/null || true
    ok "TokenEater uninstalled."
    exit 0
fi

echo ""
echo "TokenEater — Linux installer"
echo "────────────────────────────"
echo ""

# ── 1. Checks ─────────────────────────────────────────────────────────────────
echo "Checking requirements..."

command -v go &>/dev/null || die "Go is not installed. Install from https://go.dev/dl/"
info "Go $(go version | awk '{print $3}')"

command -v notify-send &>/dev/null || \
    warn "notify-send not found — desktop notifications disabled. Install: sudo apt install libnotify-bin"

# ── 2. Build daemon ───────────────────────────────────────────────────────────
echo ""
echo "Building daemon..."
mkdir -p ~/.local/bin
(cd "$SCRIPT_DIR/daemon" && go build -o ~/.local/bin/tokeneater-daemon ./...)
ok "Daemon built → ~/.local/bin/tokeneater-daemon"

# ── 3. Install GNOME extension ────────────────────────────────────────────────
echo ""
echo "Installing GNOME extension..."
EXT=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT"
cp -r "$SCRIPT_DIR/gnome-extension/." "$EXT/"
ok "Extension installed → $EXT"

# ── 4. Install D-Bus activation file ─────────────────────────────────────────
echo ""
echo "Installing D-Bus activation file..."
mkdir -p ~/.local/share/dbus-1/services
cat > ~/.local/share/dbus-1/services/io.tokeneater.Daemon.service <<EOF
[D-BUS Service]
Name=io.tokeneater.Daemon
Exec=${HOME}/.local/bin/tokeneater-daemon
SystemdService=tokeneater.service
EOF
ok "D-Bus activation file installed"

# ── 5. Install systemd service ────────────────────────────────────────────────
echo ""
echo "Installing systemd service..."
mkdir -p ~/.config/systemd/user
cp "$SCRIPT_DIR/tokeneater.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater.service
ok "systemd service enabled and started"

# ── 6. Enable GNOME extension ─────────────────────────────────────────────────
echo ""
echo "Enabling GNOME extension..."
if command -v gnome-extensions &>/dev/null; then
    if gnome-extensions enable tokeneater-gnome@io.tokeneater 2>/dev/null; then
        ok "Extension enabled"
    else
        warn "Could not auto-enable (Wayland). Log out and back in, then enable via Extensions app."
    fi
else
    warn "gnome-extensions not found. Enable via Extensions app after relogging."
fi

# ── 7. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "Verifying D-Bus connection..."
sleep 2
if gdbus call --session \
        --dest io.tokeneater.Daemon \
        --object-path /io/tokeneater/Daemon \
        --method io.tokeneater.Daemon.GetState &>/dev/null; then
    ok "Daemon responding on D-Bus"
else
    warn "Daemon not yet on D-Bus — it may still be starting. Check: systemctl --user status tokeneater"
fi

echo ""
echo "────────────────────────────"
ok "TokenEater installed successfully!"
echo ""
echo "  Daemon status : systemctl --user status tokeneater"
echo "  Live D-Bus    : gdbus call --session --dest io.tokeneater.Daemon \\"
echo "                    --object-path /io/tokeneater/Daemon \\"
echo "                    --method io.tokeneater.Daemon.GetState"
echo "  Uninstall     : bash linux/install.sh --uninstall"
echo ""
