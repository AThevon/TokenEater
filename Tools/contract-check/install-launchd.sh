#!/bin/bash
#
# Installs (or removes) the daily launchd schedule for the usage-API contract
# checker. Paths are resolved from the current checkout, so this works the same
# on any machine you clone TokenEater onto.
#
#   ./install-launchd.sh              install + load the daily job (09:00)
#   ./install-launchd.sh --uninstall  stop + remove the job
#
# Logs land in ~/Library/Logs/tokeneater-contract-check.log.

set -euo pipefail

LABEL="dev.athevon.tokeneater.contract-check"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/tokeneater-contract-check.log"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled $LABEL."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/run.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF

# Reload cleanly whether or not a previous copy is registered.
launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"

echo "Installed $LABEL (daily at 09:00)."
echo "Plist: $PLIST"
echo "Logs:  $LOG"
echo "Run once now to test:  launchctl kickstart -k $DOMAIN/$LABEL"
