import Foundation
import AppKit

@MainActor
final class UpdateStore: ObservableObject {
    @Published var updateState: UpdateState = .idle
    @Published var brewMigrationState: BrewMigrationState = .notNeeded
    @Published var brewUninstallCommand: String = ""

    private let service: UpdateServiceProtocol
    private let brewMigration: BrewMigrationServiceProtocol

    private var migrationDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "brewMigrationDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "brewMigrationDismissed") }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    init(
        service: UpdateServiceProtocol = UpdateService(),
        brewMigration: BrewMigrationServiceProtocol = BrewMigrationService()
    ) {
        self.service = service
        self.brewMigration = brewMigration
        self.brewUninstallCommand = brewMigration.brewUninstallCommand()
    }

    // MARK: - Update Flow

    func checkForUpdates() {
        guard !updateState.isModalVisible else { return }
        updateState = .checking
        Task {
            do {
                if let item = try await service.checkForUpdate() {
                    updateState = .available(version: item.version, downloadURL: item.downloadURL)
                } else {
                    updateState = .upToDate
                    try? await Task.sleep(for: .seconds(3))
                    if case .upToDate = updateState { updateState = .idle }
                }
            } catch {
                updateState = .error(error.localizedDescription)
                try? await Task.sleep(for: .seconds(5))
                if case .error = updateState { updateState = .idle }
            }
        }
    }

    func downloadUpdate() {
        guard case .available(_, let url) = updateState else { return }
        updateState = .downloading(progress: 0)
        Task {
            do {
                let fileURL = try await service.downloadUpdate(from: url) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .downloading = self.updateState {
                            self.updateState = .downloading(progress: progress)
                        }
                    }
                }
                updateState = .downloaded(fileURL: fileURL)
            } catch {
                updateState = .error(error.localizedDescription)
            }
        }
    }

    func installUpdate() {
        guard case .downloaded(let dmgURL) = updateState else { return }
        updateState = .installing

        let realHome: String = {
            guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
            return String(cString: pw.pointee.pw_dir)
        }()

        let sharedDir = "\(realHome)/Library/Application Support/com.tokeneater.shared"
        let scriptPath = "\(sharedDir)/te-update.sh"
        let dmgSharedPath = "\(sharedDir)/TokenEater.dmg"

        // 1. Copy DMG from sandbox container to shared dir (root can't access containers)
        do {
            try? FileManager.default.removeItem(atPath: dmgSharedPath)
            try FileManager.default.copyItem(atPath: dmgURL.path, toPath: dmgSharedPath)
        } catch {
            updateState = .error(error.localizedDescription)
            return
        }

        // 2. Write install script to shared dir (real path, entitlement-accessible)
        let installScript = """
        #!/bin/bash
        exec > "\(sharedDir)/install.log" 2>&1
        echo "=== TokenEater Installer ==="
        echo "Date: $(date)"

        while pgrep -x "TokenEater" > /dev/null 2>&1; do sleep 0.3; done
        echo "App quit."

        MOUNT=$(hdiutil attach '\(dmgSharedPath)' -nobrowse | grep '/Volumes/' | head -1 | sed 's/.*\\(\\/Volumes\\/.*\\)/\\1/')
        echo "Mount: $MOUNT"
        [ -z "$MOUNT" ] && { echo "Mount failed"; exit 1; }

        rm -rf /Applications/TokenEater.app
        cp -R "$MOUNT/TokenEater.app" /Applications/
        chown -R \(NSUserName()):staff /Applications/TokenEater.app
        xattr -cr /Applications/TokenEater.app
        hdiutil detach "$MOUNT" -quiet 2>/dev/null

        echo "Install OK"
        open /Applications/TokenEater.app
        rm -f "\(scriptPath)" "\(dmgSharedPath)"
        """

        do {
            try installScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: scriptPath
            )
        } catch {
            updateState = .error(error.localizedDescription)
            return
        }

        // 2. Launch pre-built installer .app from our Resources (no quarantine)
        guard let installerURL = Bundle.main.url(
            forResource: "TokenEaterInstaller",
            withExtension: "app"
        ) else {
            updateState = .error("Installer not found in bundle")
            return
        }

        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [installerURL.path]
        do {
            try openProcess.run()
        } catch {
            updateState = .error(error.localizedDescription)
            return
        }

        // 3. Quit — installer waits for us, then shows admin dialog and installs
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApp.terminate(nil)
        }
    }

    func dismissUpdateModal() {
        updateState = .idle
    }

    // MARK: - Brew Migration

    func checkBrewMigration() {
        if migrationDismissed {
            brewMigrationState = .dismissed
        } else if brewMigration.isBrewInstall() {
            brewMigrationState = .detected
        } else {
            brewMigrationState = .notNeeded
        }
    }

    func dismissBrewMigration() {
        migrationDismissed = true
        brewMigrationState = .dismissed
    }
}
