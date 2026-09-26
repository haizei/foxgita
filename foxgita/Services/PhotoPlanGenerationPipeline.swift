import CryptoKit
import Foundation
@preconcurrency import UIKit

enum PreparedImageQuality: String, Equatable, Sendable {
    case standard
    case highReadability
}

enum PreparedImageSourceKind: String, Equatable, Sendable {
    case camera
    case photoLibrary
}

struct PreparedImageAsset: Equatable, Sendable {
    let id: String
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let quality: PreparedImageQuality
    let sourceKind: PreparedImageSourceKind
    let fingerprint: String

    nonisolated var byteCount: Int { jpegData.count }
}

protocol PhotoPlanImagePreparing: Sendable {
    func prepare(_ sourceImages: [Data]) async throws -> [PreparedImageAsset]
}

enum PhotoPlanGenerationError: Error, Equatable {
    case noImages
    case tooManyImages
    case noUsableImages
    case payloadTooLarge
}

enum PhotoPlanGenerationStage: Int, Sendable {
    case preparing, requesting, validating
}

struct PhotoPlanGenerationRequest: Sendable {
    let sourceImages: [Data]
    let fallbackCategory: PracticeCategory
    let credentials: RuntimeCredentials
    let invocationID: UUID
    let sourceKind: PreparedImageSourceKind
    let quality: PreparedImageQuality

    init(
        sourceImages: [Data],
        fallbackCategory: PracticeCategory,
        credentials: RuntimeCredentials,
        invocationID: UUID,
        sourceKind: PreparedImageSourceKind = .photoLibrary,
        quality: PreparedImageQuality = .standard
    ) {
        self.sourceImages = sourceImages
        self.fallbackCategory = fallbackCategory
        self.credentials = credentials
        self.invocationID = invocationID
        self.sourceKind = sourceKind
        self.quality = quality
    }
}

/// The only image conversion point for the photo-plan Recipe.  It runs off the
/// view's main actor and produces a bounded, session-only JPEG payload.
struct DefaultPhotoPlanImagePreparer: PhotoPlanImagePreparing {
    nonisolated static let standardMaxEdge: CGFloat = 1024
    nonisolated static let highReadabilityMaxEdge: CGFloat = 1280
    nonisolated static let maximumBytesPerImage = 1_000_000
    nonisolated static let maximumTotalBytes = 2_500_000
    nonisolated static let minimumQuality: CGFloat = 0.55

    let quality: PreparedImageQuality
    let sourceKind: PreparedImageSourceKind

    init(
        quality: PreparedImageQuality = .standard,
        sourceKind: PreparedImageSourceKind
    ) {
        self.quality = quality
        self.sourceKind = sourceKind
    }

    nonisolated func prepare(_ sourceImages: [Data]) async throws -> [PreparedImageAsset] {
        let quality = quality
        let sourceKind = sourceKind
        return try await withThrowingTaskGroup(of: [PreparedImageAsset].self) { group in
            group.addTask(priority: .userInitiated) {
                try Task.checkCancellation()
            let maxEdge = quality == .highReadability
                ? Self.highReadabilityMaxEdge
                : Self.standardMaxEdge
                var assets: [PreparedImageAsset] = []
                for source in sourceImages {
                    try Task.checkCancellation()
                    if let asset = Self.prepareOne(source, maxEdge: maxEdge, quality: quality, sourceKind: sourceKind) {
                        assets.append(asset)
                    }
                }
                try Task.checkCancellation()
                guard !assets.isEmpty else { throw PhotoPlanGenerationError.noUsableImages }
                guard assets.reduce(0, { $0 + $1.byteCount }) <= Self.maximumTotalBytes else {
                    throw PhotoPlanGenerationError.payloadTooLarge
                }
                return assets
            }
            guard let result = try await group.next() else { throw PhotoPlanGenerationError.noUsableImages }
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func prepareOne(
        _ source: Data,
        maxEdge: CGFloat,
        quality: PreparedImageQuality,
        sourceKind: PreparedImageSourceKind
    ) -> PreparedImageAsset? {
        guard let image = UIImage(data: source), let cgImage = image.cgImage else { return nil }
        let original = CGSize(width: cgImage.width, height: cgImage.height)
        if original.width <= maxEdge, original.height <= maxEdge, source.count <= maximumBytesPerImage {
            return makeAsset(
                jpeg: source,
                size: original,
                source: source,
                quality: quality,
                sourceKind: sourceKind
            )
        }
        let scale = min(1, maxEdge / max(original.width, original.height))
        let target = CGSize(width: max(1, floor(original.width * scale)), height: max(1, floor(original.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }

        var jpegQuality: CGFloat = 0.68
        var jpeg = rendered.jpegData(compressionQuality: jpegQuality)
        while let data = jpeg, data.count > maximumBytesPerImage, jpegQuality > minimumQuality {
            jpegQuality = max(minimumQuality, jpegQuality - 0.05)
            jpeg = rendered.jpegData(compressionQuality: jpegQuality)
        }
        guard let jpeg, jpeg.count <= maximumBytesPerImage else { return nil }
        return makeAsset(
            jpeg: jpeg,
            size: target,
            source: source,
            quality: quality,
            sourceKind: sourceKind
        )
    }

    nonisolated private static func makeAsset(
        jpeg: Data,
        size: CGSize,
        source: Data,
        quality: PreparedImageQuality,
        sourceKind: PreparedImageSourceKind
    ) -> PreparedImageAsset {
        let fingerprint = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        return PreparedImageAsset(
            id: UUID().uuidString,
            jpegData: jpeg,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            quality: quality,
            sourceKind: sourceKind,
            fingerprint: fingerprint
        )
    }
}

actor PhotoPlanImageSession {
    private var assetsBySourceFingerprint: [String: [PreparedImageAsset]] = [:]

    func preparedAssets(
        for sourceImages: [Data],
        quality: PreparedImageQuality,
        sourceKind: PreparedImageSourceKind
    ) -> [PreparedImageAsset]? {
        assetsBySourceFingerprint[Self.cacheKey(for: sourceImages, quality: quality, sourceKind: sourceKind)]
    }

    func store(
        _ assets: [PreparedImageAsset],
        for sourceImages: [Data],
        quality: PreparedImageQuality,
        sourceKind: PreparedImageSourceKind
    ) {
        assetsBySourceFingerprint[Self.cacheKey(for: sourceImages, quality: quality, sourceKind: sourceKind)] = assets
    }

    func release() {
        assetsBySourceFingerprint.removeAll(keepingCapacity: false)
    }

    private static func fingerprint(for sourceImages: [Data]) -> String {
        var hasher = SHA256()
        for image in sourceImages {
            var count = UInt64(image.count).bigEndian
            withUnsafeBytes(of: &count) { hasher.update(data: Data($0)) }
            hasher.update(data: image)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheKey(
        for sourceImages: [Data],
        quality: PreparedImageQuality,
        sourceKind: PreparedImageSourceKind
    ) -> String {
        "\(fingerprint(for: sourceImages))|\(quality.rawValue)|\(sourceKind.rawValue)"
    }
}

struct PhotoPlanGenerationPipeline: Sendable {
    let session: PhotoPlanImageSession
    let preparer: any PhotoPlanImagePreparing
    let runner: any ImagePlanRunning
    let log: any AIInvocationRecording
    let onStage: @Sendable (PhotoPlanGenerationStage) async -> Void

    init(
        session: PhotoPlanImageSession,
        preparer: any PhotoPlanImagePreparing,
        runner: any ImagePlanRunning,
        log: any AIInvocationRecording = EmptyAIInvocationLog(),
        onStage: @escaping @Sendable (PhotoPlanGenerationStage) async -> Void = { _ in }
    ) {
        self.session = session
        self.preparer = preparer
        self.runner = runner
        self.log = log
        self.onStage = onStage
    }

    func generate(_ request: PhotoPlanGenerationRequest) async throws -> AIPracticeDraft {
        guard !request.sourceImages.isEmpty else { throw PhotoPlanGenerationError.noImages }
        guard request.sourceImages.count <= 3 else { throw PhotoPlanGenerationError.tooManyImages }

        let preparationStartedAt = Date()
        await onStage(.preparing)
        let assets: [PreparedImageAsset]
        if let cached = await session.preparedAssets(
            for: request.sourceImages,
            quality: request.quality,
            sourceKind: request.sourceKind
        ) {
            assets = cached
        } else {
            let prepared: [PreparedImageAsset]
            do {
                prepared = try await preparer.prepare(request.sourceImages)
            } catch {
                await recordPreparationFailure(request, startedAt: preparationStartedAt)
                throw error
            }
            try Task.checkCancellation()
            await session.store(
                prepared,
                for: request.sourceImages,
                quality: request.quality,
                sourceKind: request.sourceKind
            )
            assets = prepared
        }

        let preparationMs = max(0, Int(Date().timeIntervalSince(preparationStartedAt) * 1_000))
        let modelStartedAt = Date()
        try Task.checkCancellation()
        await onStage(.requesting)
        do {
            let draft = try await runner.runImagePlan(
            imageJPEGData: assets.map(\.jpegData),
            fallbackCategory: request.fallbackCategory,
            credentials: request.credentials,
            invocationID: request.invocationID
            )
            try Task.checkCancellation()
            await onStage(.validating)
            await log.recordPerformance(
                invocationID: request.invocationID.uuidString,
                performance: AIInvocationPerformance(
                    imagePreparationMs: preparationMs,
                    preparedImageBytes: assets.reduce(0) { $0 + $1.byteCount },
                    preparedImageCount: assets.count,
                    modelWaitMs: max(0, Int(Date().timeIntervalSince(modelStartedAt) * 1_000)),
                    firstResponseMs: nil,
                    imageSourceKind: request.sourceKind.rawValue
                )
            )
            return draft
        } catch {
            await log.recordPerformance(
                invocationID: request.invocationID.uuidString,
                performance: AIInvocationPerformance(
                    imagePreparationMs: preparationMs,
                    preparedImageBytes: assets.reduce(0) { $0 + $1.byteCount },
                    preparedImageCount: assets.count,
                    modelWaitMs: max(0, Int(Date().timeIntervalSince(modelStartedAt) * 1_000)),
                    firstResponseMs: nil,
                    imageSourceKind: request.sourceKind.rawValue
                )
            )
            throw error
        }
    }

    private func recordPreparationFailure(_ request: PhotoPlanGenerationRequest, startedAt: Date) async {
        let skill = SkillDefinition.planFromImage
        await log.record(AIInvocationRecordInput(
            id: request.invocationID.uuidString,
            skillId: skill.id,
            skillVersion: skill.version,
            model: request.credentials.model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            status: .failure,
            errorType: .transport,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: .failed,
            runtime: RuntimeKind.messages.rawValue,
            executionState: .failed,
            performance: AIInvocationPerformance(
                imagePreparationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
                preparedImageBytes: nil,
                preparedImageCount: nil,
                modelWaitMs: nil,
                firstResponseMs: nil,
                imageSourceKind: request.sourceKind.rawValue
            )
        ))
    }
}
