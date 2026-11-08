import Foundation
import Testing

@testable import foxgita

@MainActor struct TabLayoutBenchmarkTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_LAYOUT_DIR"] != nil))
  func matchedInputs() throws {
    let dir = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GITA_LAYOUT_DIR"]))
    for name in ["independent", "solo", "full", "scale", "smoke", "clean"] {
      let data = try Data(contentsOf: dir.appendingPathComponent(name + ".png"))
      var times: [Double] = []
      for run in 0..<4 {
        let start = ProcessInfo.processInfo.systemUptime
        let pages = try ScoreImportSelection.images([data]).pages
        let draft = try LocalTabReader.draft(pages: pages)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        if run > 0 { times.append(elapsed) }
        if run == 0 {
          for (i, bar) in draft.score.bars.enumerated() {
            let row = try #require(draft.localReadings?[bar.id])
            let json = try JSONEncoder().encode(row)
            print(
              "TABROW \(name) \(i+1) \(bar.source?.box ?? []) |\(String(decoding:json,as:UTF8.self))"
            )
          }
        }
      }
      print("TABTIME \(name) \(times)")
    }
  }
}
