import Foundation

protocol KeychainHelperReaderProtocol: Sendable {
    /// Returns the most recent token synced by the helper, or nil if the helper
    /// has never run / is reporting an error / wrote an empty token.
    func readToken() -> String?

    /// Returns the last sync timestamp reported by the helper, or nil.
    func lastSyncAt() -> Date?

    /// Returns the last error reported by the helper, or nil if status is ok.
    func lastError() -> String?
}
