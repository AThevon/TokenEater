import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class UpdateStore {
    var updateAvailable = false
    var latestVersion: String?
    var releaseNotes: String?
    var releaseURL: URL?
    var isChecking = false
    var isUpdating = false
    var updateError: String?
    var showUpdateModal = false

    private let service: UpdateServiceProtocol
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "skippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "skippedVersion") }
    }

    private var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    init(service: UpdateServiceProtocol = UpdateService()) {
        self.service = service
    }

    func checkForUpdate(userInitiated: Bool = false) async {
        if !userInitiated, let last = lastCheckDate, Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }

        isChecking = true
        updateError = nil
        defer { isChecking = false }

        do {
            guard let info = try await service.checkForUpdate() else {
                updateAvailable = false
                lastCheckDate = Date()
                return
            }

            latestVersion = info.version
            releaseNotes = info.releaseNotes
            releaseURL = info.releaseURL
            updateAvailable = true
            lastCheckDate = Date()

            if userInitiated || skippedVersion != info.version {
                showUpdateModal = true
            }
        } catch {
            if userInitiated {
                updateError = error.localizedDescription
            }
        }
    }

    func performUpdate() {
        isUpdating = true
        updateError = nil
        do {
            try service.launchBrewUpdate()
            showUpdateModal = false
            #if canImport(AppKit)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
            #endif
        } catch {
            updateError = error.localizedDescription
            isUpdating = false
        }
    }

    func skipCurrentUpdate() {
        skippedVersion = latestVersion
        showUpdateModal = false
    }

    func dismissUpdate() {
        showUpdateModal = false
    }

    func startAutoCheck() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.checkForUpdate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                guard let self else { return }
                await self.checkForUpdate()
            }
        }
    }
}
