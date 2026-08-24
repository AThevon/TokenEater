set sharedDir to do shell script "echo ~/Library/Application\\ Support/com.tokeneater.shared"
set scriptPath to POSIX path of (path to resource "te-update.sh")
do shell script "bash " & quoted form of scriptPath & " " & quoted form of sharedDir with administrator privileges
