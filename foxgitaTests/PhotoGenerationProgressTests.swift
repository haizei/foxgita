import Foundation
import Testing
@testable import foxgita

struct PhotoGenerationProgressTests {
    @Test func stagesAdvanceAndComplete() {
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 0, completed: false) == 0)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 3, completed: false) == 1)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 6, completed: false) == 2)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 1, completed: true) == 2)
        #expect(PhotoGenerationProgress.fraction(elapsed: 6, completed: false) == 0.5)
        #expect(PhotoGenerationProgress.fraction(elapsed: 20, completed: false) == 0.9)
        #expect(PhotoGenerationProgress.fraction(elapsed: 1, completed: true) == 1)
        #expect(PhotoGenerationProgress.captions.count == 3)
    }
}
