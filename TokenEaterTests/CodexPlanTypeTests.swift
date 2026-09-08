import Testing
import Foundation

@Suite("CodexPlanType")
struct CodexPlanTypeTests {

    @Test("known plans map to their badge")
    func knownPlans() {
        #expect(CodexPlanType(rawPlan: "plus") == .plus)
        #expect(CodexPlanType(rawPlan: "pro") == .pro)
        #expect(CodexPlanType(rawPlan: "prolite") == .proLite)
        #expect(CodexPlanType(rawPlan: "team") == .team)
        #expect(CodexPlanType(rawPlan: "enterprise") == .enterprise)
        #expect(CodexPlanType(rawPlan: "edu_pro") == .edu)
        #expect(CodexPlanType(rawPlan: "free") == .free)
    }

    @Test("matching ignores case and surrounding whitespace")
    func normalisation() {
        #expect(CodexPlanType(rawPlan: "  ProLite ") == .proLite)
        #expect(CodexPlanType(rawPlan: "PRO") == .pro)
    }

    @Test("an unreleased plan keeps its own name instead of disappearing")
    func unknownPlanIsPreserved() {
        let plan = CodexPlanType(rawPlan: "quorum_beta")

        #expect(plan == .other("quorum_beta"))
        #expect(plan.displayLabel == "QUORUM BETA")
    }

    @Test("a missing plan renders as no badge at all")
    func missingPlan() {
        #expect(CodexPlanType(rawPlan: nil) == .unknown)
        #expect(CodexPlanType(rawPlan: "") == .unknown)
        #expect(CodexPlanType(rawPlan: "  ") == .unknown)
        #expect(CodexPlanType(rawPlan: nil).displayLabel.isEmpty)
    }

    @Test("labels are set for every known plan")
    func labels() {
        #expect(CodexPlanType.proLite.displayLabel == "PRO LITE")
        #expect(CodexPlanType.plus.displayLabel == "PLUS")
        #expect(CodexPlanType.enterprise.displayLabel == "ENTERPRISE")
    }

    @Test("the auth state derives the plan from its claim")
    func planFromAuthState() {
        let state = CodexAuthState.chatgpt(accountId: "a", planType: "prolite", expiresAt: nil)
        #expect(state.planType == .proLite)
        #expect(CodexAuthState.notInstalled.planType == .unknown)
    }

    @Test("only a ChatGPT login is trackable")
    func trackability() {
        #expect(CodexAuthState.chatgpt(accountId: nil, planType: nil, expiresAt: nil).isTrackable)
        #expect(!CodexAuthState.apiKeyOnly.isTrackable)
        #expect(!CodexAuthState.noCredentials.isTrackable)
        #expect(!CodexAuthState.notInstalled.isTrackable)
        #expect(CodexAuthState.apiKeyOnly.isInstalled)
        #expect(!CodexAuthState.notInstalled.isInstalled)
    }
}
