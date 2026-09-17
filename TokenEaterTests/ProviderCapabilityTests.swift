import Testing
import Foundation

/// The capability matrix is the single declaration four surfaces read from:
/// the badge on a section header, the caption under the mode pills, the
/// Coverage page and the what's-new matrix. If it drifts from what the app
/// actually does, all four lie at once.
@Suite("Provider capabilities")
struct ProviderCapabilityTests {

    @Test("Every capability declares a state for every provider")
    func matrixIsTotal() {
        for capability in ProviderCapability.allCases {
            for provider in MetricProvider.allCases {
                // A capability supported by nobody is a capability that should
                // not be listed at all.
                _ = capability.support(for: provider)
            }
            #expect(!capability.providers.isEmpty, "\(capability.rawValue) serves no provider")
        }
    }

    @Test("Every capability has a name, and no two share one")
    func namesAreUniqueAndPresent() {
        let names = ProviderCapability.allCases.map(\.localizedName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test("The shared capabilities are the ones both providers really carry")
    func sharedSet() {
        let shared: [ProviderCapability] = [.usageWindows, .smartColor, .pacing, .notifications, .surfaces]
        for capability in shared {
            #expect(!capability.isUneven, "\(capability.rawValue) should be even")
            #expect(capability.support(for: .codex) == .full)
        }
    }

    @Test("The Claude-only capabilities are exactly the four that have no Codex pipeline")
    func claudeOnlySet() {
        let claudeOnly = ProviderCapability.allCases.filter { $0.support(for: .codex) == .none }
        #expect(Set(claudeOnly) == [.perModel, .extraCredits, .agentWatchers, .outageDetection])
        for capability in claudeOnly {
            #expect(capability.support(for: .claude) == .full)
            #expect(capability.isUneven)
        }
    }

    @Test("Partial support carries a reason, because a warning with no text explains nothing")
    func partialAlwaysExplains() {
        for capability in ProviderCapability.allCases {
            for provider in MetricProvider.allCases {
                if case .partial(let why) = capability.support(for: provider) {
                    #expect(!why.isEmpty, "\(capability.rawValue)/\(provider.rawValue) is partial with no reason")
                }
            }
        }
    }

    // MARK: - What the mode caption says

    @Test("All mode hides nothing, so it owes no explanation")
    func allModeHidesNothing() {
        #expect(ProviderMode.all.unavailableCapabilities.isEmpty)
    }

    @Test("A provider mode names exactly what it is hiding")
    func providerModesNameTheirCost() {
        let codexHides = ProviderMode.codex.unavailableCapabilities
        #expect(Set(codexHides) == [.perModel, .extraCredits, .agentWatchers, .outageDetection])

        // Claude carries everything, so Claude mode hides nothing and the
        // caption stays silent rather than inventing a cost.
        #expect(ProviderMode.claude.unavailableCapabilities.isEmpty)
    }

    @Test("A capability counted as hidden is never one the mode still shows")
    func hiddenSetIsDisjointFromShown() {
        for mode in ProviderMode.allCases {
            guard let provider = mode.provider else { continue }
            for capability in mode.unavailableCapabilities {
                #expect(!capability.isSupported(by: provider))
            }
        }
    }
}

/// The release screen fires once, for the right people, at the right time.
@Suite("What's new gate", .serialized)
@MainActor
struct WhatsNewGateTests {

    private func makeStore() -> SettingsStore {
        for key in ["hasCompletedOnboarding", "lastSeenVersion"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
    }

    @Test("Someone mid-onboarding is never shown it")
    func onboardingWins() {
        let store = makeStore()
        store.hasCompletedOnboarding = false
        #expect(!store.needsWhatsNew)
    }

    @Test("Finishing the wizard disarms it, so a new user does not get two takeovers")
    func finishingOnboardingDisarms() {
        let store = makeStore()
        store.hasCompletedOnboarding = true
        #expect(store.lastSeenVersion == SettingsStore.currentVersion)
        #expect(!store.needsWhatsNew)
    }

    @Test("An upgrading user has seen nothing, so they get it once")
    func upgradeShowsItOnce() {
        let store = makeStore()
        // Simulate an install that predates the key entirely.
        store.hasCompletedOnboarding = true
        store.lastSeenVersion = "5.13.0"
        #expect(store.needsWhatsNew)

        store.markWhatsNewSeen()
        #expect(!store.needsWhatsNew)
    }

    @Test("A patch release announces nothing")
    func patchIsSilent() {
        let store = makeStore()
        store.hasCompletedOnboarding = true
        let current = SettingsStore.currentVersion.split(separator: ".")
        guard current.count == 3 else { return }
        store.lastSeenVersion = "\(current[0]).\(current[1]).\(Int(current[2]).map { $0 + 9 } ?? 9)"
        #expect(!store.needsWhatsNew)
    }

    @Test("Replaying the wizard does not re-arm the release screen")
    func replayingOnboardingDoesNotReArm() {
        let store = makeStore()
        store.hasCompletedOnboarding = true
        store.hasCompletedOnboarding = false
        store.hasCompletedOnboarding = true
        #expect(!store.needsWhatsNew)
    }
}
