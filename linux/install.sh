#!/usr/bin/env bash
# TokenEater — Linux installer
# Supports GNOME 42+ on Ubuntu 22.04+ / Fedora 38+
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/AThevon/TokenEater/main/linux/install.sh)
set -euo pipefail

REPO="AThevon/TokenEater"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"
GITHUB_RELEASES="https://github.com/${REPO}/releases/download"

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

command -v curl &>/dev/null || die "curl is required. Install: sudo apt install curl"
command -v tar  &>/dev/null || die "tar is required."

command -v notify-send &>/dev/null || \
    warn "notify-send not found — desktop notifications disabled. Install: sudo apt install libnotify-bin"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *) die "Unsupported architecture: ${ARCH}. Only x86_64 and aarch64 are supported." ;;
esac
info "Architecture: ${ARCH} (${ARCH_SUFFIX})"

# ── 2. Fetch latest release version ──────────────────────────────────────────
echo ""
echo "Fetching latest release..."
VERSION=$(curl -fsSL "$GITHUB_API" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
[[ -n "$VERSION" ]] || die "Could not determine latest release version."
info "Version: ${VERSION}"

BASE_URL="${GITHUB_RELEASES}/${VERSION}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── 3. Download assets ────────────────────────────────────────────────────────
echo ""
echo "Downloading assets..."

curl -fsSL --progress-bar \
    -o "$TMPDIR/tokeneater-daemon" \
    "${BASE_URL}/tokeneater-daemon-linux-${ARCH_SUFFIX}"
ok "Downloaded daemon binary"

curl -fsSL --progress-bar \
    -o "$TMPDIR/extras.tar.gz" \
    "${BASE_URL}/tokeneater-linux-extras.tar.gz"
ok "Downloaded extras (GNOME extension + service)"

tar -xzf "$TMPDIR/extras.tar.gz" -C "$TMPDIR"

# ── 4. Install daemon ─────────────────────────────────────────────────────────
echo ""
echo "Installing daemon..."
mkdir -p ~/.local/bin
install -m 755 "$TMPDIR/tokeneater-daemon" ~/.local/bin/tokeneater-daemon
ok "Daemon installed → ~/.local/bin/tokeneater-daemon"

# ── 5. Install GNOME extension ────────────────────────────────────────────────
echo ""
echo "Installing GNOME extension..."
EXT=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT"
cp -r "$TMPDIR/gnome-extension/." "$EXT/"
ok "Extension installed → $EXT"

# ── 6. Install D-Bus activation file ─────────────────────────────────────────
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

# ── 7. Install systemd service ────────────────────────────────────────────────
echo ""
echo "Installing systemd service..."
mkdir -p ~/.config/systemd/user
cp "$TMPDIR/tokeneater.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater.service
ok "systemd service enabled and started"

# ── 8. Enable GNOME extension ─────────────────────────────────────────────────
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

# ── 9. Verify ─────────────────────────────────────────────────────────────────
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
ok "TokenEater ${VERSION} installed successfully!"
echo ""
echo "  Daemon status : systemctl --user status tokeneater"
echo "  Live D-Bus    : gdbus call --session --dest io.tokeneater.Daemon \\"
echo "                    --object-path /io/tokeneater/Daemon \\"
echo "                    --method io.tokeneater.Daemon.GetState"
echo "  Uninstall     : bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/linux/install.sh) --uninstall"
echo ""
