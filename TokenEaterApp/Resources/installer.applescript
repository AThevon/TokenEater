set sharedDir to do shell script "echo ~/Library/Application\\ Support/com.tokeneater.shared"
set scriptPath to POSIX path of (path to resource "te-update.sh")
-- Resolved here, unprivileged, so the script gets the account that actually
-- started the update rather than whoever owns the active console session.
set updateUser to short user name of (system info)
do shell script "bash " & quoted form of scriptPath & " " & quoted form of sharedDir & " " & quoted form of updateUser with administrator privileges
