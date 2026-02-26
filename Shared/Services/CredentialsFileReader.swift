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

    func readToken() -> String? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    func tokenExists() -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}
