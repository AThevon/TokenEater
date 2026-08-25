#!/bin/bash
#
# Runs as root, launched by installer.applescript with administrator privileges.
#
# Bundled inside TokenEaterInstaller.app/Contents/Resources. What actually
# protects this file is macOS refusing writes into a notarized app bundle sitting
# at the top level of /Applications, which is where both the installer below and
# the Homebrew cask put it. Writes there fail with EPERM even for the bundle's
# owner, so a process running as the user cannot swap this script out.
#
# It is NOT protected by the code signature seal at runtime, despite living in a
# sealed resource directory. Tampering does invalidate the seal, but macOS still
# launches the applet and still runs the modified script (measured, not assumed).
# An app running from somewhere unprotected therefore does not get this
# guarantee: ~/Applications, a subdirectory of /Applications, and unnotarized
# local builds are all writable. For those, the swap this script was written to
# prevent is still possible, and the only real answer is to install to
# /Applications from the notarized DMG.
#
# The rule for everything else this script touches: whatever arrives from the
# user-writable shared directory is untrusted and must be verified here, by the
# privileged process, at the moment it is used. A check performed earlier by the
# unprivileged app proves nothing, since the file can be swapped in between.
#
# $1 = shared directory path (e.g. ~/Library/Application Support/com.tokeneater.shared)
# $2 = short name of the user who started the update
SHARED_DIR="$1"
UPDATE_USER="$2"
DMG_PATH="$SHARED_DIR/TokenEater.dmg"

# This script runs as root, so the log must not live in the shared directory:
# that path is writable by any process running as the user, which could replace
# it with a symlink and turn this redirection into an arbitrary root-owned
# truncate-and-write. Part of the content is attacker-controlled too, since the
# mounted volume name is echoed below. /var/log is only writable by root.
LOG="/var/log/tokeneater-update.log"
exec > "$LOG" 2>&1
chmod 644 "$LOG" 2>/dev/null

# Earlier versions logged into the shared directory as root, leaving a
# root-owned file behind in the user's own directory. Clear it out on the way
# past. rm on a symlink removes the link, not its target, so this is safe here.
rm -f "$SHARED_DIR/install.log"
echo "=== TokenEater Installer ==="
echo "Date: $(date)"

# The user is passed in by the applet, which runs unprivileged as that very
# user. Deriving it here from /dev/console would instead name whoever owns the
# active console session, which under Fast User Switching is not necessarily the
# account that started the update: the wait loop would watch the wrong uid and
# the ownership fixup would hand the installed app to the wrong account.
if [ -z "$UPDATE_USER" ]; then echo "No user given"; exit 1; fi
UPDATE_UID=$(id -u "$UPDATE_USER" 2>/dev/null)
if [ -z "$UPDATE_UID" ]; then echo "Unknown user: $UPDATE_USER"; exit 1; fi

# Wait only for THIS user's instance to quit. An unscoped pgrep would also match
# other logged-in users' instances and stall the update until they quit too.
while pgrep -x -U "$UPDATE_UID" "TokenEater" > /dev/null 2>&1; do sleep 0.3; done
echo "App quit."

if [ ! -f "$DMG_PATH" ]; then echo "No DMG at $DMG_PATH"; exit 1; fi

# Mount at a path we choose, read-only. The previous code parsed hdiutil's
# output to find the mount point, but the volume name inside the DMG is
# attacker-controlled and could steer that parsing elsewhere. -mountpoint drops
# the parsing entirely, and -readonly keeps the volume from being mutated
# between the checks below and the copy.
MNT=$(mktemp -d /tmp/tokeneater-update.XXXXXX)
if [ -z "$MNT" ]; then echo "Cannot create mount point"; exit 1; fi
STAGE_DIR=""
cleanup() {
    hdiutil detach "$MNT" -quiet 2>/dev/null
    rmdir "$MNT" 2>/dev/null
    if [ -n "$STAGE_DIR" ]; then rm -rf "$STAGE_DIR"; fi
}
trap cleanup EXIT

if ! hdiutil attach "$DMG_PATH" -readonly -nobrowse -noverify -mountpoint "$MNT"; then
    echo "Mount failed"
    exit 1
fi
echo "Mounted at $MNT"

APP="$MNT/TokenEater.app"
if [ ! -d "$APP" ]; then echo "No TokenEater.app inside the DMG"; exit 1; fi

# The DMG sits in the user-writable shared directory, so the signature check the
# app ran before handing it over says nothing about the bytes we are installing:
# any process running as the user can swap the file in between. Verify the
# payload we actually mounted, here, in the privileged process.
#
# The requirement pins the Apple anchor and our Team ID, so a validly signed app
# from anyone else is rejected. Keep in sync with DEVELOPMENT_TEAM in project.yml.
if ! codesign --verify --deep --strict \
    -R '=anchor apple generic and certificate leaf[subject.OU] = "S7B8M9JYF4"' \
    "$APP"; then
    echo "Signature check failed, refusing to install"
    exit 1
fi
echo "Signature OK"

# Rejects a correctly signed but unnotarized bundle, i.e. one that did not come
# out of our release pipeline.
if ! spctl --assess --type execute "$APP"; then
    echo "Notarization check failed, refusing to install"
    exit 1
fi
echo "Notarization OK"

# A genuinely signed and notarized but older DMG passes every check above, so
# without this an attacker able to swap the file could force a downgrade to a
# release whose vulnerabilities they already know, and exploit those instead.
# Compare against what is installed rather than against an expected version
# handed to us through the shared directory, which would be just as swappable as
# the DMG itself.
NEW_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null)
if [ -z "$NEW_VERSION" ]; then
    echo "Cannot read the version inside the DMG, refusing to install"
    exit 1
fi
CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - \
    /Applications/TokenEater.app/Contents/Info.plist 2>/dev/null)
if [ -n "$CURRENT_VERSION" ]; then
    # sort -V puts the lower version first, so if that is the incoming one we are
    # being asked to go backwards.
    OLDEST=$(printf '%s\n%s\n' "$CURRENT_VERSION" "$NEW_VERSION" | sort -V | head -1)
    if [ "$NEW_VERSION" = "$CURRENT_VERSION" ] || [ "$OLDEST" = "$NEW_VERSION" ]; then
        echo "Refusing to install $NEW_VERSION over $CURRENT_VERSION"
        exit 1
    fi
    echo "Version OK ($CURRENT_VERSION -> $NEW_VERSION)"
else
    # Nothing installed at the canonical path to compare against (the running app
    # lives elsewhere). The signature and notarization gates above still hold, so
    # allow it rather than blocking a legitimate install.
    echo "Version OK ($NEW_VERSION, no installed copy to compare against)"
fi

# Stage inside /Applications so the final move is a rename on the same volume,
# and in a root-owned 0700 directory so the verified copy cannot be touched
# before it lands. A failed copy can then no longer leave the user with no app.
STAGE_DIR=$(mktemp -d /Applications/.tokeneater-update.XXXXXX)
if [ -z "$STAGE_DIR" ]; then echo "Cannot create staging directory"; exit 1; fi
if ! cp -R "$APP" "$STAGE_DIR/TokenEater.app"; then echo "Copy failed"; exit 1; fi
chown -R "$UPDATE_USER:staff" "$STAGE_DIR/TokenEater.app"
# No xattr -cr: notarized + stapled DMGs pass Gatekeeper without manual
# unquarantine, and stripping attributes would also remove the stapled ticket.
rm -rf /Applications/TokenEater.app
if ! mv "$STAGE_DIR/TokenEater.app" /Applications/TokenEater.app; then
    echo "Install failed"
    exit 1
fi

echo "Install OK"
# Relaunch as the user, not as root. A bare `open` from this privileged context
# can start the app outside the user's session, and an app running as root would
# then write its shared state and read the Keychain as root.
launchctl asuser "$UPDATE_UID" sudo -u "$UPDATE_USER" open /Applications/TokenEater.app
rm -f "$DMG_PATH"
