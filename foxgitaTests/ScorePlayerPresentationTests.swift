import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import foxgita

@Suite(.serialized) @MainActor struct ScorePlayerPresentationTests {
    @Test func firstAndRepeatedPresentationAlwaysReceiveTheActualSession() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeStore(repository: InMemoryPracticeRepository(),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = ScoreExercises.melody,library = try ScoreLibrary(directory: folder,profileID: store.scoreProfileID())
        let item = try store.openScorePractice(score: score,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "presentation")
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let driver = PresentationDriver()
        let host = UIHostingController(rootView: PresentationHost(driver: driver))
        let window = UIWindow(windowScene: scene); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        host.view.layoutIfNeeded()
        for _ in 0..<2 {
            driver.appeared = false; driver.dismissed = false
            let audio = PresentationAudio()
            let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: score.fullRange,speed: 1,audio: audio)
            driver.session = ScorePlayerSession(model: model)
            for _ in 0..<100 where !driver.appeared || !audio.running { try await Task.sleep(for: .milliseconds(30)) }
            #expect(driver.appeared,"First presentation must render a real player, not an empty cover.")
            #expect(audio.running)
            driver.session = nil
            for _ in 0..<100 where !driver.dismissed { try await Task.sleep(for: .milliseconds(30)) }
            #expect(driver.dismissed)
            #expect(!audio.running)
            #expect(host.presentedViewController == nil)
        }
    }
}

@Observable @MainActor private final class PresentationDriver {
    var session: ScorePlayerSession?
    var appeared = false
    var dismissed = false
}
private struct PresentationHost: View {
    @Bindable var driver: PresentationDriver
    var body: some View {
        Text("Preparation fixture").fullScreenCover(item: $driver.session,onDismiss: { driver.dismissed = true }) { session in
            ScorePlayerView(model: session.model).onAppear { driver.appeared = true }
        }
    }
}
@MainActor private final class PresentationAudio: ScoreAudioDriving {
    var seconds = 0.0, demoVolume = 0.0, clickVolume = 0.0
    var listening = false, running = false
    var onObservation: ((ScorePitchObservation,Double) -> Void)?
    func start(run: ScoreRun) async throws { running = true }
    func stop() { running = false }
}
