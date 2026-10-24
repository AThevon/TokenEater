import Foundation

/// A fixed set of accounts for code that only reads `AccountsStoreProtocol`.
@MainActor
final class MockAccountsStore: AccountsStoreProtocol {
    var records: [ClaudeAccountRecord]
    var stores: [AccountID: UsageStore]

    init(records: [ClaudeAccountRecord] = [.defaultMain()], stores: [AccountID: UsageStore] = [:]) {
        self.records = records
        self.stores = stores
    }

    var activeAccountIDs: [AccountID] { records.filter { !$0.isPaused }.map(\.id) }
    var tracksMultipleAccounts: Bool { records.count >= 2 }
    var showsAccountMarkers: Bool { activeAccountIDs.count >= 2 }

    func record(for id: AccountID) -> ClaudeAccountRecord? {
        records.first { $0.id == id }
    }

    func usageStore(for id: AccountID) -> UsageStore? {
        stores[id]
    }
}
