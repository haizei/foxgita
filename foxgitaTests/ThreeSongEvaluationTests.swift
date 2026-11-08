import Foundation
import Testing

@testable import foxgita

@MainActor struct ThreeSongEvaluationTests {
  private struct Input: Decodable { let name: String }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func frozenReaderOnUserPages() throws {
    let dir = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"]))
    let inputs = try JSONDecoder().decode(
      [Input].self, from: Data(contentsOf: dir.appendingPathComponent("inputs.json")))
    for item in inputs {
      let bytes = try Data(contentsOf: dir.appendingPathComponent(item.name))
      var times: [Double] = []
      for run in 0..<4 {
        let start = ProcessInfo.processInfo.systemUptime
        let selection = try ScoreImportSelection.images([bytes])
        let draft = try LocalTabReader.draft(pages: selection.pages)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        if run > 0 { times.append(elapsed) }
        if run == 0 {
          for (index, bar) in draft.score.bars.enumerated() {
            let reading = try #require(draft.localReadings?[bar.id])
            let encoded = String(decoding: try JSONEncoder().encode(reading), as: UTF8.self)
            print("SONGROW \(item.name) \(index+1) \(bar.source?.box ?? []) |\(encoded)")
          }
          print("SONGNOTES \(item.name) \(draft.score.soundingEvents.count)")
          let readings = Array(draft.localReadings?.values ?? [:].values)
          let unknown = readings.flatMap(\.attacks).flatMap(\.marks).filter { $0.contains("?") }
            .count
          let pitchless = readings.flatMap(\.attacks).flatMap(\.marks).filter {
            $0.hasPrefix("x") || $0 == "↑" || $0 == "↓"
          }.count
          let unbound = readings.flatMap(\.attacks).filter { $0.diagramBinding == nil }.flatMap(\.marks).filter {
            $0.hasPrefix("x") || $0 == "↑" || $0 == "↓"
          }.count
          let timing = readings.flatMap(\.attacks).filter {
            $0.length == 0 || $0.durationNeedsReview == true
          }.count
          let covered = draft.score.bars.count(where: draft.hasReviewedCoverage)
          let musicValid = (try? draft.score.validate()) != nil
          let audit: [String: Any] = [
            "coveredMeasures": covered, "measures": draft.score.bars.count,
            "structurallyValid": musicValid, "unresolvedMarks": unknown,
            "marksWithoutFingering": pitchless, "rhythmNeedsReview": timing,
            "unboundPitchMarks": unbound,
            "diagramBoundAttacks": readings.flatMap(\.attacks).count(where: { $0.diagramBinding != nil }),
            "recognitionDataComplete": musicValid && covered == draft.score.bars.count
              && unknown == 0 && unbound == 0 && timing == 0
              && readings.allSatisfy { $0.problem == nil },
          ]
          let auditJSON = try JSONSerialization.data(withJSONObject: audit, options: .sortedKeys)
          print("SONGAUDIT \(item.name) |\(String(decoding:auditJSON,as:UTF8.self))")

          #expect(!draft.isConfirmed)
          // Export system previews only for examining what the frozen layout detected.
          let output = dir.appendingPathComponent(item.name + ".preview", isDirectory: true)
          try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
          try selection.pages[0].write(to: output.appendingPathComponent("normalized-page.jpg"))
          try JSONEncoder().encode(TabDiagramReader.diagrams(page: selection.pages[0])).write(
            to: output.appendingPathComponent("diagrams.json"))
          try JSONEncoder().encode(draft).write(
            to: output.appendingPathComponent("score-candidate.json"))
          for system in ScoreSystemImageSlicer.slices(
            page: selection.pages[0], number: 1, tabOnly: true)
          {
            try system.image.write(to: output.appendingPathComponent("system-\(system.number).jpg"))
          }
        }
      }
      print("SONGTIME \(item.name) \(times)")
    }
    let groups: [(String, String, Int)] = [("晴天C", "晴天-谱子", 60), ("晴天G", "晴天-G调", 52), ("断了的弦", "断了的弦-", 70), ("知足", "知足-", 61)]
    for (label, prefix, expectedMeasures) in groups {
      let parts = inputs.filter { $0.name.hasPrefix(prefix) }.sorted { $0.name < $1.name }
      guard !parts.isEmpty else { continue }
      let data = try parts.map { try Data(contentsOf: dir.appendingPathComponent($0.name)) }
      var times: [Double] = []
      for run in 0..<4 {
        let start = ProcessInfo.processInfo.systemUptime
        let selection = try ScoreImportSelection.images(data)
        let combined = try LocalTabReader.draft(pages: selection.pages)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        if run > 0 { times.append(elapsed) }
        if run == 0 {
          let readings = Array(combined.localReadings!.values)
          let covered = combined.score.bars.count(where: combined.hasReviewedCoverage)
          let marks = readings.flatMap(\.attacks).flatMap(\.marks)
          let unbound = readings.flatMap(\.attacks).filter { $0.diagramBinding == nil }.flatMap(\.marks)
            .count(where: { $0.hasPrefix("x") || $0 == "↑" || $0 == "↓" })
          let audit: [String: Any] = [
            "pages": parts.count, "measures": combined.score.bars.count, "coveredMeasures": covered,
            "structurallyValid": (try? combined.score.validate()) != nil,
            "soundingEvents": combined.score.soundingEvents.count,
            "unresolvedMarks": marks.count(where: { $0.contains("?") }),
            "marksWithoutFingering": marks.count(where: {
              $0.hasPrefix("x") || $0 == "↑" || $0 == "↓"
            }),
            "rhythmNeedsReview": readings.flatMap(\.attacks).count(where: {
              $0.length == 0 || $0.durationNeedsReview == true
            }),
            "unboundPitchMarks": unbound,
            "diagramBoundAttacks": readings.flatMap(\.attacks).count(where: { $0.diagramBinding != nil }),
            "tempo": combined.score.tempo.bpm, "capo": combined.score.capo,
            "confirmed": combined.isConfirmed,
            "recognitionDataComplete": covered == combined.score.bars.count
              && readings.allSatisfy { $0.problem == nil }
              && unbound == 0 && marks.allSatisfy { !$0.contains("?") },
          ]
          let encoded = try JSONSerialization.data(withJSONObject: audit, options: .sortedKeys)
          print("SONGBUNDLE \(label) |\(String(decoding:encoded,as:UTF8.self))")
          try JSONEncoder().encode(combined).write(
            to: dir.appendingPathComponent("\(label)-combined-candidate.json"))
          #expect(combined.score.bars.count == expectedMeasures)
          #expect(!combined.isConfirmed)
        }
      }
      print("SONGBUNDLETIME \(label) \(times)")
    }
  }
}
