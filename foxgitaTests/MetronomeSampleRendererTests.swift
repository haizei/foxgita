import Testing
@testable import foxgita

struct MetronomeSampleRendererTests {
    @Test func activeTailStaysStableAndMuteDoesNotMoveQueuedBeatOrCutoff() {
        let output = MetronomeSampleRenderer(sampleRate: 44_100)
        output.installSamples([[0.2, 0.2, 0.2, 0.2], [0.4], [0.8, 0.8], [0.9]])
        output.start()
        output.configure(preset: 0, volume: 0.5, strongBeatBoost: true, muted: false)
        #expect(output.schedule(frame: 0, role: .main, kind: .weak))
        var first = [Float](repeating: 0, count: 1)
        first.withUnsafeMutableBufferPointer { output.render(into: $0.baseAddress!, startingAt: 0, count: 1) }
        output.configure(preset: 1, volume: 0.5, strongBeatBoost: true, muted: true)
        #expect(output.schedule(frame: 4, role: .main, kind: .weak))
        var muted = [Float](repeating: 0, count: 1)
        muted.withUnsafeMutableBufferPointer { output.render(into: $0.baseAddress!, startingAt: 1, count: 1) }
        output.configure(preset: 1, volume: 0.5, strongBeatBoost: true, muted: false)
        output.setCutoff(5)
        var rest = [Float](repeating: 0, count: 5)
        rest.withUnsafeMutableBufferPointer { output.render(into: $0.baseAddress!, startingAt: 2, count: 5) }
        #expect(abs(first[0] - 0.09) < 0.0001)
        #expect(muted == [0])
        #expect(abs(rest[0] - 0.09) < 0.0001 && abs(rest[1] - 0.09) < 0.0001)
        #expect(abs(rest[2] - 0.36) < 0.0001)
        #expect(rest[3] == 0 && rest[4] == 0)
    }
    @Test func queuedClickUsesPresetChosenBeforeItBecomesAudible() {
        let output = MetronomeSampleRenderer(sampleRate: 44_100)
        output.installSamples([[0.2, 0.2], [0.4, 0.4], [0.7, 0.7], [0.8, 0.8]])
        output.start()
        output.configure(preset: 0, volume: 1, strongBeatBoost: true, muted: false)
        #expect(output.schedule(frame: 4, role: .main, kind: .weak))
        var first = [Float](repeating: 0, count: 2)
        first.withUnsafeMutableBufferPointer { output.render(into: $0.baseAddress!, startingAt: 0, count: 2) }
        output.configure(preset: 1, volume: 1, strongBeatBoost: true, muted: false)
        var second = [Float](repeating: 0, count: 6)
        second.withUnsafeMutableBufferPointer { output.render(into: $0.baseAddress!, startingAt: 2, count: 6) }
        #expect(first == [0, 0])
        #expect(second[0] == 0 && second[1] == 0)
        #expect(abs(second[2] - 0.63) < 0.0001)
        #expect(abs(second[3] - 0.63) < 0.0001)
        #expect(second[4] == 0 && second[5] == 0)
    }
}
