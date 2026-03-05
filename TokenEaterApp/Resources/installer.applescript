set sharedDir to do shell script "echo ~/Library/Application\\ Support/com.tokeneater.shared"
do shell script "bash '" & sharedDir & "/te-update.sh'" with administrator privileges
