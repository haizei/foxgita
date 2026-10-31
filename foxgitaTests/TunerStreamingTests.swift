import AVFoundation
import XCTest
@testable import foxgita

nonisolated private final class PitchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TunerPitchEstimate] = []

    func record(_ value: TunerPitchEstimate) -> Int {
        lock.lock(); defer { lock.unlock() }
        values.append(value)
        return values.count
    }
}

final class TunerStreamingTests: XCTestCase {
    func testSilentWindowPreservesItsSampleTimeFormatAndRunIdentity() async {
        let observed = expectation(description: "A timed, non-pitched observation")
        let runID = UUID()
        let worker = TunerPitchWorker(runID: runID) { observation in
            XCTAssertNil(observation.pitch)
            XCTAssertEqual(observation.capturedAt, 12.5)
            XCTAssertEqual(observation.sampleRate, 48_000)
            XCTAssertEqual(observation.runID, runID)
            observed.fulfill()
        }
        worker.consume(buffer(frequency: 0, count: 4096), capturedAt: 12.5)
        await fulfillment(of: [observed], timeout: 1)
    }

    private func buffer(frequency: Double, start: Int = 0, count: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        result.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            result.floatChannelData![0][i] = Float(0.02 * sin(2 * .pi * frequency * Double(start + i) / 48_000))
        }
        return result
    }

    func testLowEIsRecognizedWithinTheFirst110MillisecondsOfInput() async throws {
        let detected = expectation(description: "Low E before 110 ms of PCM")
        detected.assertForOverFulfill = false
        let worker = TunerPitchWorker { observation in
            if let pitch = observation.pitch, abs(1200 * log2(pitch.frequency / 82.4069)) < 4 { detected.fulfill() }
        }
        for block in 0..<5 {
            worker.consume(buffer(frequency: 82.4069, start: block * 1024, count: 1024))
            try await Task.sleep(for: .milliseconds(5))
        }
        await fulfillment(of: [detected], timeout: 0.5)
    }

    func testAudioReceivedDuringBusyAnalysisIsRetainedAndNewestPitchIsDelivered() async {
        let first = expectation(description: "First analysis in flight")
        let followed = expectation(description: "Newest pitch survives worker backpressure")
        followed.assertForOverFulfill = false
        let gate = DispatchSemaphore(value: 0)
        let probe = PitchProbe()
        let higher = 82.4069 * pow(2, 20.0 / 1200)
        let worker = TunerPitchWorker { observation in
            guard let pitch = observation.pitch else { return }
            if probe.record(pitch) == 1 {
                first.fulfill()
                _ = gate.wait(timeout: .now() + 2)
            } else if abs(1200 * log2(pitch.frequency / higher)) < 4 {
                followed.fulfill()
            }
        }
        worker.consume(buffer(frequency: 82.4069, count: 9600))
        await fulfillment(of: [first], timeout: 1)
        for block in 0..<8 {
            worker.consume(buffer(frequency: higher, start: block * 1024, count: 1024))
        }
        gate.signal()
        await fulfillment(of: [followed], timeout: 0.5)
    }
}
