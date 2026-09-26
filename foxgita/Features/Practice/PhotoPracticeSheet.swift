import PhotosUI
import SwiftUI
@preconcurrency import UIKit

struct PhotoPracticeDraftLifecycle: Equatable {
    enum State: Equatable { case source, generating, pending, committed, abandoned }
    private(set) var state: State = .source

    mutating func begin() { state = .generating }
    mutating func present() { if state == .generating { state = .pending } }
    var allowsCommit: Bool { state == .pending }
    mutating func commit() -> Bool {
        guard allowsCommit else { return false }
        state = .committed
        return true
    }
    mutating func abandon() {
        guard state == .generating || state == .pending else { return }
        state = .abandoned
    }
}

struct PhotoPracticeSheet: View {
    @Environment(\.gitaAIRunner) private var aiRunner
    private enum Phase {
        case source
        case generating
        case preview
    }

    private struct EditStep: Identifiable {
        let id = UUID()
        var text: String
    }

    var fallbackCategory: PracticeCategory
    var baseURL: String
    var model: String
    @Binding var selection: String?
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeStore.self) private var store
    @Environment(AIInvocationStore.self) private var invocationStore
    @State private var phase: Phase = .source
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isGenerating = false
    @State private var generateTask: Task<Void, Never>?
    @State private var confirmTask: Task<Void, Never>?
    @State private var generationId = UUID().uuidString
    @State private var toast: String?
    @State private var entryGate = PracticeEntryGate()
    @State private var submitToken = PracticeEntryToken()
    @State private var approvalGate = PracticeDraftApprovalGate()
    @State private var selectedBlobs: [Data] = []
    @State private var draftCategory: PracticeCategory = .left
    @State private var draftChords: [String] = []
    @State private var appliedTitle = ""
    @State private var appliedMinutes = 0
    @State private var appliedSteps: [String] = []
    @State private var editTitle = ""
    @State private var editMinutes = 10
    @State private var editSteps: [EditStep] = []
    @State private var isSubmitting = false
    @State private var didFinishOutcome = false
    @State private var lifecycle = PhotoPracticeDraftLifecycle()
    @State private var imageSession = PhotoPlanImageSession()
    @State private var selectedSourceKind: PreparedImageSourceKind = .photoLibrary
    @State private var imageQuality: PreparedImageQuality = .standard
    @State private var generationStage: PhotoPlanGenerationStage = .preparing

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text(phase == .source ? "从图片生成练习" : phase == .generating ? "正在生成练习" : "预览练习")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭", action: close)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .disabled(isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Group {
                switch phase {
                case .source:
                    sourceContent
                case .generating:
                    generatingContent
                case .preview:
                    previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GitaTheme.bgDefault)
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast)
                        .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            StillImageCameraPicker(
                isPresented: $isCameraPresented,
                onPicked: beginGeneration(cameraImage:),
                onCancel: {}
            )
            .ignoresSafeArea()
        }
        .onDisappear {
            generateTask?.cancel()
            confirmTask?.cancel()
            Task { await imageSession.release() }
            if (phase == .generating || phase == .preview), !didFinishOutcome {
                invocationStore.setDraftOutcome(id: generationId, outcome: .abandoned, taskId: nil)
                lifecycle.abandon()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isGenerating || isSubmitting)
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("选择图片来源")
                    .font(.system(size: 17, weight: .bold))
                Text("适合乐谱、练习清单和手写内容")
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                sourceCard(
                    title: String(localized: "拍照"),
                    subtitle: String(localized: "立即拍摄纸质内容"),
                    systemImage: "camera.fill",
                    background: GitaTheme.brand50,
                    titleColor: GitaTheme.brand500
                ) {
                    isCameraPresented = true
                }

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    sourceCardLabel(
                        title: String(localized: "相册"),
                        subtitle: String(localized: "选择截图或已有照片"),
                        systemImage: "photo.on.rectangle",
                        background: GitaTheme.bgSubtle,
                        titleColor: GitaTheme.textPrimary
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    beginGeneration(items: items)
                }
            }

            Text("识别完成后先预览和修改，确认后才加入练习")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private var generatingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
                .frame(width: 64, height: 64)
                .background(GitaTheme.brand50)
                .clipShape(Circle())

            Text("正在识别图片内容")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(["正在准备图片", "正在请求模型", "正在校验结果"].enumerated()), id: \.offset) { index, caption in
                    HStack(spacing: 10) {
                        Image(
                            systemName: index <= generationStage.rawValue
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            index <= generationStage.rawValue
                                ? GitaTheme.brand500
                                : GitaTheme.borderSubtle
                        )
                        Text(caption)
                            .font(.system(size: 13, weight: index == generationStage.rawValue ? .semibold : .regular))
                            .foregroundStyle(
                                index <= generationStage.rawValue
                                    ? GitaTheme.textSecondary
                                    : GitaTheme.textTertiary
                            )
                    }
                }
            }

            Spacer()

            Text("完成后进入可编辑预览，不会自动创建练习")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textTertiary)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("请检查图片识别结果，确认后才会加入今日练习")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            TextField("标题", text: $editTitle)
                .font(.system(size: 16, weight: .semibold))
            HStack {
                Button { editMinutes = max(1, editMinutes - 5) } label: { Text("－") }
                Text("\(editMinutes) 分钟")
                Button { editMinutes = min(60, editMinutes + 5) } label: { Text("＋") }
            }
            .font(.system(size: 13, weight: .semibold))
            ForEach($editSteps) { $step in
                HStack {
                    TextField("步骤", text: $step.text)
                    Button("删") { editSteps.removeAll { $0.id == step.id } }
                        .font(.system(size: 13))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if editSteps.count < 12 {
                Button("加一步") { editSteps.append(EditStep(text: "")) }
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Button("重新生成", action: regenerate)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
                .disabled(isSubmitting)
            if imageQuality == .standard, selectedSourceKind != .camera {
                Button("文字不清楚？以高清重新生成") {
                    imageQuality = .highReadability
                    regenerate()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitaTheme.textSecondary)
                .disabled(isSubmitting)
            }
            Button(action: confirm) {
                Text("确认并加入今日练习")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
        .disabled(isSubmitting)
    }

    private func sourceCard(
        title: String,
        subtitle: String,
        systemImage: String,
        background: Color,
        titleColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            sourceCardLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                background: background,
                titleColor: titleColor
            )
        }
        .buttonStyle(.plain)
    }

    private func sourceCardLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        background: Color,
        titleColor: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(titleColor)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(titleColor)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 142)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func beginGeneration(items: [PhotosPickerItem]) {
        guard !isGenerating else { return }
        imageQuality = .standard
        generateTask = Task {
            prepareGeneration()
            do {
                var blobs: [Data] = []
                for item in items.prefix(3) {
                    try Task.checkCancellation()
                    if let data = try await item.loadTransferable(type: Data.self) {
                        blobs.append(data)
                    }
                }
                try await generate(blobs: blobs, sourceKind: .photoLibrary)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                fail(with: error)
            }
        }
    }

    private func beginGeneration(blobs: [Data], sourceKind: PreparedImageSourceKind = .photoLibrary) {
        guard !isGenerating else { return }
        imageQuality = .standard
        generateTask = Task {
            prepareGeneration()
            do {
                try await generate(blobs: blobs, sourceKind: sourceKind)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                fail(with: error)
            }
        }
    }

    private func beginGeneration(cameraImage: UIImage) {
        guard !isGenerating else { return }
        imageQuality = .standard
        generateTask = Task {
            prepareGeneration()
            do {
                let image = cameraImage
                let blobs = try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let jpeg = PracticeImageCodec.jpegData(from: image, maxEdge: 1024, quality: 0.68) else {
                        throw PhotoPlanGenerationError.noUsableImages
                    }
                    return [jpeg]
                }.value
                try Task.checkCancellation()
                try await generate(blobs: blobs, sourceKind: .camera)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                fail(with: error)
            }
        }
    }

    private func prepareGeneration() {
        generationId = UUID().uuidString
        submitToken = PracticeEntryToken()
        phase = .generating
        isGenerating = true
        toast = nil
        generationStage = .preparing
        lifecycle.begin()
    }

    private func generate(blobs: [Data], sourceKind: PreparedImageSourceKind) async throws {
        guard let aiRunner else { throw ImageStepGeneratorError.notConfigured }
        selectedBlobs = blobs
        selectedSourceKind = sourceKind
        let credentialsStore = LLMCredentialsStore()
        guard credentialsStore.isConfigured(baseURL: baseURL, model: model),
              let apiKey = credentialsStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            await recordNotConfigured()
            throw ImageStepGeneratorError.notConfigured
        }
        let log = LiveAIInvocationLog(store: invocationStore)
        let pipeline = PhotoPlanGenerationPipeline(
            session: imageSession,
            preparer: DefaultPhotoPlanImagePreparer(quality: imageQuality, sourceKind: sourceKind),
            runner: ImagePlanRecipeRunner(platform: aiRunner, log: log),
            log: log,
            onStage: { stage in
                await MainActor.run { generationStage = stage }
            }
        )
        let draft: AIPracticeDraft
        do {
            draft = try await pipeline.generate(PhotoPlanGenerationRequest(
                sourceImages: blobs,
                fallbackCategory: fallbackCategory,
                credentials: RuntimeCredentials(baseURL: baseURL, apiKey: apiKey, model: model),
                invocationID: UUID(uuidString: generationId) ?? UUID(),
                sourceKind: sourceKind,
                quality: imageQuality
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VisionPracticeError {
            throw ImageStepGeneratorError.failed(error)
        } catch let error as PhotoPlanGenerationError {
            switch error {
            case .noImages, .noUsableImages: throw ImageStepGeneratorError.noImages
            case .tooManyImages: throw ImageStepGeneratorError.tooManyImages
            case .payloadTooLarge: throw ImageStepGeneratorError.payloadTooLarge
            }
        } catch {
            if AIInvocationStore.errorType(from: error) == .cancelled { throw error }
            throw ImageStepGeneratorError.failed(.transport)
        }
        try Task.checkCancellation()
        applyDraft(draft)
        isGenerating = false
        phase = .preview
        lifecycle.present()
    }

    private func applyDraft(_ draft: AIPracticeDraft) {
        draftCategory = draft.category
        draftChords = draft.chords
        appliedTitle = draft.title
        appliedMinutes = draft.targetMin
        appliedSteps = draft.steps
        editTitle = draft.title
        editMinutes = draft.targetMin
        editSteps = draft.steps.map { EditStep(text: $0) }
    }

    private func currentDraft() -> AIPracticeDraft {
        var steps = editSteps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if steps.isEmpty { steps = [String(localized: "新步骤")] }
        return AIPracticeDraft(
            title: editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未命名练习") : editTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draftCategory,
            targetMin: min(60, max(1, editMinutes)),
            steps: Array(steps.prefix(12)),
            chords: draftChords
        )
    }

    private func confirm() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let draft = currentDraft()
        let token = approvalGate.issue(draft: draft, userID: "local-user", sessionID: generationId, draftID: generationId)
        let entryToken = submitToken
        confirmTask = Task {
            do {
                try await approvalGate.validate(token, draft: draft, userID: "local-user", sessionID: generationId, draftID: generationId)
                try Task.checkCancellation()
                guard lifecycle.allowsCommit else { throw CancellationError() }
                let item = try entryGate.submit(
                    store: store,
                    input: PracticeEntry.photo(draft: draft, generationId: generationId),
                    token: entryToken,
                    now: Date(),
                    calendar: .current
                )
                guard lifecycle.commit() else { throw CancellationError() }
                didFinishOutcome = true
                invocationStore.setDraftOutcome(
                    id: generationId,
                    outcome: AIDraftOutcomeRules.confirm(
                        originalTitle: appliedTitle,
                        originalMinutes: appliedMinutes,
                        originalSteps: appliedSteps,
                        editTitle: draft.title,
                        editMinutes: draft.targetMin,
                        editSteps: draft.steps
                    ),
                    taskId: item.id.uuidString
                )
                selection = item.id.uuidString
                onFinished()
            } catch is CancellationError {
                return
            } catch {
                isSubmitting = false
                toast = String(localized: "保存失败，请重试")
                hideToastLater()
            }
        }
    }

    private func regenerate() {
        guard !selectedBlobs.isEmpty, !isSubmitting else { return }
        let predecessor = generationId
        prepareGeneration()
        generateTask = Task {
            do {
                try await generate(blobs: selectedBlobs, sourceKind: selectedSourceKind)
                invocationStore.markRegenerated(invocationID: predecessor, successorInvocationID: generationId)
            } catch is CancellationError {
                invocationStore.markRegenerated(invocationID: predecessor, successorInvocationID: generationId)
            } catch {
                invocationStore.markRegenerated(invocationID: predecessor, successorInvocationID: generationId)
                fail(with: error)
            }
        }
    }

    private func fail(with error: Error) {
        isGenerating = false
        phase = .source
        pickerItems = []
        generateTask = nil
        if let error = error as? ImageStepGeneratorError {
            toast = error.userMessage
        } else {
            toast = String(localized: "生成失败，请稍后重试")
        }
        hideToastLater()
    }

    private func close() {
        if phase == .generating {
            generateTask?.cancel()
            generateTask = nil
            pickerItems = []
            isGenerating = false
            phase = .source
            invocationStore.setDraftOutcome(id: generationId, outcome: .abandoned, taskId: nil)
            lifecycle.abandon()
            Task { await imageSession.release() }
            return
        }
        if phase == .preview, !didFinishOutcome {
            invocationStore.setDraftOutcome(id: generationId, outcome: .abandoned, taskId: nil)
            lifecycle.abandon()
        }
        Task { await imageSession.release() }
        dismiss()
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toast = nil
        }
    }

    private func recordNotConfigured() async {
        let skill = SkillRegistry.builtin.skill(id: SkillID.planFromImage)!
        await LiveAIInvocationLog(store: invocationStore).record(AIInvocationRecordInput(
            id: generationId,
            skillId: skill.id,
            skillVersion: skill.version,
            model: model,
            startedAt: Date(),
            durationMs: 0,
            status: .failure,
            errorType: .notConfigured,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: nil
        ))
    }
}
