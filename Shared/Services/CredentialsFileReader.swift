import Foundation

final class CredentialsFileReader: CredentialsFileReaderProtocol, @unchecked Sendable {

    private let filePath: String

    init() {
        guard let pw = getpwuid(getuid()) else {
            filePath = ""
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        filePath = home + "/.claude/.credentials.json"
    }

    init(filePath: String) {
        self.filePath = filePath
    }

    func readCredential() -> ClaudeCredential? {
        guard let data = FileManager.default.contents(atPath: filePath) else { return nil }
        return ClaudeCredential.parse(data)
    }

    func tokenExists() -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}
