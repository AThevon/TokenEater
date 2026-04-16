-- Reads a command written by the sandboxed main app to the shared dir and
-- runs it as a user-level (no admin) shell script. Because this applet is
-- a separate .app bundle launched via /usr/bin/open, its shell script runs
-- outside the main app's sandbox and can therefore invoke /bin/launchctl.
set sharedDir to do shell script "echo ~/Library/Application\\ Support/com.tokeneater.shared"
do shell script "bash '" & sharedDir & "/te-helper-cmd.sh'"
