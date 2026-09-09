import Foundation
import Testing
@testable import foxgita

struct AIPlatformContractTests {
    @Test func executionStateAllowsOnlyDeclaredForwardTransitions() {
        #expect(AIExecutionState.created.canTransition(to: .fetching))
        #expect(AIExecutionState.fetching.canTransition(to: .fenced))
        #expect(AIExecutionState.executing.canTransition(to: .validating))
        #expect(AIExecutionState.awaitingApproval.canTransition(to: .applying))
        #expect(!AIExecutionState.created.canTransition(to: .applying))
        #expect(!AIExecutionState.completed.canTransition(to: .executing))
    }

    @Test func recipeKeepsRuntimeNeedsSeparateFromDomain() {
        let recipe = RecipeDefinition(
            id: "practice.next_session",
            family: "practice.plan",
            version: "1.0.0",
            title: "下次练习安排",
            fetchPolicy: .empty,
            outputSchemaID: "practice-plan.v1",
            runtimeRequirements: .messagesOnly,
            approvalPolicy: .hostRequired,
            timeoutSeconds: 60,
            allowsFormatRepair: true
        )
        #expect(recipe.runtimeRequirements.requiresDurability == false)
        #expect(recipe.approvalPolicy == .hostRequired)
    }
}
