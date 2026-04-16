import Foundation

enum HelperStatus: Equatable {
    case notInstalled
    case installed(lastSyncAt: Date?, lastError: String?)
    case binaryMissing
    case error(String)
}

enum HelperError: LocalizedError {
    case templateMissing
    case binaryMissing
    case launchctlFailed(Int32)
    case appleScriptFailed(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .templateMissing: return "Helper plist template is missing from the app bundle."
        case .binaryMissing: return "Helper binary is missing from the app bundle."
        case .launchctlFailed(let code): return "launchctl exited with status \(code)."
        case .appleScriptFailed(let code): return "AppleScript installer failed with code \(code)."
        case .writeFailed(let detail): return "Could not write LaunchAgent plist: \(detail)."
        }
    }
}

protocol HelperManagerProtocol: Sendable {
    func currentStatus() -> HelperStatus
    func install(syncInterval: TimeInterval) throws
    func uninstall() throws
    func forceSync() throws
}
