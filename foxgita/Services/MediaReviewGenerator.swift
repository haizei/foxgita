import AVFoundation
import Foundation
import UIKit

enum MediaReviewGeneratorError: Error, Equatable {
    case notConfigured
    case fileMissing
    case prepareFailed
    case failed(VisionPracticeError)
}

enum MediaReviewMedia {
    static func isVideo(fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return ext == "mov" || ext == "mp4" || ext == "m4v"
    }
}

protocol MediaImagePreparing: Sendable {
    func jpegImages(fileName: String) throws -> [Data]
}

protocol MediaReviewGenerating: Sendable {
    func review(_ context: MediaReviewContext, baseURL: String, model: String) async throws -> MediaReviewDraft
}

@MainActor
final class MediaReviewGenerator: MediaReviewGenerating {
    private let client: any MediaReviewing
    private let credentials: LLMCredentialsStore
    private let images: any MediaImagePreparing

    init(
        client: any MediaReviewing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer()
    ) {
        self.client = client
        self.credentials = credentials
        self.images = images
    }

    func review(_ context: MediaReviewContext, baseURL: String, model: String) async throws -> MediaReviewDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw MediaReviewGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw MediaReviewGeneratorError.notConfigured
        }

        let jpegs: [Data]
        do {
            let preparer = images
            let name = context.fileName
            jpegs = try await Task.detached { try preparer.jpegImages(fileName: name) }.value
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.prepareFailed
        }
        guard !jpegs.isEmpty else {
            throw MediaReviewGeneratorError.prepareFailed
        }

        do {
            return try await client.generateReview(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageJPEGData: jpegs,
                contextText: Self.contextText(from: context)
            )
        } catch let error as VisionPracticeError {
            throw MediaReviewGeneratorError.failed(error)
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.failed(.transport)
        }
    }

    static func contextText(from context: MediaReviewContext) -> String {
        var lines: [String] = []
        let title = context.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append("任务：\(title)")
        }
        let steps = context.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !steps.isEmpty {
            lines.append("步骤：\(steps.joined(separator: "、"))")
        }
        lines.append("BPM：\(context.bpm)")
        let timeSig = context.timeSig.trimmingCharacters(in: .whitespacesAndNewlines)
        if !timeSig.isEmpty {
            lines.append("拍号：\(timeSig)")
        }
        let note = context.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            lines.append("笔记：\(note)")
        }
        lines.append("时长：\(context.durationSec)秒")
        let isVideo = MediaReviewMedia.isVideo(fileName: context.fileName)
        lines.append("媒介：\(isVideo ? "录像" : "录音")")
        return lines.joined(separator: "\n")
    }
}

struct FileMediaImagePreparer: MediaImagePreparing {
    func jpegImages(fileName: String) throws -> [Data] {
        let url = RecordingStore.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaReviewGeneratorError.fileMissing
        }
        if MediaReviewMedia.isVideo(fileName: fileName) {
            return try Self.videoFrames(url: url)
        }
        return [try Self.waveformJPEG(url: url)]
    }

    private static func videoFrames(url: URL) throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let seconds = durationSeconds(asset)
        let sample = VideoFrameSampler.sampleSeconds(duration: seconds)
        let cap = max(seconds - 0.1, 0)
        let times = sample.map {
            CMTime(seconds: min($0, cap), preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var jpegs: [Data] = []
        for time in times {
            guard let jpeg = frameJPEG(generator: generator, at: time) else { continue }
            jpegs.append(jpeg)
        }
        guard !jpegs.isEmpty else {
            throw MediaReviewGeneratorError.prepareFailed
        }
        if let wave = try? waveformJPEG(url: url) {
            jpegs.append(wave)
        }
        return jpegs
    }

    /// Completion / `load` APIs avoid deprecated `duration` and `copyCGImage`.
    /// The preparer protocol is sync, so we wait once off the async work.
    private static func durationSeconds(_ asset: AVURLAsset) -> Double {
        let box = WaitBox<Double>()
        let lock = DispatchSemaphore(value: 0)
        Task.detached {
            if let time = try? await asset.load(.duration) {
                let value = CMTimeGetSeconds(time)
                if value.isFinite { box.value = value }
            }
            lock.signal()
        }
        lock.wait()
        return box.value ?? 0
    }

    private static func frameJPEG(generator: AVAssetImageGenerator, at time: CMTime) -> Data? {
        let box = WaitBox<CGImage>()
        let lock = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
            box.value = cgImage
            lock.signal()
        }
        lock.wait()
        guard let cgImage = box.value else { return nil }
        return encodedJPEG(UIImage(cgImage: cgImage))
    }

    private final class WaitBox<T>: @unchecked Sendable {
        var value: T?
    }

    private static func waveformJPEG(url: URL) throws -> Data {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw MediaReviewGeneratorError.prepareFailed
        }

        let totalFrames = file.length
        guard totalFrames > 0 else {
            throw MediaReviewGeneratorError.prepareFailed
        }

        let barCount = 200
        var bars = [Float](repeating: 0, count: barCount)
        let format = file.processingFormat
        let framesPerBar = max(1, Int((totalFrames + AVAudioFramePosition(barCount) - 1) / AVAudioFramePosition(barCount)))
        let chunkCapacity = AVAudioFrameCount(min(framesPerBar, 4096))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw MediaReviewGeneratorError.prepareFailed
        }

        for index in 0..<barCount {
            let start = AVAudioFramePosition(index * framesPerBar)
            guard start < totalFrames else { break }
            let end = min(start + AVAudioFramePosition(framesPerBar), totalFrames)
            file.framePosition = start
            var peak: Float = 0
            var remaining = AVAudioFrameCount(end - start)
            while remaining > 0 {
                let request = min(remaining, chunkCapacity)
                do {
                    try file.read(into: buffer, frameCount: request)
                } catch {
                    throw MediaReviewGeneratorError.prepareFailed
                }
                let frames = Int(buffer.frameLength)
                guard frames > 0, let channels = buffer.floatChannelData else { break }
                let channelCount = Int(format.channelCount)
                for frame in 0..<frames {
                    var mixed: Float = 0
                    for channel in 0..<channelCount {
                        mixed += abs(channels[channel][frame])
                    }
                    if channelCount > 0 {
                        mixed /= Float(channelCount)
                    }
                    if mixed > peak { peak = mixed }
                }
                remaining -= buffer.frameLength
                if buffer.frameLength == 0 { break }
            }
            bars[index] = peak
        }

        let size = CGSize(width: 640, height: 200)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            let midY = size.height / 2
            let barWidth = size.width / CGFloat(barCount)
            let maxPeak = max(bars.max() ?? 0, 0.0001)
            for (index, bar) in bars.enumerated() {
                let height = max(1, CGFloat(bar / maxPeak) * (size.height * 0.9))
                let rect = CGRect(
                    x: CGFloat(index) * barWidth,
                    y: midY - height / 2,
                    width: max(barWidth - 0.5, 0.5),
                    height: height
                )
                ctx.cgContext.fill(rect)
            }
        }
        guard let jpeg = encodedJPEG(image) else {
            throw MediaReviewGeneratorError.prepareFailed
        }
        return jpeg
    }

    private static func encodedJPEG(_ image: UIImage) -> Data? {
        guard let raw = image.jpegData(compressionQuality: 1) else { return nil }
        return PracticeImageCodec.jpegData(from: raw)
    }
}
