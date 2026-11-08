import Foundation

nonisolated enum ScoreExercises {
    static var documents: [ScoreDocument] { [melody, chords, strumming] }

    private static func identity(_ suffix: String) -> UUID { UUID(uuidString: "B17A0000-0000-4000-8000-0000000000" + suffix)! }
    private static func identified(_ document: ScoreDocument, namespace: Int) -> ScoreDocument {
        var result = document
        func id(_ value: Int) -> UUID {
            UUID(uuidString: String(format: "B17A%04X-0000-4000-9000-%012llX", namespace, Int64(value)))!
        }
        for i in result.bars.indices {
            result.bars[i].id = id(i * 1000)
            for j in result.bars[i].events.indices { result.bars[i].events[j].id = id(i * 1000 + j + 1) }
        }
        return result
    }
    private static func tone(_ string: Int, _ fret: Int, finger: Int? = nil) -> ScoreTone {
        let tuning = [40, 45, 50, 55, 59, 64]
        return .init(midi: tuning[6 - string] + fret, string: string, fret: fret, finger: fret == 0 ? 0 : finger)
    }
    static var melody: ScoreDocument {
        let notes = [(6,0),(6,3),(5,0),(5,2),(5,3),(4,0),(4,2),(4,0)]
        let bars = (0..<8).map { bar in
            ScoreBar(number: bar + 1, events: (0..<4).map { beat in
                let n = notes[(bar * 2 + beat) % notes.count]
                return ScoreEvent(tick: beat * 960, duration: 960, tones: [tone(n.0,n.1,finger: n.1 == 3 ? 3 : 1)])
            }, section: bar < 4 ? "第一句" : "第二句")
        }
        return identified(.init(id: identity("01"), versionID: identity("11"), title: "开放弦与旋律", tempo: .init(bpm: 80), bars: bars), namespace: 1)
    }
    static var chords: ScoreDocument {
        let shapes: [(String,[ScoreTone])] = [
            ("C",[tone(5,3,finger:3),tone(4,2,finger:2),tone(3,0),tone(2,1,finger:1),tone(1,0)]),
            ("G",[tone(6,3,finger:2),tone(5,2,finger:1),tone(4,0),tone(3,0),tone(2,0),tone(1,3,finger:3)]),
            ("Am",[tone(5,0),tone(4,2,finger:2),tone(3,2,finger:3),tone(2,1,finger:1),tone(1,0)]),
            ("F",[tone(6,1,finger:1),tone(5,3,finger:3),tone(4,3,finger:4),tone(3,2,finger:2),tone(2,1,finger:1),tone(1,1,finger:1)])
        ]
        let bars = (0..<8).map { i in
            ScoreBar(number: i+1, events: [.init(tick: 0, duration: 3_840, tones: shapes[i%4].1, chord: shapes[i%4].0)], section: i < 4 ? "和弦转换" : "连贯弹奏")
        }
        return identified(.init(id: identity("02"), versionID: identity("12"), title: "C · G · Am · F 和弦转换", tempo: .init(bpm: 72), bars: bars), namespace: 2)
    }
    static var strumming: ScoreDocument {
        let g = [tone(6,3,finger:1),tone(5,5,finger:3),tone(4,5,finger:4)]
        let a = [tone(5,0),tone(4,2,finger:1),tone(3,2,finger:2)]
        let bars = (0..<12).map { i in
            ScoreBar(number: i+1, events: (0..<8).map { beat in
                .init(tick: beat * 480, duration: 480, tones: i % 2 == 0 ? g : a, chord: beat == 0 ? (i % 2 == 0 ? "G5" : "A5") : nil)
            }, section: i < 4 ? "主歌 A" : i < 8 ? "主歌 B" : "副歌")
        }
        return identified(.init(id: identity("03"), versionID: identity("13"), title: "强力和弦与八分扫弦", tempo: .init(bpm: 100), bars: bars), namespace: 3)
    }
}
