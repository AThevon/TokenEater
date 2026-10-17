import Combine
import SwiftUI

/// Lets one view follow the `UsageStore` of every running added Claude
/// account.
///
/// The added stores are deliberately not relayed through `AccountsStore`'s
/// own `objectWillChange` (every view observing it would repaint on every
/// refresh of any account). A view that reads several of them at once, such
/// as the popover grid deciding which cells have data, owns one of these as
/// a `@StateObject` and re-renders when any of the stores it tracks changes.
/// Views that read a single account's store receive it as an
/// `@ObservedObject` or through the environment instead.
@MainActor
final class UsageStoresObserver: ObservableObject {
    private var tracked: [ObjectIdentifier] = []
    private var subscriptions: [AnyCancellable] = []

    /// Follows exactly these stores from now on. Calling it again with the
    /// same stores changes nothing, so it can run on every appearance.
    func track(_ stores: [UsageStore]) {
        let ids = stores.map(ObjectIdentifier.init)
        guard ids != tracked else { return }
        tracked = ids
        subscriptions = stores.map { store in
            store.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

extension View {
    /// Points `observer` at the running added accounts' stores when the
    /// view appears and whenever the account list changes. The view owns
    /// `observer` as a `@StateObject`, so a refresh of any of those stores
    /// re-renders it.
    func followingAccountStores(
        _ observer: UsageStoresObserver,
        accounts: AccountsStore,
        accountList: [ClaudeAccountSummary]
    ) -> some View {
        onAppear { observer.track(accounts.runningExtraStores) }
            .onChange(of: accountList) { _, _ in observer.track(accounts.runningExtraStores) }
    }
}

extension AccountsStore {
    /// The stores of the running added accounts, in display order. The main
    /// account's store is left out: the views hold it in their environment.
    var runningExtraStores: [UsageStore] {
        activeAccountIDs.filter { !$0.isMain }.compactMap { usageStore(for: $0) }
    }
}
