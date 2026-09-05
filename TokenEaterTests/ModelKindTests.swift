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

    /// The bare "opus" alias appears in JSONL for the default model and must not
    /// fall through to `.other`; it maps to the current shipping Opus version.
    @Test func bareOpusAliasMapsToCurrentVersion() {
        #expect(ModelKind(rawModel: "opus") == .opus5)
    }

    // MARK: - Fable

    /// Fable 5 must not fall through to `.other` (#199); it is its own family,
    /// not an Opus variant.
    @Test func fableIsRecognised() {
        #expect(ModelKind(rawModel: "claude-fable-5") == .fable)
        #expect(ModelKind(rawModel: "claude-fable-5[1m]") == .fable)
        #expect(ModelKind(rawModel: "fable") == .fable)
    }

    @Test func fableIsItsOwnFamily() {
        #expect(ModelKind.fable.family == .fable)
        #expect(ModelKind.fable.displayName == "Fable 5")
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

    @Test func sonnetAndHaiku() {
        #expect(ModelKind(rawModel: "claude-sonnet-4-6") == .sonnet)
        #expect(ModelKind(rawModel: "claude-sonnet-4-5-20250929") == .sonnet)
        #expect(ModelKind(rawModel: "claude-haiku-4-5") == .haiku)
    }

    @Test func unknownModelFallsToOther() {
        #expect(ModelKind(rawModel: "gpt-5") == .other)
        #expect(ModelKind(rawModel: "") == .other)
    }

    // MARK: - Family folding

    @Test func everyOpusVersionFoldsIntoOpusFamily() {
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
    }
}
