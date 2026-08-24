#!/bin/bash
# Bundled inside TokenEaterInstaller.app/Contents/Resources — read-only at runtime.
# $1 = shared directory path (e.g. ~/Library/Application Support/com.tokeneater.shared)
SHARED_DIR="$1"
DMG_PATH="$SHARED_DIR/TokenEater.dmg"

exec > "$SHARED_DIR/install.log" 2>&1
echo "=== TokenEater Installer ==="
echo "Date: $(date)"

REAL_USER=$(stat -f%Su /dev/console)
REAL_UID=$(id -u "$REAL_USER")

while pgrep -x -U "$REAL_UID" "TokenEater" > /dev/null 2>&1; do sleep 0.3; done
echo "App quit."

MOUNT=$(hdiutil attach "$DMG_PATH" -nobrowse | grep '/Volumes/' | head -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')
echo "Mount: $MOUNT"
[ -z "$MOUNT" ] && { echo "Mount failed"; exit 1; }

rm -rf /Applications/TokenEater.app
cp -R "$MOUNT/TokenEater.app" /Applications/
chown -R "$REAL_USER:staff" /Applications/TokenEater.app
hdiutil detach "$MOUNT" -quiet 2>/dev/null

echo "Install OK"
open /Applications/TokenEater.app
rm -f "$DMG_PATH"
