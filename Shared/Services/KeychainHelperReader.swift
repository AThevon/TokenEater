import Foundation

final class KeychainHelperReader: KeychainHelperReaderProtocol, @unchecked Sendable {
    private let filePath: String

    convenience init() {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        self.init(
            filePath: "\(home)/Library/Application Support/com.tokeneater.shared/keychain-token.json"
        )
    }

    init(filePath: String) {
        self.filePath = filePath
    }

    func readToken() -> String? {
        guard let payload = readPayload(),
              payload["status"] as? String == "ok",
              let token = payload["token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    func lastSyncAt() -> Date? {
        guard let payload = readPayload(),
              let raw = payload["lastSyncAt"] as? String else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: raw)
    }

    func lastError() -> String? {
        guard let payload = readPayload(),
              let error = payload["error"] as? String,
              !error.isEmpty else {
            return nil
        }
        return error
    }

    private func readPayload() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
