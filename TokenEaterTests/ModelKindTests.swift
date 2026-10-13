import Testing
import Foundation

@Suite("ModelKind")
struct ModelKindTests {

    // MARK: - Opus version mapping

    /// Claude 5 generation IDs carry no minor suffix ("claude-opus-5") and must
    /// not be absorbed by the bare-opus fallback into a 4.x label (#259).
    @Test func opus5IsRecognised() {
        #expect(ModelKind(rawModel: "claude-opus-5") == .opus5)
        #expect(ModelKind(rawModel: "claude-opus-5[1m]") == .opus5)
        #expect(ModelKind(rawModel: "opus-5") == .opus5)
        #expect(ModelKind.opus5.displayName == "Opus 5")
    }

    /// Opus 5.5 contains "opus-5" and was folded into Opus 5 before it had its
    /// own kind; it must get its own label.
    @Test func opus55IsRecognised() {
        #expect(ModelKind(rawModel: "claude-opus-5-5") == .opus55)
        #expect(ModelKind(rawModel: "claude-opus-5-5[1m]") == .opus55)
        #expect(ModelKind(rawModel: "opus-5.5") == .opus55)
        #expect(ModelKind.opus55.displayName == "Opus 5.5")
    }

    @Test func opus48IsRecognised() {
        #expect(ModelKind(rawModel: "claude-opus-4-8") == .opus48)
        #expect(ModelKind(rawModel: "claude-opus-4-8[1m]") == .opus48)
        #expect(ModelKind(rawModel: "opus-4.8") == .opus48)
    }

    @Test func opus47IsRecognised() {
        #expect(ModelKind(rawModel: "claude-opus-4-7") == .opus47)
        #expect(ModelKind(rawModel: "opus-4.7") == .opus47)
    }

    @Test func opus46IsRecognised() {
        #expect(ModelKind(rawModel: "claude-opus-4-6") == .opus46)
        #expect(ModelKind(rawModel: "opus-4.6") == .opus46)
    }

    /// A 4.x minor without its own case stays in the 4.x generation instead of
    /// being absorbed by the bare-opus fallback into the Opus 5 bucket.
    @Test func unknownOpus4MinorStaysInGeneration4() {
        #expect(ModelKind(rawModel: "claude-opus-4-5") == .opus48)
        #expect(ModelKind(rawModel: "claude-opus-4-5-20251101") == .opus48)
    }

    /// 4.5-era ids end in "-4-5", so they must never match a 5.x check.
    @Test func claude45IdsNeverLandInA5xBucket() {
        let fiveX: Set<ModelKind> = [.opus55, .opus5, .sonnet55, .sonnet5]
        for id in ["claude-opus-4-5", "claude-opus-4-5-20251101", "claude-sonnet-4-5",
                   "claude-sonnet-4-5-20250929", "claude-haiku-4-5", "claude-haiku-4-5-20251001"] {
            #expect(!fiveX.contains(ModelKind(rawModel: id)), "\(id)")
        }
    }

    /// The bare "opus" alias appears in JSONL for the default model and must not
    /// fall through to `.other`; it maps to the current shipping Opus version.
    @Test func bareOpusAliasMapsToCurrentVersion() {
        #expect(ModelKind(rawModel: "opus") == .opus55)
    }

    // MARK: - Fable

    /// Fable 5 must not fall through to `.other` (#199); it is its own family,
    /// not an Opus variant.
    @Test func fableIsRecognised() {
        #expect(ModelKind(rawModel: "claude-fable-5") == .fable)
        #expect(ModelKind(rawModel: "claude-fable-5[1m]") == .fable)
        #expect(ModelKind(rawModel: "claude-fable-5-1") == .fable)
        #expect(ModelKind(rawModel: "fable") == .fable)
    }

    /// One kind covers every Fable release, so its label must not claim a
    /// version: "Fable 5" was wrong for Fable 5.1 traffic.
    @Test func fableLabelCarriesNoVersion() {
        #expect(ModelKind(rawModel: "claude-fable-5-1").displayName == "Fable")
        #expect(ModelKind(rawModel: "claude-fable-5").displayName == "Fable")
    }

    @Test func fableIsItsOwnFamily() {
        #expect(ModelKind.fable.family == .fable)
        #expect(ModelKind.fable.displayName == "Fable")
        #expect(ModelFamily.fable.displayName == "Fable")
        #expect(ModelFamily.allCases.contains(.fable))
    }

    // MARK: - Other families

    /// Sonnet 5 gets a versioned label instead of collapsing into the generic
    /// legacy "Sonnet" bucket (#261).
    @Test func sonnet5IsRecognised() {
        #expect(ModelKind(rawModel: "claude-sonnet-5") == .sonnet5)
        #expect(ModelKind(rawModel: "claude-sonnet-5[1m]") == .sonnet5)
        #expect(ModelKind.sonnet5.displayName == "Sonnet 5")
        #expect(ModelKind.sonnet5.family == .sonnet)
    }

    @Test func sonnet55IsRecognised() {
        #expect(ModelKind(rawModel: "claude-sonnet-5-5") == .sonnet55)
        #expect(ModelKind(rawModel: "claude-sonnet-5-5[1m]") == .sonnet55)
        #expect(ModelKind(rawModel: "sonnet-5.5") == .sonnet55)
        #expect(ModelKind.sonnet55.displayName == "Sonnet 5.5")
        #expect(ModelKind.sonnet55.family == .sonnet)
    }

    @Test func sonnetAndHaiku() {
        #expect(ModelKind(rawModel: "claude-sonnet-4-6") == .sonnet)
        #expect(ModelKind(rawModel: "claude-sonnet-4-5-20250929") == .sonnet)
        #expect(ModelKind(rawModel: "claude-haiku-4-5") == .haiku)
        #expect(ModelKind(rawModel: "claude-haiku-4-5-20251001") == .haiku)
        #expect(ModelKind.haiku.displayName == "Haiku")
    }

    /// The ids Claude Code logs today, each in its own bucket.
    @Test func currentClaudeCodeLineup() {
        #expect(ModelKind(rawModel: "claude-opus-5-5") == .opus55)
        #expect(ModelKind(rawModel: "claude-sonnet-5-5") == .sonnet55)
        #expect(ModelKind(rawModel: "claude-fable-5-1") == .fable)
        #expect(ModelKind(rawModel: "claude-haiku-4-5-20251001") == .haiku)
    }

    @Test func unknownModelFallsToOther() {
        #expect(ModelKind(rawModel: "gpt-5") == .other)
        #expect(ModelKind(rawModel: "") == .other)
    }

    // MARK: - Family folding

    @Test func everyOpusVersionFoldsIntoOpusFamily() {
        #expect(ModelKind.opus55.family == .opus)
        #expect(ModelKind.opus5.family == .opus)
        #expect(ModelKind.opus48.family == .opus)
        #expect(ModelKind.opus47.family == .opus)
        #expect(ModelKind.opus46.family == .opus)
    }

    @Test func displayNameMatchesVersion() {
        #expect(ModelKind.opus48.displayName == "Opus 4.8")
    }

    @Test func stackOrderContainsEveryCase() {
        #expect(Set(ModelKind.stackOrder) == Set(ModelKind.allCases))
        #expect(ModelKind.stackOrder.count == ModelKind.allCases.count)
    }
}
