import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import foxgita

/// Runs inside the app host: no extra UI-runner app or personal database required.
@Suite(.serialized) @MainActor struct PracticeDetailRenderTests {
    @Test func practiceNoteToolsRenderAfterReturningFromACover() async throws {
        let schema = Schema(versionedSchema: GitaSchemaV19.self)
        let container = try ModelContainer(for: schema,configurations: [ModelConfiguration(schema: schema,isStoredInMemoryOnly: true)])
        let store = PracticeStore(repository: SwiftDataPracticeRepository(context: container.mainContext),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let item = try store.openScorePractice(score: ScoreExercises.melody,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "detail-render")
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let router = AppRouter()
        let reviews = ReviewJobRunner(store: store,generator: RenderOnlyReview(),videoGenerator: RenderOnlyReview())
        let memory = MemoryStore(repository: SwiftDataMemoryRepository(context: container.mainContext),context: container.mainContext)
        let consent = MemoryConsentCoordinator(store: memory)
        let host = UIHostingController(rootView: NavigationStack {
            PracticeDetailView(itemId: item.id)
        }.environment(store).environment(router).environment(reviews).environment(consent).modelContainer(container))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try ScoreLibrary(directory: folder,profileID: item.profileId)
        let cover = UIHostingController(rootView: NavigationStack {
            ScoreDetailView(score: ScoreExercises.melody,library: library,entry: .tool)
        }.environment(store).environment(router).modelContainer(container))
        cover.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { continuation in host.present(cover,animated: false) { continuation.resume() } }
        await withCheckedContinuation { continuation in cover.dismiss(animated: false) { continuation.resume() } }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(host.presentedViewController == nil)
        #expect(host.view.window != nil)
        #expect(item.deletedAt == nil)
    }
}

private struct RenderOnlyReview: MediaReviewGenerating,VideoDiagnosisGenerating {
    func review(_ context: MediaReviewContext,baseURL: String,model: String,invocationId: String) async throws -> MediaReviewDraft {
        throw MediaReviewGeneratorError.notConfigured
    }
    func diagnose(_ context: MediaReviewContext,baseURL: String,model: String,invocationId: String) async throws -> VideoDiagnosisDraft {
        throw MediaReviewGeneratorError.notConfigured
    }
}
