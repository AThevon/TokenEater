import Testing
import Foundation

@Suite("ModelKind")
struct ModelKindTests {

    // MARK: - Opus version mapping

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
        #expect(ModelKind(rawModel: "opus") == .opus48)
    }

    // MARK: - Other families

    @Test func sonnetAndHaiku() {
        #expect(ModelKind(rawModel: "claude-sonnet-4-6") == .sonnet)
        #expect(ModelKind(rawModel: "claude-haiku-4-5") == .haiku)
    }

    @Test func unknownModelFallsToOther() {
        #expect(ModelKind(rawModel: "gpt-5") == .other)
        #expect(ModelKind(rawModel: "") == .other)
    }

    // MARK: - Family folding

    @Test func everyOpusVersionFoldsIntoOpusFamily() {
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
