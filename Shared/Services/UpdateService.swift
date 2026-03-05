import Foundation
import Sparkle

final class UpdateService: NSObject, UpdateServiceProtocol {
    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func startUpdater() {
        do {
            try updater.start()
        } catch {
            print("[UpdateService] Failed to start Sparkle: \(error)")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }
}
