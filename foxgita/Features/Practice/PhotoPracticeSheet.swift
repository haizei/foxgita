import Combine
import SwiftData
import SwiftUI
import UIKit

struct PhotoPracticeSheet: View {
    private enum Phase {
        case generating
        case confirming
        case failed
    }

    let imageData: [Data]
    let requestedTitle: String
    let fallbackCategory: PracticeCategory
    let baseURL: String
    let model: String
    @Binding var selectedProjectId: UUID?
    @Binding var selection: String?
    let onReselect: () -> Void
    let onFinished: () -> Void

    @Environment(\.memoryContext) private var memoryContext
    @Environment(PracticeStore.self) private var store
    @Environment(AIInvocationStore.self) private var invocationStore
    @Environment(MemoryConsentCoordinator.self) private var consent
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var phase: Phase = .generating
    @State private var hasStarted = false
    @State private var generateTask: Task<Void, Never>?
    @State private var generationStartedAt = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var generationId = UUID().uuidString
    @State private var originalDraft: AIPracticeDraft?
    @State private var originalProjectId: UUID?
    @State private var draftTitle = ""
    @State private var draftCategory: PracticeCategory = .chord
    @State private var draftChords: [String] = []
    @State private var steps: [PhotoPracticeStep] = []
    @State private var toast: String?
    @State private var isSubmitting = false
    @State private var didFinishOutcome = false
    @State private var showProjectSelection = false
    @State private var showStepEditor = false
    @State private var editingStepID: UUID?
    @State private var editTitle = ""
    @State private var editDetail = ""
    @State private var editMinutes = 5
    @State private var entryGate = PracticeEntryGate()
    @State private var submitToken = PracticeEntryToken()

    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    private var canConfirm: Bool {
        !isSubmitting && PhotoPracticeStep.valid(steps) && totalMinutes <= 60
    }
    private var projectName: String {
        guard let selectedProjectId else { return "未选择项目" }
        return projects.first(where: { $0.id == selectedProjectId })?.name ?? "未选择项目"
    }

    var body: some View {
        Group {
            switch phase {
            case .generating:
                generatingContent
            case .confirming:
                confirmingContent
            case .failed:
                failedContent
            }
        }
        .background(GitaTheme.bgSurface)
        .sheet(isPresented: $showProjectSelection) {
            PracticeProjectSelectionView(selectedProjectId: $selectedProjectId)
        }
        .sheet(isPresented: $showStepEditor) {
            stepEditor
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            beginGeneration()
        }
        .onReceive(progressTimer) { _ in
            guard phase == .generating else { return }
            elapsed = Date().timeIntervalSince(generationStartedAt)
        }
        .onDisappear {
            generateTask?.cancel()
            if phase == .confirming { abandonDraftIfNeeded() }
            if consent.isPresented { consent.chooseDisabled() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var generatingContent: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            HStack {
                Text("正在生成练习")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭", action: close)
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(width: 64, height: 64)
                    .background(GitaTheme.brand50)
                    .clipShape(Circle())
                Text("正在识别图片内容")
                    .font(.system(size: 18, weight: .bold))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GitaTheme.bgSubtle)
                        Capsule()
                            .fill(GitaTheme.brand500)
                            .frame(width: proxy.size.width * CGFloat(PhotoGenerationProgress.fraction(elapsed: elapsed, completed: false)))
                    }
                }
                .frame(height: 8)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(PhotoGenerationProgress.captions.enumerated()), id: \.offset) { index, caption in
                        HStack(spacing: 10) {
                            Image(systemName: index <= PhotoGenerationProgress.activeIndex(elapsed: elapsed, completed: false)
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(index <= PhotoGenerationProgress.activeIndex(elapsed: elapsed, completed: false)
                                    ? GitaTheme.brand500 : GitaTheme.borderSubtle)
                            Text(caption)
                                .font(.system(size: 13))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 32)
            Spacer()
            Text("识别完成后进入确认练习内容")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textTertiary)
                .padding(.bottom, 28)
        }
    }

    private var confirmingContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel("返回")
                Spacer()
                Text("确认练习内容")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Color.clear.frame(width: 32, height: 36)
            }
            .foregroundStyle(GitaTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        if let image = imageData.first.flatMap(UIImage.init(data:)) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 130, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("来源图片")
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            Text("已识别图片内容")
                                .font(.system(size: 16, weight: .bold))
                            Text("已识别 \(steps.count) 个练习步骤")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                            Button {
                                abandonDraftIfNeeded(outcome: .regenerated)
                                onReselect()
                            } label: {
                                Label("重新选择图片", systemImage: "photo")
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(GitaTheme.bgSubtle)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }

                    Button { showProjectSelection = true } label: {
                        HStack {
                            Text("归属项目")
                            Spacer()
                            Text(projectName)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 58)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text("练习步骤")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        Text("\(steps.count) 个步骤 · 约 \(totalMinutes) 分钟")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            Button { openEditor(step) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(GitaTheme.brand500)
                                        .frame(width: 44, height: 44)
                                        .background(GitaTheme.brand50)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .lineLimit(1)
                                        if !step.detail.isEmpty {
                                            Text(step.detail)
                                                .font(.system(size: 12))
                                                .foregroundStyle(GitaTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(step.minutes) 分钟")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                                .foregroundStyle(GitaTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 82)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("practice.photo-step-\(index + 1)")
                            if index < steps.count - 1 {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .background(GitaTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(GitaTheme.borderSubtle, lineWidth: 1)
                    }

                    Button {
                        guard steps.count < 12 else { return }
                        let step = PhotoPracticeStep(title: "新步骤", minutes: 5)
                        steps.append(step)
                        openEditor(step)
                    } label: {
                        Label("添加步骤", systemImage: "plus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GitaTheme.brand500)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(GitaTheme.bgSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(steps.count >= 12)

                    if totalMinutes > 60 {
                        Text("步骤总时长不能超过 60 分钟")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.brand500)
                    }
                    if let toast {
                        Text(toast)
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.brand500)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 24)
            }

            Button(action: confirmPractice) {
                Text("确认并创建练习")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(GitaTheme.brand500)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(!canConfirm)
            .opacity(canConfirm ? 1 : 0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var failedContent: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回") { onReselect() }
                Spacer()
            }
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(GitaTheme.brand500)
            Text("图片识别失败")
                .font(.system(size: 20, weight: .bold))
            Text(toast ?? "请重试或重新选择图片")
                .foregroundStyle(GitaTheme.textSecondary)
            Button("重试识别", action: beginGeneration)
                .buttonStyle(.borderedProminent)
            Button("重新选择图片", action: onReselect)
            Spacer()
        }
        .padding(20)
    }

    private var stepEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("编辑步骤")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("完成", action: saveEditor)
                    .foregroundStyle(GitaTheme.brand500)
            }
            TextField("步骤名称", text: $editTitle)
                .textFieldStyle(.roundedBorder)
            TextField("练习说明（选填）", text: $editDetail, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Stepper("练习时长 \(editMinutes) 分钟", value: $editMinutes, in: 1...60)
            HStack {
                Button("上移") { moveEditingStep(by: -1) }
                Button("下移") { moveEditingStep(by: 1) }
                Spacer()
                Button("删除步骤", role: .destructive) { deleteEditingStep() }
                    .disabled(steps.count <= 1)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(350)])
    }

    private func beginGeneration() {
        guard !imageData.isEmpty else { phase = .failed; toast = "请选择图片"; return }
        generationId = UUID().uuidString
        submitToken = PracticeEntryToken()
        phase = .generating
        elapsed = 0
        generationStartedAt = Date()
        toast = nil
        generateTask = Task {
            let gate = await consent.ensureDecided()
            guard !Task.isCancelled else { return }
            guard gate == .proceed else { onReselect(); return }
            do {
                let log = LiveAIInvocationLog(store: invocationStore)
                let generator = ImageStepGenerator(
                    client: VisionPracticeClient(memory: memoryContext, log: log),
                    log: log
                )
                let draft = try await generator.generate(
                    imageData: imageData,
                    baseURL: baseURL,
                    model: model,
                    fallbackCategory: fallbackCategory,
                    invocationId: generationId
                )
                try Task.checkCancellation()
                originalDraft = draft
                originalProjectId = selectedProjectId
                draftTitle = requestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? draft.title : requestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                draftCategory = draft.category
                draftChords = draft.chords
                steps = PhotoPracticeStep.fromDraft(draft)
                phase = .confirming
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                toast = (error as? ImageStepGeneratorError)?.userMessage ?? "生成失败，请稍后重试"
                phase = .failed
            }
        }
    }

    private func openEditor(_ step: PhotoPracticeStep) {
        editingStepID = step.id
        editTitle = step.title
        editDetail = step.detail
        editMinutes = step.minutes
        showStepEditor = true
    }

    private func saveEditor() {
        guard let id = editingStepID,
              let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { toast = "步骤名称不能为空"; return }
        steps[index].title = title
        steps[index].detail = editDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        steps[index].minutes = editMinutes
        showStepEditor = false
    }

    private func moveEditingStep(by offset: Int) {
        guard !editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            toast = "步骤名称不能为空"
            return
        }
        saveEditor()
        guard let id = editingStepID,
              let index = steps.firstIndex(where: { $0.id == id }),
              steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
        showStepEditor = false
    }

    private func deleteEditingStep() {
        guard steps.count > 1, let id = editingStepID else { return }
        steps.removeAll { $0.id == id }
        showStepEditor = false
    }

    private func confirmPractice() {
        guard canConfirm, let originalDraft else { return }
        isSubmitting = true
        let minutes = totalMinutes
        let draft = AIPracticeDraft(
            title: draftTitle,
            category: draftCategory,
            targetMin: minutes,
            steps: steps.map(\.storedText),
            chords: draftChords
        )
        do {
            let item = try entryGate.submit(
                store: store,
                input: PracticeEntry.photo(draft: draft, generationId: generationId, projectId: selectedProjectId),
                token: submitToken,
                now: Date(),
                calendar: .current
            )
            let outcome = AIDraftOutcomeRules.confirm(
                originalTitle: originalDraft.title,
                originalMinutes: originalDraft.targetMin,
                originalSteps: originalDraft.steps,
                editTitle: draft.title,
                editMinutes: draft.targetMin,
                editSteps: draft.steps
            )
            invocationStore.setDraftOutcome(
                id: generationId,
                outcome: originalProjectId == selectedProjectId ? outcome : .edited,
                taskId: item.id.uuidString
            )
            didFinishOutcome = true
            selection = item.id.uuidString
            onFinished()
        } catch {
            isSubmitting = false
            toast = "创建练习失败，请重试"
        }
    }

    private func abandonDraftIfNeeded(outcome: AIDraftOutcome = .abandoned) {
        guard phase == .confirming, !didFinishOutcome else { return }
        didFinishOutcome = true
        invocationStore.setDraftOutcome(id: generationId, outcome: outcome, taskId: nil)
    }

    private func close() {
        if phase == .generating {
            generateTask?.cancel()
        } else {
            abandonDraftIfNeeded()
        }
        onReselect()
    }
}
