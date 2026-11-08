import SwiftUI

/// The user chooses the exact strings to sound for a strum. X marks only use their
/// own printed strings, and an omitted string never silently becomes an open string.
nonisolated enum TabChordResolution {
  static func tones(marks: [String], frets: [Int?], tuning: [Int], capo: Int) -> [ScoreTone]? {
    guard !marks.isEmpty, frets.count == 6, tuning.count == 6, (0...12).contains(capo) else {
      return nil
    }
    let strings: [Int]
    if marks == ["↑"] || marks == ["↓"] {
      strings = (1...6).filter { frets[$0 - 1] != nil }
    } else {
      strings = marks.compactMap { $0.hasPrefix("x") ? Int($0.dropFirst()) : nil }
      guard strings.count == marks.count else { return nil }
    }
    guard !strings.isEmpty else { return nil }
    var result: [ScoreTone] = []
    for s in strings {
      guard (1...6).contains(s), let f = frets[s - 1], (0...24).contains(f) else { return nil }
      let pitch = tuning[6 - s] + capo + f
      guard (24...108).contains(pitch) else { return nil }
      result.append(.init(midi: pitch, string: s, fret: f))
    }
    return result
  }
}

struct TabChordCorrection: View {
  @Environment(\.dismiss) var dismiss
  @Binding var bar: ScoreBar
  let reading: TabReading
  let tuning: [Int]
  let capo: Int
  @State private var first = 0
  @State private var last = 0
  @State private var name = ""
  @State private var frets: [Int?] = Array(repeating: nil, count: 6)
  private var newEvents: [ScoreEvent] {
    guard first <= last, reading.attacks.indices.contains(last) else { return [] }
    return (first...last).compactMap { index in
      let a = reading.attacks[index]
      guard !bar.events.contains(where: { $0.tick == a.start * 240 }),
        let tones = TabChordResolution.tones(
          marks: a.effectiveMarks, frets: frets, tuning: tuning, capo: capo)
      else { return nil }
      return .init(
        tick: a.start * 240, duration: a.length * 240, tones: tones,
        chord: name.isEmpty ? nil : name,
        source: bar.source.map { .init(page: $0.page, box: a.box) })
    }
  }
  var body: some View {
    Form {
      Section("和弦在哪些起音生效") {
        TextField("和弦名（可选）", text: $name)
        Stepper("从第\(first+1)组", value: $first, in: 0...last)
        Stepper("到第\(last+1)组", value: $last, in: first...max(first, reading.attacks.count - 1))
        if let source = bar.source { Text("原谱第\(source.page)页 · 第\(bar.number)小节") }
      }
      Section("按原谱确认实际弹奏的弦品") {
        ForEach(0..<6, id: \.self) { i in
          Picker("\(i+1)弦", selection: $frets[i]) {
            Text("不弹／未指定").tag(nil as Int?)
            ForEach(0...24, id: \.self) { Text("\($0)品").tag(Optional($0)) }
          }
        }
        Text("扫弦使用你选中的弦；叉号只使用谱上标出的弦。已经校正的起音会保留。")
      }
      Button("确认并补入\(newEvents.count)组起音") {
        bar.events += newEvents
        dismiss()
      }
      .disabled(newEvents.isEmpty)
    }.navigationTitle("按指法补录")
  }
}
