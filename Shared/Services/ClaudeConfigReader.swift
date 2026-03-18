import Foundation

final class ClaudeConfigReader: ClaudeConfigReaderProtocol, @unchecked Sendable {
    private let configPath: String

    init() {
        guard let pw = getpwuid(getuid()) else { configPath = ""; return }
        let home = String(cString: pw.pointee.pw_dir)
        configPath = home + "/Library/Application Support/Claude/config.json"
    }

    init(configPath: String) { self.configPath = configPath }

    func readEncryptedToken() -> String? {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encrypted = json["oauth:tokenCache"] as? String,
              !encrypted.isEmpty
        else { return nil }
        return encrypted
    }
}
