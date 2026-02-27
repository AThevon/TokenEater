# Enrich Displayed Data — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Opus/Cowork usage + profile info from Anthropic API, build a dark premium dashboard window, redesign the popover, and migrate to NSStatusItem for click-behavior control.

**Architecture:** NSStatusItem (AppKit) replaces MenuBarExtra for full control over menu bar click routing. New `/api/oauth/profile` endpoint provides plan type and rate limit tier. Reusable SwiftUI components (RingGauge, PacingBar, ParticleField) shared between dashboard and popover.

**Tech Stack:** SwiftUI (views) + AppKit (NSStatusItem, NSPopover, NSWindow) + Canvas (particles) + Swift Testing (tests)

**Design doc:** `docs/plans/2026-02-26-enrich-displayed-data-design.md`

---

## Phase 1: Data Layer

### Task 1: ProfileResponse model + fixture

**Files:**
- Create: `Shared/Models/ProfileModels.swift`
- Create: `TokenEaterTests/Fixtures/ProfileResponse+Fixture.swift`

**Step 1: Create ProfileResponse model**

```swift
// Shared/Models/ProfileModels.swift
import Foundation

struct ProfileResponse: Codable {
    let account: AccountInfo
    let organization: OrganizationInfo?
}

struct AccountInfo: Codable {
    let uuid: String
    let fullName: String
    let displayName: String
    let email: String
    let hasClaudeMax: Bool
    let hasClaudePro: Bool

    enum CodingKeys: String, CodingKey {
        case uuid
        case fullName = "full_name"
        case displayName = "display_name"
        case email
        case hasClaudeMax = "has_claude_max"
        case hasClaudePro = "has_claude_pro"
    }
}

struct OrganizationInfo: Codable {
    let uuid: String
    let name: String
    let organizationType: String
    let billingType: String
    let rateLimitTier: String

    enum CodingKeys: String, CodingKey {
        case uuid, name
        case organizationType = "organization_type"
        case billingType = "billing_type"
        case rateLimitTier = "rate_limit_tier"
    }
}

enum PlanType: String, Codable {
    case pro, max, free, unknown

    init(from account: AccountInfo) {
        if account.hasClaudeMax { self = .max }
        else if account.hasClaudePro { self = .pro }
        else { self = .free }
    }
}
```

**Step 2: Create fixture**

```swift
// TokenEaterTests/Fixtures/ProfileResponse+Fixture.swift
import Foundation

extension ProfileResponse {
    static func fixture(
        fullName: String = "Test User",
        displayName: String = "Test",
        email: String = "test@example.com",
        hasClaudeMax: Bool = false,
        hasClaudePro: Bool = true,
        orgName: String? = "Test Org",
        orgType: String = "personal",
        rateLimitTier: String = "default_claude_pro"
    ) -> ProfileResponse {
        ProfileResponse(
            account: AccountInfo(
                uuid: "test-uuid",
                fullName: fullName,
                displayName: displayName,
                email: email,
                hasClaudeMax: hasClaudeMax,
                hasClaudePro: hasClaudePro
            ),
            organization: orgName.map { name in
                OrganizationInfo(
                    uuid: "org-uuid",
                    name: name,
                    organizationType: orgType,
                    billingType: "stripe",
                    rateLimitTier: rateLimitTier
                )
            }
        )
    }
}
```

**Step 3: Write test for JSON decoding**

```swift
// Add to a new file TokenEaterTests/ProfileModelTests.swift
import Testing
@testable import TokenEater

@Suite("ProfileModels")
struct ProfileModelTests {

    @Test("decodes profile JSON with all fields")
    func decodesFullProfile() throws {
        let json = """
        {
          "account": {
            "uuid": "abc",
            "full_name": "John Doe",
            "display_name": "John",
            "email": "john@example.com",
            "has_claude_max": false,
            "has_claude_pro": true
          },
          "organization": {
            "uuid": "org1",
            "name": "My Org",
            "organization_type": "claude_enterprise",
            "billing_type": "stripe_subscription_contracted",
            "rate_limit_tier": "default_claude_max_5x"
          }
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(profile.account.fullName == "John Doe")
        #expect(profile.account.hasClaudePro == true)
        #expect(profile.account.hasClaudeMax == false)
        #expect(profile.organization?.rateLimitTier == "default_claude_max_5x")
    }

    @Test("decodes profile with null organization")
    func decodesNullOrg() throws {
        let json = """
        {
          "account": {
            "uuid": "abc",
            "full_name": "Solo User",
            "display_name": "Solo",
            "email": "solo@example.com",
            "has_claude_max": true,
            "has_claude_pro": false
          },
          "organization": null
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(profile.organization == nil)
        #expect(PlanType(from: profile.account) == .max)
    }

    @Test("PlanType derives correctly from account flags")
    func planTypeDerivation() {
        let proAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: true)
        let maxAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let freeAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: false)

        #expect(PlanType(from: proAccount) == .pro)
        #expect(PlanType(from: maxAccount) == .max)
        #expect(PlanType(from: freeAccount) == .free)
    }
}
```

**Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

Expected: All tests PASS.

**Step 5: Commit**

```
feat(models): add ProfileResponse model and PlanType enum

New Codable models for /api/oauth/profile endpoint.
Includes AccountInfo, OrganizationInfo, and PlanType derivation.
```

---

### Task 2: APIClient — fetchProfile method

**Files:**
- Modify: `Shared/Services/Protocols/APIClientProtocol.swift`
- Modify: `Shared/Services/APIClient.swift`
- Modify: `TokenEaterTests/Mocks/MockAPIClient.swift`

**Step 1: Add fetchProfile to protocol**

Add to `APIClientProtocol`:
```swift
func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
```

**Step 2: Implement in APIClient**

Add to `APIClient`:
```swift
private let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

private func makeProfileRequest(token: String) -> URLRequest {
    var request = URLRequest(url: profileURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    return request
}

func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
    let request = makeProfileRequest(token: token)
    let (data, response) = try await session(proxyConfig: proxyConfig).data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200:
        return try JSONDecoder().decode(ProfileResponse.self, from: data)
    case 401, 403:
        throw APIError.tokenExpired
    default:
        throw APIError.httpError(httpResponse.statusCode)
    }
}
```

**Step 3: Update MockAPIClient**

Add to `MockAPIClient`:
```swift
var stubbedProfile: ProfileResponse?

func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
    if let error = stubbedError { throw error }
    return stubbedProfile ?? .fixture()
}
```

**Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

Expected: All existing tests still PASS.

**Step 5: Commit**

```
feat(api): add fetchProfile endpoint to APIClient

Calls GET /api/oauth/profile with same OAuth auth headers.
Returns ProfileResponse with account info and organization details.
```

---

### Task 3: UsageRepository — fetchProfile orchestration

**Files:**
- Modify: `Shared/Repositories/UsageRepository.swift`
- Modify: `Shared/Services/Protocols/UsageRepositoryProtocol.swift` (path may be in Repositories folder — check)
- Modify: `TokenEaterTests/Mocks/MockUsageRepository.swift`
- Create: `TokenEaterTests/UsageRepositoryProfileTests.swift`

**Step 1: Add fetchProfile to UsageRepositoryProtocol**

```swift
func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse
```

**Step 2: Implement in UsageRepository**

```swift
func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
    guard let token = sharedFileService.oauthToken else {
        throw APIError.noToken
    }
    return try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
}
```

Note: No caching needed for profile — fetched on-demand only.

**Step 3: Update MockUsageRepository**

```swift
var stubbedProfile: ProfileResponse?
var stubbedProfileError: APIError?

func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
    if let error = stubbedProfileError { throw error }
    return stubbedProfile ?? .fixture()
}
```

**Step 4: Write tests**

```swift
// TokenEaterTests/UsageRepositoryProfileTests.swift
import Testing
@testable import TokenEater

@Suite("UsageRepository – Profile")
struct UsageRepositoryProfileTests {

    private func makeSUT() -> (repo: UsageRepository, api: MockAPIClient, keychain: MockKeychainService, sharedFile: MockSharedFileService) {
        let api = MockAPIClient()
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        let repo = UsageRepository(apiClient: api, keychainService: keychain, sharedFileService: sharedFile)
        return (repo, api, keychain, sharedFile)
    }

    @Test("fetchProfile returns profile when token exists")
    func fetchProfileSuccess() async throws {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "valid-token"
        let expected = ProfileResponse.fixture(fullName: "Alice")
        api.stubbedProfile = expected

        let profile = try await repo.fetchProfile(proxyConfig: nil)
        #expect(profile.account.fullName == "Alice")
    }

    @Test("fetchProfile throws noToken when no token")
    func fetchProfileNoToken() async {
        let (repo, _, _, _) = makeSUT()

        do {
            _ = try await repo.fetchProfile(proxyConfig: nil)
            Issue.record("Expected APIError.noToken")
        } catch let error as APIError {
            guard case .noToken = error else {
                Issue.record("Expected .noToken, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }
}
```

**Step 5: Run tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

**Step 6: Commit**

```
feat(repository): add fetchProfile to UsageRepository

Orchestrates profile fetch through APIClient with token from SharedFileService.
```

---

### Task 4: UsageStore — enriched data properties

**Files:**
- Modify: `Shared/Stores/UsageStore.swift`
- Modify: `TokenEaterTests/UsageStoreTests.swift`

**Step 1: Add new @Published properties to UsageStore**

Add after existing `@Published` properties:
```swift
@Published var opusPct: Int = 0
@Published var coworkPct: Int = 0
@Published var oauthAppsPct: Int = 0
@Published var hasOpus: Bool = false
@Published var hasCowork: Bool = false
@Published var planType: PlanType = .unknown
@Published var rateLimitTier: String?
@Published var organizationName: String?
```

**Step 2: Update `update(from:)` to extract new buckets**

Add to `update(from:)`:
```swift
opusPct = Int(usage.sevenDayOpus?.utilization ?? 0)
coworkPct = Int(usage.sevenDayCowork?.utilization ?? 0)
oauthAppsPct = Int(usage.sevenDayOauthApps?.utilization ?? 0)
hasOpus = usage.sevenDayOpus != nil
hasCowork = usage.sevenDayCowork != nil
```

**Step 3: Add refreshProfile method**

```swift
func refreshProfile() async {
    guard repository.isConfigured else { return }
    do {
        let profile = try await repository.fetchProfile(proxyConfig: proxyConfig)
        planType = PlanType(from: profile.account)
        rateLimitTier = profile.organization?.rateLimitTier
        organizationName = profile.organization?.name
    } catch {
        // Profile fetch failure is non-critical — don't update errorState
    }
}
```

**Step 4: Call refreshProfile from reloadConfig**

In `reloadConfig()`, after the existing `refreshTask = Task { await refresh(...) }`, add:
```swift
Task { await refreshProfile() }
```

**Step 5: Write tests**

Add to `UsageStoreTests.swift`:
```swift
@Test("refresh extracts opus and cowork percentages")
func refreshExtractsNewBuckets() async {
    let usage = UsageResponse(
        fiveHour: .fixture(utilization: 50),
        sevenDay: .fixture(utilization: 40),
        sevenDaySonnet: .fixture(utilization: 30),
        sevenDayOpus: .fixture(utilization: 20),
        sevenDayCowork: .fixture(utilization: 10)
    )
    let (store, _, _) = makeSUT(usage: usage)

    await store.refresh()

    #expect(store.opusPct == 20)
    #expect(store.coworkPct == 10)
    #expect(store.hasOpus == true)
    #expect(store.hasCowork == true)
}

@Test("refresh sets hasOpus false when bucket nil")
func refreshNilOpus() async {
    let usage = UsageResponse(fiveHour: .fixture(utilization: 50))
    let (store, _, _) = makeSUT(usage: usage)

    await store.refresh()

    #expect(store.hasOpus == false)
    #expect(store.opusPct == 0)
}

@Test("refreshProfile updates plan type")
func refreshProfileSetsPlanType() async {
    let (store, repo, _) = makeSUT()
    repo.stubbedProfile = .fixture(hasClaudeMax: false, hasClaudePro: true)

    await store.refreshProfile()

    #expect(store.planType == .pro)
}

@Test("refreshProfile failure does not set error state")
func refreshProfileFailureSilent() async {
    let (store, repo, _) = makeSUT()
    repo.stubbedProfileError = .invalidResponse

    await store.refreshProfile()

    #expect(store.errorState == .none)
    #expect(store.planType == .unknown)
}
```

Note: The `makeSUT()` helper needs the MockUsageRepository updated (Task 3) with `stubbedProfile`/`stubbedProfileError`.

**Step 6: Run tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

**Step 7: Commit**

```
feat(store): enrich UsageStore with Opus, Cowork, and profile data

Extracts seven_day_opus and seven_day_cowork from usage response.
Adds refreshProfile() for plan type, rate limit tier, and org name.
```

---

## Phase 2: Reusable UI Components

### Task 5: RingGauge component

**Files:**
- Create: `Shared/Components/RingGauge.swift`

This is a visual component — verify by visual inspection, not unit tests.

**Step 1: Create RingGauge**

```swift
// Shared/Components/RingGauge.swift
import SwiftUI

struct RingGauge: View {
    let percentage: Int
    let gradient: LinearGradient
    let size: CGFloat
    let lineWidth: CGFloat
    let glowColor: Color
    let glowRadius: CGFloat

    init(
        percentage: Int,
        gradient: LinearGradient,
        size: CGFloat = 200,
        lineWidth: CGFloat? = nil,
        glowColor: Color = .clear,
        glowRadius: CGFloat = 0
    ) {
        self.percentage = percentage
        self.gradient = gradient
        self.size = size
        self.lineWidth = lineWidth ?? max(size * 0.08, 4)
        self.glowColor = glowColor
        self.glowRadius = glowRadius
    }

    @State private var animatedPct: Double = 0

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            // Filled arc
            Circle()
                .trim(from: 0, to: animatedPct / 100)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glowColor.opacity(0.6), radius: glowRadius)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedPct = Double(percentage)
            }
        }
        .onChange(of: percentage) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedPct = Double(newValue)
            }
        }
    }
}
```

**Step 2: Commit**

```
feat(ui): add RingGauge reusable component

Animated circular arc with gradient stroke, glow, and spring animation.
Supports S/M/L sizes via size parameter.
```

---

### Task 6: PacingBar component

**Files:**
- Create: `Shared/Components/PacingBar.swift`

**Step 1: Create PacingBar**

```swift
// Shared/Components/PacingBar.swift
import SwiftUI

struct PacingBar: View {
    let actual: Double
    let expected: Double
    let zone: PacingZone
    let gradient: LinearGradient
    let compact: Bool

    init(actual: Double, expected: Double, zone: PacingZone, gradient: LinearGradient, compact: Bool = false) {
        self.actual = actual
        self.expected = expected
        self.zone = zone
        self.gradient = gradient
        self.compact = compact
    }

    @State private var animatedActual: Double = 0
    @State private var pulsing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: compact ? 4 : 8)

                // Fill
                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(gradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(animatedActual, 100)) / 100), height: compact ? 4 : 8)

                // Ideal marker (triangle)
                idealMarker
                    .offset(x: geo.size.width * CGFloat(min(expected, 100)) / 100 - (compact ? 3 : 5))

                // Actual marker (pulsing dot) — only in full mode
                if !compact {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.5), radius: pulsing ? 6 : 2)
                        .offset(x: geo.size.width * CGFloat(min(animatedActual, 100)) / 100 - 5)
                }
            }
        }
        .frame(height: compact ? 10 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedActual = actual
            }
            if !compact {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: actual) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedActual = newValue
            }
        }
    }

    private var idealMarker: some View {
        let size: CGFloat = compact ? 6 : 10
        return Path { path in
            path.move(to: CGPoint(x: size / 2, y: 0))
            path.addLine(to: CGPoint(x: size, y: size))
            path.addLine(to: CGPoint(x: 0, y: size))
            path.closeSubpath()
        }
        .fill(Color.white.opacity(0.5))
        .frame(width: size, height: size)
    }
}
```

**Step 2: Commit**

```
feat(ui): add PacingBar reusable component

Horizontal bar with animated fill, ideal triangle marker,
and pulsing actual-position dot. Supports compact and full modes.
```

---

### Task 7: AnimatedGradient + ParticleField + GlowText

**Files:**
- Create: `Shared/Components/AnimatedGradient.swift`
- Create: `Shared/Components/ParticleField.swift`
- Create: `Shared/Components/GlowText.swift`

**Step 1: Create AnimatedGradient**

```swift
// Shared/Components/AnimatedGradient.swift
import SwiftUI

struct AnimatedGradient: View {
    let baseColors: [Color]
    let animationDuration: Double

    @State private var start = UnitPoint(x: 0, y: 0)
    @State private var end = UnitPoint(x: 1, y: 1)

    init(baseColors: [Color] = [Color(hex: "0a0a1a"), Color(hex: "141428")], animationDuration: Double = 30) {
        self.baseColors = baseColors
        self.animationDuration = animationDuration
    }

    var body: some View {
        LinearGradient(colors: baseColors, startPoint: start, endPoint: end)
            .onAppear {
                withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
                    start = UnitPoint(x: 1, y: 0)
                    end = UnitPoint(x: 0, y: 1)
                }
            }
    }
}
```

**Step 2: Create ParticleField**

```swift
// Shared/Components/ParticleField.swift
import SwiftUI

struct ParticleField: View {
    let particleCount: Int
    let speed: Double  // 0.0 (slow) to 1.0 (fast)
    let color: Color
    let radius: CGFloat

    init(particleCount: Int = 20, speed: Double = 0.5, color: Color = .white, radius: CGFloat = 120) {
        self.particleCount = particleCount
        self.speed = speed
        self.color = color
        self.radius = radius
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate * (0.2 + speed * 0.8)

                for i in 0..<particleCount {
                    let phase = Double(i) / Double(particleCount) * .pi * 2
                    let orbitSpeed = 0.3 + Double(i % 5) * 0.15
                    let angle = time * orbitSpeed + phase
                    let r = radius * (0.7 + 0.3 * sin(time * 0.5 + phase))

                    let x = center.x + cos(angle) * r
                    let y = center.y + sin(angle) * r

                    let opacity = 0.2 + 0.4 * (sin(time * 2 + phase) * 0.5 + 0.5)
                    let dotSize = 1.5 + sin(time + phase) * 0.8

                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}
```

**Step 3: Create GlowText**

```swift
// Shared/Components/GlowText.swift
import SwiftUI

struct GlowText: View {
    let text: String
    let font: Font
    let color: Color
    let glowRadius: CGFloat

    init(_ text: String, font: Font = .title, color: Color = .white, glowRadius: CGFloat = 4) {
        self.text = text
        self.font = font
        self.color = color
        self.glowRadius = glowRadius
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.5), radius: glowRadius)
    }
}
```

**Step 4: Commit**

```
feat(ui): add AnimatedGradient, ParticleField, and GlowText components

AnimatedGradient: slowly shifting background gradient.
ParticleField: orbiting luminous particles via Canvas.
GlowText: text with neon shadow effect.
```

---

## Phase 3: Settings — Click Behavior

### Task 8: ClickBehavior setting in SettingsStore

**Files:**
- Create: `Shared/Models/ClickBehavior.swift`
- Modify: `Shared/Stores/SettingsStore.swift`
- Modify: `TokenEaterTests/SettingsStoreTests.swift`

**Step 1: Create ClickBehavior enum**

```swift
// Shared/Models/ClickBehavior.swift
import Foundation

enum ClickBehavior: String, CaseIterable {
    case popover
    case dashboard
}
```

**Step 2: Add to SettingsStore**

Add `@Published` property:
```swift
@Published var clickBehavior: ClickBehavior {
    didSet { UserDefaults.standard.set(clickBehavior.rawValue, forKey: "clickBehavior") }
}
```

Initialize in `init()`:
```swift
self.clickBehavior = ClickBehavior(
    rawValue: UserDefaults.standard.string(forKey: "clickBehavior") ?? "popover"
) ?? .popover
```

**Step 3: Write test**

Add to `SettingsStoreTests.swift`:
```swift
@Test("clickBehavior defaults to popover")
func clickBehaviorDefault() {
    UserDefaults.standard.removeObject(forKey: "clickBehavior")
    let (store, _) = makeStore()
    #expect(store.clickBehavior == .popover)
}

@Test("clickBehavior persists to UserDefaults")
func clickBehaviorPersists() {
    let (store, _) = makeStore()
    store.clickBehavior = .dashboard
    #expect(UserDefaults.standard.string(forKey: "clickBehavior") == "dashboard")
}
```

Note: Check `makeStore()` helper in SettingsStoreTests — ensure it cleans `clickBehavior` key in its cleanup.

**Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

**Step 5: Commit**

```
feat(settings): add clickBehavior setting (popover/dashboard)

Persisted in UserDefaults, defaults to popover.
```

---

### Task 9: Add Click Behavior to SettingsView

**Files:**
- Modify: `TokenEaterApp/SettingsView.swift`

**Step 1: Add picker in Display tab**

Find the Display tab section in SettingsView. Add a new section before or after the menu bar visibility toggle:

```swift
// Click behavior picker
VStack(alignment: .leading, spacing: 6) {
    Text(String(localized: "settings.clickbehavior"))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)

    Picker("", selection: $localClickBehavior) {
        Text(String(localized: "settings.clickbehavior.popover")).tag(ClickBehavior.popover)
        Text(String(localized: "settings.clickbehavior.dashboard")).tag(ClickBehavior.dashboard)
    }
    .pickerStyle(.segmented)
    .onChange(of: localClickBehavior) { _, newValue in
        settingsStore.clickBehavior = newValue
    }
}
```

Use `@State private var localClickBehavior: ClickBehavior` + `.onAppear { localClickBehavior = settingsStore.clickBehavior }` pattern (matching existing codebase pattern for avoiding Binding to computed properties).

**Step 2: Add localization keys**

Add to `en.lproj/Localizable.strings`:
```
"settings.clickbehavior" = "Menu Bar Click";
"settings.clickbehavior.popover" = "Quick Glance";
"settings.clickbehavior.dashboard" = "Dashboard";
```

Add to `fr.lproj/Localizable.strings`:
```
"settings.clickbehavior" = "Clic barre de menu";
"settings.clickbehavior.popover" = "Aperçu rapide";
"settings.clickbehavior.dashboard" = "Dashboard";
```

**Step 3: Build and verify visually**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) build 2>&1 | tail -3
```

**Step 4: Commit**

```
feat(settings): add click behavior picker in Display tab

Segmented control to choose between popover and dashboard on menu bar click.
```

---

## Phase 4: StatusBarController (AppKit Migration)

### Task 10: Create StatusBarController

**Files:**
- Create: `TokenEaterApp/StatusBarController.swift`

This is the core architectural change. The StatusBarController manages NSStatusItem, NSPopover, and the dashboard NSWindow.

**Step 1: Create StatusBarController**

```swift
// TokenEaterApp/StatusBarController.swift
import AppKit
import SwiftUI
import Combine

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let usageStore: UsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore

    init(
        usageStore: UsageStore,
        themeStore: ThemeStore,
        settingsStore: SettingsStore,
        updateStore: UpdateStore
    ) {
        self.usageStore = usageStore
        self.themeStore = themeStore
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupPopover()
        observeStoreChanges()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusBarClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp])
        updateMenuBarIcon()
    }

    private func setupPopover() {
        let popoverView = MenuBarPopoverView()
            .environmentObject(usageStore)
            .environmentObject(themeStore)
            .environmentObject(settingsStore)
            .environmentObject(updateStore)

        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.behavior = .transient
    }

    private func observeStoreChanges() {
        // Re-render menu bar icon when relevant store properties change
        Publishers.MergeMany(
            usageStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            themeStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateMenuBarIcon()
        }
        .store(in: &cancellables)
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon() {
        let image = MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            pacingDelta: usageStore.pacingDelta,
            pacingZone: usageStore.pacingZone,
            pacingDisplayMode: settingsStore.pacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            themeColors: themeStore.current,
            thresholds: themeStore.thresholds,
            menuBarMonochrome: themeStore.menuBarMonochrome
        ))
        statusItem.button?.image = image
    }

    // MARK: - Click handling

    @objc private func statusBarClicked() {
        switch settingsStore.clickBehavior {
        case .popover:
            togglePopover()
        case .dashboard:
            showDashboard()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    func showDashboard() {
        popover.performClose(nil)
        stopEventMonitor()

        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboardView = DashboardView()
            .environmentObject(usageStore)
            .environmentObject(themeStore)
            .environmentObject(settingsStore)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
        window.contentViewController = NSHostingController(rootView: dashboardView)
        window.center()
        window.setFrameAutosaveName("DashboardWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.dashboardWindow = window
    }

    // MARK: - Event Monitor (close popover on outside click)

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
```

**Step 2: Build check**

This won't compile yet because `DashboardView` doesn't exist. Create a placeholder:

```swift
// TokenEaterApp/DashboardView.swift (placeholder)
import SwiftUI

struct DashboardView: View {
    var body: some View {
        Text("Dashboard — Coming Soon")
            .frame(width: 650, height: 550)
            .background(Color(hex: "0a0a1a"))
    }
}
```

**Step 3: Commit**

```
feat(app): add StatusBarController with NSStatusItem, NSPopover, and dashboard window

Manages menu bar icon rendering, click behavior routing (popover/dashboard),
and outside-click dismiss. DashboardView is a placeholder for now.
```

---

### Task 11: Migrate TokenEaterApp from MenuBarExtra to StatusBarController

**Files:**
- Modify: `TokenEaterApp/TokenEaterApp.swift`

This is a critical change — we're removing the `MenuBarExtra` scene and replacing it with the `StatusBarController`.

**Step 1: Update TokenEaterApp**

Replace the current App struct body. Key changes:
- Remove `MenuBarExtra` scene
- Remove `MenuBarLabel` view
- Remove `@AppStorage("showMenuBar")` (the StatusBarController manages visibility)
- Add `private let statusBarController: StatusBarController`
- Initialize it in `init()` after stores are created

```swift
@main
struct TokenEaterApp: App {
    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()

    private let statusBarController: StatusBarController

    init() {
        NotificationService().setupDelegate()
        statusBarController = StatusBarController(
            usageStore: usageStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore
        )
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            RootView()
        }
        .environmentObject(usageStore)
        .environmentObject(themeStore)
        .environmentObject(settingsStore)
        .environmentObject(updateStore)
        .windowResizability(.contentSize)
    }
}
```

Note: `RootView` and `SettingsContentView` remain unchanged.

**Step 2: Update MenuBarPopoverView onAppear**

The popover's `onAppear` currently starts auto-refresh. This is now handled by `SettingsContentView.task`. Verify that the popover's `onAppear` logic still works — it should because it checks `if usageStore.lastUpdate == nil` and refreshes accordingly.

**Step 3: Handle "Open Dashboard" from popover**

Add a way for the popover to open the dashboard. The simplest approach: add a `showDashboard` callback environment key, or post a notification.

Create a simple notification-based approach:
```swift
// Add to StatusBarController
private func observeDashboardRequest() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleDashboardRequest),
        name: .openDashboard,
        object: nil
    )
}

@objc private func handleDashboardRequest() {
    showDashboard()
}

// Add notification name
extension Notification.Name {
    static let openDashboard = Notification.Name("openDashboard")
}
```

Call `observeDashboardRequest()` in `StatusBarController.init()`.

In the popover view, the "open dashboard" button posts this notification:
```swift
NotificationCenter.default.post(name: .openDashboard, object: nil)
```

**Step 4: Build and test manually**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) build 2>&1 | tail -3
```

**Step 5: Run unit tests** (ensure nothing broke)

```bash
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

**Step 6: Commit**

```
refactor(app): migrate from MenuBarExtra to StatusBarController

Replaces SwiftUI MenuBarExtra with AppKit NSStatusItem for full control
over click behavior. Menu bar icon rendering uses existing MenuBarRenderer.
```

---

## Phase 5: Dashboard Window

### Task 12: Build DashboardView

**Files:**
- Replace: `TokenEaterApp/DashboardView.swift` (placeholder from Task 10)

**Step 1: Build the full DashboardView**

```swift
// TokenEaterApp/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradient(baseColors: backgroundColors)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                dashboardHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        // Hero: Session ring
                        heroSection

                        // Satellite rings: Weekly + model-specific
                        satelliteSection

                        // Pacing
                        if let pacing = usageStore.pacingResult {
                            pacingSection(pacing: pacing)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 650, height: 550)
        .onAppear {
            if settingsStore.hasCompletedOnboarding, usageStore.lastUpdate == nil {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            } else {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            }
        }
    }

    // MARK: - Background colors based on pacing zone

    private var backgroundColors: [Color] {
        switch usageStore.pacingZone {
        case .chill:
            return [Color(hex: "0a0a1a"), Color(hex: "0a1428")]
        case .onTrack:
            return [Color(hex: "0a0a1a"), Color(hex: "141428")]
        case .hot:
            return [Color(hex: "1a0a0a"), Color(hex: "281414")]
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("TokenEater")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            if usageStore.planType != .unknown {
                Text(usageStore.planType.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(planBadgeColor.opacity(0.3))
                    .clipShape(Capsule())
            }

            Spacer()

            if usageStore.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            if let date = usageStore.lastUpdate {
                Text(String(format: String(localized: "menubar.updated"), date.formatted(.relative(presentation: .named))))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Button {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var planBadgeColor: Color {
        switch usageStore.planType {
        case .max: return .purple
        case .pro: return .blue
        case .free: return .gray
        case .unknown: return .clear
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            // Particles
            ParticleField(
                particleCount: 25,
                speed: Double(usageStore.fiveHourPct) / 100.0,
                color: gaugeColor(for: usageStore.fiveHourPct),
                radius: 130
            )
            .frame(width: 280, height: 280)

            VStack(spacing: 4) {
                RingGauge(
                    percentage: usageStore.fiveHourPct,
                    gradient: gaugeGradient(for: usageStore.fiveHourPct),
                    size: 200,
                    glowColor: gaugeColor(for: usageStore.fiveHourPct),
                    glowRadius: 8
                )
                .overlay {
                    VStack(spacing: 2) {
                        GlowText(
                            "\(usageStore.fiveHourPct)%",
                            font: .system(size: 42, weight: .black, design: .rounded),
                            color: gaugeColor(for: usageStore.fiveHourPct),
                            glowRadius: 6
                        )
                        Text(String(localized: "metric.session"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        if !usageStore.fiveHourReset.isEmpty {
                            Text(String(format: String(localized: "metric.reset"), usageStore.fiveHourReset))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Satellite Rings

    private var satelliteSection: some View {
        HStack(spacing: 20) {
            satelliteRing(label: String(localized: "metric.weekly"), pct: usageStore.sevenDayPct)
            satelliteRing(label: String(localized: "metric.sonnet"), pct: usageStore.sonnetPct)
            if usageStore.hasOpus {
                satelliteRing(label: "Opus", pct: usageStore.opusPct)
            }
            if usageStore.hasCowork {
                satelliteRing(label: "Cowork", pct: usageStore.coworkPct)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func satelliteRing(label: String, pct: Int) -> some View {
        VStack(spacing: 6) {
            RingGauge(
                percentage: pct,
                gradient: gaugeGradient(for: pct),
                size: 80,
                glowColor: gaugeColor(for: pct),
                glowRadius: 4
            )
            .overlay {
                GlowText(
                    "\(pct)%",
                    font: .system(size: 18, weight: .black, design: .rounded),
                    color: gaugeColor(for: pct),
                    glowRadius: 3
                )
            }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .scaleEffect(1.0) // placeholder for hover animation
    }

    // MARK: - Pacing Section

    private func pacingSection(pacing: PacingResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "pacing.label"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                let sign = pacing.delta >= 0 ? "+" : ""
                GlowText(
                    "\(sign)\(Int(pacing.delta))%",
                    font: .system(size: 20, weight: .black, design: .rounded),
                    color: themeStore.current.pacingColor(for: pacing.zone),
                    glowRadius: 4
                )
            }

            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: themeStore.current.pacingGradient(for: pacing.zone, startPoint: .leading, endPoint: .trailing)
            )

            Text(pacing.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(themeStore.current.pacingColor(for: pacing.zone).opacity(0.8))

            if let resetDate = pacing.resetDate {
                let diff = resetDate.timeIntervalSinceNow
                if diff > 0 {
                    let days = Int(diff) / 86400
                    let hours = (Int(diff) % 86400) / 3600
                    Text(String(format: String(localized: "pacing.reset.countdown"), days, hours))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Theme Helpers

    private func gaugeColor(for pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(for pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}
```

**Step 2: Add Color(hex:) extension if missing**

Check if `Color(hex:)` extension exists. If not, add to `Shared/Extensions/`:

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

**Step 3: Add localization keys**

Add to both `en.lproj` and `fr.lproj`:
```
"pacing.reset.countdown" = "Resets in %dd %dh";  // en
"pacing.reset.countdown" = "Reset dans %dj %dh";  // fr
```

**Step 4: Build and verify visually**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) build 2>&1 | tail -3
```

**Step 5: Commit**

```
feat(ui): build DashboardView with dark premium Power Station design

Hero ring gauge with particles, satellite rings for models,
pacing section with animated bar, glassmorphic cards,
and animated gradient background that shifts with pacing zone.
```

---

## Phase 6: Popover Redesign

### Task 13: Redesign MenuBarPopoverView

**Files:**
- Modify: `TokenEaterApp/MenuBarView.swift`

**Step 1: Redesign the popover**

Refactor `MenuBarPopoverView` with the dark premium style. Key changes:
- Width: 260 → 300px
- Add mini hero ring for Session (~100px)
- Inline mini-rings for Weekly + Sonnet (~40px)
- Add plan badge next to title
- Add "Open Dashboard" button (top-right arrow icon)
- Use RingGauge and PacingBar components
- Keep existing pin/toggle logic
- Keep existing error banner
- Use GlowText for percentages
- Gradient background (static, not animated)

The full refactored view should:
1. Replace the existing metricRow with RingGauge-based displays
2. Use the shared components (RingGauge, PacingBar, GlowText)
3. Add a dashboard button that posts `Notification.Name.openDashboard`
4. Keep all the existing data bindings and functionality

**Step 2: Build and verify**

Manual testing: click menu bar icon, verify popover looks correct.

**Step 3: Run unit tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

**Step 4: Commit**

```
feat(ui): redesign popover with dark premium style

Mini hero ring for session, inline satellite rings, plan badge,
dashboard open button, and shared GlowText/PacingBar components.
```

---

## Phase 7: Polish & Integration

### Task 14: Release build test + final integration

**Step 1: Run all unit tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -5
```

Expected: All tests PASS (including new ProfileModel, UsageStore, SettingsStore tests).

**Step 2: Build Release with Xcode 16.4**

```bash
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -3
```

**Step 3: Full nuke + install test**

Use the nuke + install one-liner from CLAUDE.md to test the complete flow:
- Menu bar icon appears
- Click → popover opens (dark premium design)
- Click dashboard button → dashboard window opens
- Switch setting to "Dashboard" → click menu bar → dashboard opens directly
- All metrics display correctly
- Profile badge shows (Pro/Max)
- Pacing section works
- Opus/Cowork show when available

**Step 4: Commit any fixes**

**Step 5: Final commit if clean**

```
chore: integration polish and release build verification
```

---

## Summary of files

### New files
- `Shared/Models/ProfileModels.swift`
- `Shared/Models/ClickBehavior.swift`
- `Shared/Components/RingGauge.swift`
- `Shared/Components/PacingBar.swift`
- `Shared/Components/AnimatedGradient.swift`
- `Shared/Components/ParticleField.swift`
- `Shared/Components/GlowText.swift`
- `TokenEaterApp/StatusBarController.swift`
- `TokenEaterApp/DashboardView.swift`
- `TokenEaterTests/Fixtures/ProfileResponse+Fixture.swift`
- `TokenEaterTests/ProfileModelTests.swift`
- `TokenEaterTests/UsageRepositoryProfileTests.swift`

### Modified files
- `Shared/Services/Protocols/APIClientProtocol.swift`
- `Shared/Services/APIClient.swift`
- `Shared/Repositories/UsageRepository.swift`
- `Shared/Stores/UsageStore.swift`
- `Shared/Stores/SettingsStore.swift`
- `TokenEaterApp/TokenEaterApp.swift`
- `TokenEaterApp/MenuBarView.swift`
- `TokenEaterApp/SettingsView.swift`
- `TokenEaterTests/Mocks/MockAPIClient.swift`
- `TokenEaterTests/Mocks/MockUsageRepository.swift`
- `TokenEaterTests/UsageStoreTests.swift`
- `TokenEaterTests/SettingsStoreTests.swift`
- Localization files (en + fr)

### Unchanged
- Widget files (reads from shared JSON, no changes needed)
- ThemeStore, ThemeModels (existing theme system reused)
- NotificationService, KeychainService
- MenuBarRenderer (reused by StatusBarController)
