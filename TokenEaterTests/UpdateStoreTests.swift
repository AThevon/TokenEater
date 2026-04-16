import Testing
import Foundation

@Suite("UpdateStore", .serialized)
@MainActor
struct UpdateStoreTests {
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "brewMigrationDismissed")
    }

    private func makeStore(
        service: UpdateServiceProtocol = MockUpdateService(),
        brewMigration: BrewMigrationServiceProtocol = MockBrewMigrationService(),
        signatureVerifier: SignatureVerifierProtocol = MockSignatureVerifier(),
        publicKey: String? = "stub-public-key"
    ) -> UpdateStore {
        UpdateStore(
            service: service,
            brewMigration: brewMigration,
            signatureVerifier: signatureVerifier,
            publicKeyProvider: { publicKey }
        )
    }

    private func writeTempDMG(bytes: Int = 32) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test-\(UUID().uuidString).dmg")
        let payload = Data((0..<bytes).map { UInt8($0 & 0xFF) })
        try? payload.write(to: url)
        return url
    }

    // MARK: - Brew Migration

    @Test("shows brew migration when brew install detected")
    func brewMigrationDetected() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = true
        let store = makeStore(brewMigration: mockBrew)
        store.checkBrewMigration()
        #expect(store.brewMigrationState == .detected)
    }

    @Test("hides brew migration when no brew install")
    func noBrewMigration() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = false
        let store = makeStore(brewMigration: mockBrew)
        store.checkBrewMigration()
        #expect(store.brewMigrationState == .notNeeded)
    }

    @Test("dismissing brew migration persists across instances")
    func dismissBrewMigration() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = true
        let store = makeStore(brewMigration: mockBrew)
        store.checkBrewMigration()
        store.dismissBrewMigration()
        #expect(store.brewMigrationState == .dismissed)

        let store2 = makeStore(brewMigration: mockBrew)
        store2.checkBrewMigration()
        #expect(store2.brewMigrationState == .dismissed)
    }

    // MARK: - Update Check

    @Test("checkForUpdates sets checking then available when update exists")
    func checkForUpdatesAvailable() async throws {
        let mockService = MockUpdateService()
        mockService.checkResult = AppcastItem(
            version: "9.9.9",
            downloadURL: URL(string: "https://example.com/test.dmg")!,
            edSignature: "sig==",
            expectedLength: 1024
        )
        let store = makeStore(service: mockService)
        store.checkForUpdates()

        try await Task.sleep(for: .milliseconds(100))

        #expect(mockService.checkForUpdateCalled)
        if case .available(let version, _, let signature, let length) = store.updateState {
            #expect(version == "9.9.9")
            #expect(signature == "sig==")
            #expect(length == 1024)
        } else {
            Issue.record("Expected .available state, got \(store.updateState)")
        }
    }

    @Test("checkForUpdates sets upToDate when no update")
    func checkForUpdatesUpToDate() async throws {
        let mockService = MockUpdateService()
        mockService.checkResult = nil
        let store = makeStore(service: mockService)
        store.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))

        #expect(mockService.checkForUpdateCalled)
        #expect(store.updateState == .upToDate)
    }

    @Test("checkForUpdates sets error on failure")
    func checkForUpdatesError() async throws {
        let mockService = MockUpdateService()
        mockService.checkError = URLError(.notConnectedToInternet)
        let store = makeStore(service: mockService)
        store.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))

        if case .error = store.updateState {
            // OK
        } else {
            Issue.record("Expected .error state, got \(store.updateState)")
        }
    }

    // MARK: - Version Comparison

    @Test("version comparator: newer patch")
    func versionNewerPatch() {
        #expect(VersionComparator.isNewer("4.6.3", than: "4.6.2"))
        #expect(!VersionComparator.isNewer("4.6.2", than: "4.6.3"))
    }

    @Test("version comparator: release beats pre-release")
    func versionReleaseBeatsPre() {
        #expect(VersionComparator.isNewer("4.6.3", than: "4.6.3-beta.1"))
        #expect(!VersionComparator.isNewer("4.6.3-beta.1", than: "4.6.3"))
    }

    @Test("version comparator: pre-release ordering")
    func versionPreRelease() {
        #expect(VersionComparator.isNewer("4.6.3-beta.2", than: "4.6.3-beta.1"))
        #expect(VersionComparator.isNewer("4.6.3-beta.1", than: "4.6.2"))
    }

    @Test("version comparator: equal versions")
    func versionEqual() {
        #expect(!VersionComparator.isNewer("4.6.3", than: "4.6.3"))
    }

    @Test("dismiss update modal resets state")
    func dismissModal() {
        let store = makeStore()
        store.updateState = .available(
            version: "9.9.9",
            downloadURL: URL(string: "https://example.com")!,
            signature: nil,
            expectedLength: nil
        )
        store.dismissUpdateModal()
        #expect(store.updateState == .idle)
    }

    // MARK: - Signature Verification

    @Test("verifyDownloadedUpdate accepts a valid signature")
    func verifyAcceptsValidSignature() {
        let dmgURL = writeTempDMG(bytes: 32)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = true
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "dummy-signature",
            expectedLength: 32
        )
        #expect(error == nil)
        #expect(verifier.verifyCallCount == 1)
        #expect(verifier.lastSignature == "dummy-signature")
        #expect(verifier.lastPublicKey == "stub-public-key")
    }

    @Test("verifyDownloadedUpdate rejects when signature is nil")
    func verifyRejectsNilSignature() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: nil,
            expectedLength: nil
        )
        #expect(error != nil)
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("verifyDownloadedUpdate rejects when signature is empty string")
    func verifyRejectsEmptySignature() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "",
            expectedLength: nil
        )
        #expect(error != nil)
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("verifyDownloadedUpdate rejects when verifier returns false")
    func verifyRejectsInvalidSignature() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = false
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "tampered-signature",
            expectedLength: nil
        )
        #expect(error != nil)
        #expect(verifier.verifyCallCount == 1)
    }

    @Test("verifyDownloadedUpdate rejects when public key is unavailable")
    func verifyRejectsMissingPublicKey() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        let store = makeStore(signatureVerifier: verifier, publicKey: nil)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "dummy-signature",
            expectedLength: nil
        )
        #expect(error != nil)
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("verifyDownloadedUpdate rejects when file size does not match expected length")
    func verifyRejectsSizeMismatch() {
        let dmgURL = writeTempDMG(bytes: 32)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = true
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "dummy-signature",
            expectedLength: 999_999
        )
        #expect(error != nil)
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("verifyDownloadedUpdate treats expectedLength=0 as unknown (skips size check)")
    func verifySkipsSizeCheckWhenZero() {
        let dmgURL = writeTempDMG(bytes: 32)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = true
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "dummy-signature",
            expectedLength: 0
        )
        #expect(error == nil)
        #expect(verifier.verifyCallCount == 1)
    }

    @Test("verifyDownloadedUpdate treats expectedLength=nil as unknown (skips size check)")
    func verifySkipsSizeCheckWhenNil() {
        let dmgURL = writeTempDMG(bytes: 32)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = true
        let store = makeStore(signatureVerifier: verifier)

        let error = store.verifyDownloadedUpdate(
            at: dmgURL,
            signature: "dummy-signature",
            expectedLength: nil
        )
        #expect(error == nil)
        #expect(verifier.verifyCallCount == 1)
    }

    @Test("installUpdate transitions to error state when signature is missing")
    func installUpdateRejectsMissingSignature() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        let store = makeStore(signatureVerifier: verifier)
        store.updateState = .downloaded(fileURL: dmgURL, signature: nil, expectedLength: nil)
        store.installUpdate()

        if case .error = store.updateState {
            // OK, fail-closed
        } else {
            Issue.record("Expected .error state, got \(store.updateState)")
        }
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("installUpdate transitions to error state when verifier rejects")
    func installUpdateRejectsInvalidSignature() {
        let dmgURL = writeTempDMG()
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let verifier = MockSignatureVerifier()
        verifier.verifyResult = false
        let store = makeStore(signatureVerifier: verifier)
        store.updateState = .downloaded(fileURL: dmgURL, signature: "tampered", expectedLength: nil)
        store.installUpdate()

        if case .error = store.updateState {
            // OK, fail-closed
        } else {
            Issue.record("Expected .error state, got \(store.updateState)")
        }
        #expect(verifier.verifyCallCount == 1)
    }
}
