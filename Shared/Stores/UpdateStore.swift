import Foundation
import AppKit

@MainActor
final class UpdateStore: ObservableObject {
    @Published var updateState: UpdateState = .idle
    @Published var brewMigrationState: BrewMigrationState = .notNeeded
    @Published var brewUninstallCommand: String = ""

    private let service: UpdateServiceProtocol
    private let brewMigration: BrewMigrationServiceProtocol
    private let signatureVerifier: SignatureVerifierProtocol
    private let publicKeyProvider: () -> String?

    private var migrationDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "brewMigrationDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "brewMigrationDismissed") }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    init(
        service: UpdateServiceProtocol = UpdateService(),
        brewMigration: BrewMigrationServiceProtocol = BrewMigrationService(),
        signatureVerifier: SignatureVerifierProtocol = SignatureVerifier(),
        publicKeyProvider: @escaping () -> String? = UpdateStore.bundledPublicKey
    ) {
        self.service = service
        self.brewMigration = brewMigration
        self.signatureVerifier = signatureVerifier
        self.publicKeyProvider = publicKeyProvider
        self.brewUninstallCommand = brewMigration.brewUninstallCommand()
    }

    static func bundledPublicKey() -> String? {
        guard let url = Bundle.main.url(forResource: "SparklePublicKey", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Update Flow

    func checkForUpdates() {
        guard !updateState.isModalVisible else { return }
        updateState = .checking
        Task {
            do {
                if let item = try await service.checkForUpdate() {
                    updateState = .available(
                        version: item.version,
                        downloadURL: item.downloadURL,
                        signature: item.edSignature,
                        expectedLength: item.expectedLength
                    )
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
        guard case .available(_, let url, let signature, let expectedLength) = updateState else { return }
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
                updateState = .downloaded(
                    fileURL: fileURL,
                    signature: signature,
                    expectedLength: expectedLength
                )
            } catch {
                updateState = .error(error.localizedDescription)
            }
        }
    }

    func installUpdate() {
        guard case .downloaded(let dmgURL, let signature, let expectedLength) = updateState else { return }

        // Fail-closed: verify length + signature BEFORE giving the DMG to the privileged installer.
        if let verificationError = verifyDownloadedUpdate(
            at: dmgURL,
            signature: signature,
            expectedLength: expectedLength
        ) {
            updateState = .error(verificationError)
            return
        }

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

        // 3. Quit - installer waits for us, then shows admin dialog and installs
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApp.terminate(nil)
        }
    }

    func dismissUpdateModal() {
        updateState = .idle
    }

    // MARK: - Verification

    /// Returns a localized error message if verification fails, or nil if the DMG is acceptable.
    /// Size check is only enforced when the appcast advertises a positive expected length
    /// (older appcast entries sometimes ship `length="0"`, which we treat as "unknown").
    /// Signature verification is always required (fail-closed).
    func verifyDownloadedUpdate(
        at dmgURL: URL,
        signature: String?,
        expectedLength: Int64?
    ) -> String? {
        if let expected = expectedLength, expected > 0 {
            let actual = (try? FileManager.default.attributesOfItem(atPath: dmgURL.path)[.size] as? Int64) ?? -1
            if actual != expected {
                return String(localized: "update.error.sizeMismatch")
            }
        }

        guard let signature, !signature.isEmpty else {
            return String(localized: "update.error.signatureMissing")
        }

        guard let publicKey = publicKeyProvider(), !publicKey.isEmpty else {
            return String(localized: "update.error.verifyReadFailed")
        }

        guard let dmgData = try? Data(contentsOf: dmgURL) else {
            return String(localized: "update.error.verifyReadFailed")
        }

        guard signatureVerifier.verify(
            data: dmgData,
            base64Signature: signature,
            base64PublicKey: publicKey
        ) else {
            return String(localized: "update.error.signatureInvalid")
        }

        return nil
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
