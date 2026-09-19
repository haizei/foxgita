import Testing
@testable import foxgita

struct AIPlatformBoundaryTests {
    @Test func productionGeneratorsDependOnRecipeRunners() {
        #expect(NextSessionGenerator.dependencyKind == .recipeRunner)
        #expect(ImageStepGenerator.dependencyKind == .recipeRunner)
        #expect(MediaReviewGenerator.dependencyKind == .recipeRunner)
        #expect(VideoDiagnosisGenerator.dependencyKind == .recipeRunner)
    }
}
