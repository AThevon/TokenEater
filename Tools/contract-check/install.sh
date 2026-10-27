#!/bin/bash
#
# Installs (or removes) the local half of the usage API contract check.
#
#   Tools/contract-check/install.sh               build, install and load the job
#   Tools/contract-check/install.sh --print-plist  print the launchd plist, change nothing
#   Tools/contract-check/install.sh --uninstall    unload the job and remove it
#
# The checker is compiled once into ~/Library/Application Support/
# TokenEaterContractCheck, so the job depends on no checkout and no branch.
# Run this again after pulling a change to Sources/.
#
# launchd starts jobs with PATH=/usr/bin:/bin:/usr/sbin:/sbin, which has no gh
# on a Nix or Homebrew setup. The gh found now is baked into the plist (GH_BIN)
# along with a full PATH.

set -euo pipefail

LABEL="dev.athevon.tokeneater.contract-check"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/Library/Application Support/TokenEaterContractCheck"
BIN="$APP_DIR/contract-check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/tokeneater-contract-check.log"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$APP_DIR"
  echo "Uninstalled $LABEL. The log is left at $LOG."
  exit 0
fi

# Keep the profile path (~/.nix-profile/bin/gh), not the store path it links
# to: the profile survives upgrades, the store path does not.
GH="$(command -v gh || true)"
if [[ -z "$GH" ]]; then
  echo "gh not found on PATH. Install it and run gh auth login first." >&2
  exit 1
fi
GH="$(cd "$(dirname "$GH")" && pwd)/$(basename "$GH")"

BUILD="$(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$HERE" diff --quiet HEAD -- . 2>/dev/null; then BUILD="$BUILD-dirty"; fi
JOB_PATH="$(dirname "$GH"):$HOME/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$JOB_PATH</string>
        <key>GH_BIN</key>
        <string>$GH</string>
        <key>HOME</key>
        <string>$HOME</string>
        <key>CONTRACT_CHECK_BUILD</key>
        <string>$BUILD</string>
    </dict>
    <!-- Every hour, and at load. The binary runs the real check once a week,
         at the first hour a usable token exists, and exits silently otherwise. -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>17</integer>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST
}

if [[ "${1:-}" == "--print-plist" ]]; then
  plist
  exit 0
fi

if ! "$GH" auth status >/dev/null 2>&1; then
  echo "gh is not logged in. Run gh auth login first." >&2
  exit 1
fi

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
echo "Compiling the checker..."
xcrun swiftc -O -swift-version 5 -o "$BIN.new" "$HERE"/Sources/*.swift
mv -f "$BIN.new" "$BIN"

plist > "$PLIST.new"
plutil -lint "$PLIST.new" >/dev/null
mv -f "$PLIST.new" "$PLIST"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"

echo "Installed $LABEL (build $BUILD)."
echo "  binary: $BIN"
echo "  gh:     $GH"
echo "  log:    $LOG"
echo "It ran once at load; follow it with: tail -f \"$LOG\""
