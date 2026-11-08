import Foundation
import os

/// Opt-in simulator diagnostics; records app events without XCTest queries or screenshots.
@MainActor
enum NextFocusPageTiming {
    enum Event: String {
        case factsSaved, completionStateSaved, editorLoaded
        case generationQueued, requestStarted, responseParsed, draftSaved, viewStateReady, cachedDraftUsed
    }

    static func begin(sourceID: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        guard enabled else { return }
        trace = Trace(runID: ProcessInfo.processInfo.environment["GITA_NEXT_FOCUS_TIMING_RUN_ID"] ?? UUID().uuidString,
                      sourceID: sourceID, startedAtDate: Date(), startedAt: ProcessInfo.processInfo.systemUptime,
                      elapsed: ["completionActionStarted": 0])
        do {
            let url = URL.documentsDirectory.appendingPathComponent("NextFocusPageTiming/latest.json")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            Logger(subsystem: "com.haizei.foxgita", category: "next-focus-timing")
                .error("Unable to clear previous page timing diagnostics: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    static func mark(sourceID: UUID, _ event: Event) {
        #if DEBUG && targetEnvironment(simulator)
        guard enabled, var current = trace, current.sourceID == sourceID,
              current.elapsed[event.rawValue] == nil else { return }
        current.elapsed[event.rawValue] = ProcessInfo.processInfo.systemUptime - current.startedAt
        trace = current
        if event == .viewStateReady {
            do {
                let directory = URL.documentsDirectory.appendingPathComponent("NextFocusPageTiming", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(current).write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
            } catch {
                Logger(subsystem: "com.haizei.foxgita", category: "next-focus-timing")
                    .error("Unable to save page timing diagnostics: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    static func preparedDraftReady(sourceID: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        if trace?.sourceID == sourceID, trace?.elapsed[Event.generationQueued.rawValue] == nil {
            mark(sourceID: sourceID, .cachedDraftUsed)
        }
        mark(sourceID: sourceID, .viewStateReady)
        #endif
    }

    static func setModel(sourceID: UUID, model: String) {
        #if DEBUG && targetEnvironment(simulator)
        guard enabled, trace?.sourceID == sourceID else { return }
        trace?.model = model
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private struct Trace: Codable {
        var runID: String
        var sourceID: UUID
        var startedAtDate: Date
        var startedAt: Double
        var elapsed: [String: Double]
        var model: String? = nil
    }
    private static var trace: Trace?
    private static var enabled: Bool {
        PracticeTestEnvironment.isActive && ProcessInfo.processInfo.arguments.contains("-NextFocusPageTiming")
    }
    #endif
}
