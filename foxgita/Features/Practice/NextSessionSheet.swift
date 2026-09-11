import SwiftUI

struct NextSessionSheet: View {
    private enum Phase {
        case duration
        case generating
        case preview
    }

    var initialMinutes: Int
    var fallbackCategory: PracticeCategory
    var baseURL: String
    var model: String
    @Binding var selection: String?
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.memoryContext) private var memoryContext
    @Environment(\.durationPreferenceSync) private var durationSync
    @Environment(PracticeStore.self) private var store
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(AIInvocationStore.self) private var invocationStore
    @Environment(MemoryConsentCoordinator.self) private var consent

    @State private var phase: Phase = .duration
    @State private var minutes = 20
    @State private var isGenerating = false
    @State private var generateTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var generationId = UUID().uuidString
    @State private var entryGate = PracticeEntryGate()
    @State private var submitToken = PracticeEntryToken()
    @State private var approvalGate = PracticeDraftApprovalGate()
    @State private var isSubmitting = false
    @State private var citation = ""
    @State private var draftCategory: PracticeCategory = .chord
    @State private var draftChords: [String] = []
    @State private var editTitle = ""
    @State private var editMinutes = 20
    @State private var editSteps: [EditStep] = []
    @State private var appliedTitle = ""
    @State private var appliedMinutes = 20
    @State private var appliedSteps: [String] = []
    @State private var didFinishOutcome = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text(titleText)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭", action: close)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Group {
                switch phase {
                case .duration: durationContent
                case .generating: generatingContent
                case .preview: previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GitaTheme.bgDefault)
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            memoryStore.reload()
            minutes = NextSessionDuration.resolved(
                preferenceMinutes: NextSessionDuration.parsePreference(consentedItems),
                initialMinutes: initialMinutes
            )
        }
        .onDisappear {
            generateTask?.cancel()
            abandonPreviewIfNeeded()
            if consent.isPresented {
                consent.chooseDisabled()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var titleText: String {
        switch phase {
        case .duration: return "安排今日练习"
        case .generating: return "正在安排今日练习"
        case .preview: return "确认今日练习"
        }
    }

    private var durationContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("这次能练多久？")
                .font(.system(size: 17, weight: .bold))
            Text("生成后可以再改步骤。确认前不会加入今日清单。")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(spacing: 8) {
                ForEach([15, 20, 30], id: \.self) { value in
                    Button {
                        minutes = value
                    } label: {
                        Text("\(value) 分钟")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(minutes == value ? GitaTheme.brandOn : GitaTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(minutes == value ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button { minutes = max(5, minutes - 5) } label: {
                    Text("－").frame(width: 28, height: 28)
                }
                Text("\(minutes) 分钟")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 48)
                Button { minutes = min(60, minutes + 5) } label: {
                    Text("＋").frame(width: 28, height: 28)
                }
            }
            .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
            Button(action: beginGeneration) {
                Text("生成安排")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private var generatingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在按你的 \(minutes) 分钟安排练习")
                .font(.system(size: 14))
                .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(citation)
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            TextField("标题", text: $editTitle)
                .font(.system(size: 16, weight: .semibold))
            HStack {
                Button { editMinutes = max(1, editMinutes - 5) } label: {
                    Text("－")
                }
                Text("\(editMinutes) 分钟")
                Button { editMinutes = min(60, editMinutes + 5) } label: {
                    Text("＋")
                }
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
            Button("重新生成") {
                minutes = min(60, max(5, editMinutes))
                beginGeneration()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(GitaTheme.brand500)
            .disabled(isSubmitting)
            Button(action: confirm) {
                Text("加入今日练习")
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
    }

    private func beginGeneration() {
        guard !isGenerating, !isSubmitting else { return }
        generateTask = Task {
            let gate = await consent.ensureDecided()
            guard !Task.isCancelled else { return }
            guard gate == .proceed else { return }
            durationSync?.syncActive(minutes: minutes)
            memoryStore.reload()
            let predecessorInvocationID = phase == .preview ? generationId : nil
            generationId = UUID().uuidString
            submitToken = PracticeEntryToken()
            phase = .generating
            isGenerating = true
            toast = nil
            do {
                let log = LiveAIInvocationLog(store: invocationStore)
                let client: any NextSessionGenerating = RecipeMigrationResolver().usesPlatform(
                    for: SkillID.nextSession
                )
                    ? NextSessionRecipeRunner(memory: memoryContext, log: log)
                    : NextSessionClient(memory: memoryContext, log: log)
                let generator = NextSessionGenerator(
                    client: client,
                    log: log
                )
                let draft = try await generator.generate(
                    budgetMinutes: minutes,
                    baseURL: baseURL,
                    model: model,
                    fallbackCategory: fallbackCategory,
                    invocationId: generationId
                )
                try Task.checkCancellation()
                if let predecessorInvocationID {
                    invocationStore.markRegenerated(
                        invocationID: predecessorInvocationID,
                        successorInvocationID: generationId
                    )
                }
                applyDraft(draft)
                citation = NextSessionCitation.line(
                    items: consentedItems.filter { draft.sourceMemoryIDs.contains($0.id) },
                    selectedMinutes: minutes
                )
                isGenerating = false
                phase = .preview
            } catch is CancellationError {
                if let predecessorInvocationID {
                    invocationStore.markRegenerated(
                        invocationID: predecessorInvocationID,
                        successorInvocationID: generationId
                    )
                }
                return
            } catch {
                if Task.isCancelled { return }
                if let predecessorInvocationID {
                    invocationStore.markRegenerated(
                        invocationID: predecessorInvocationID,
                        successorInvocationID: generationId
                    )
                }
                fail(with: error)
            }
        }
    }

    private var consentedItems: [MemoryItem] {
        memoryStore.consent == .enabled ? memoryStore.items : []
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

    private func confirm() {
        guard !isSubmitting else { return }
        let token = submitToken
        isSubmitting = true
        let draft = currentDraft()
        let approval = approvalGate.issue(
            draft: draft,
            userID: "local-user",
            sessionID: generationId,
            draftID: generationId
        )
        Task {
            do {
                try await approvalGate.validate(
                    approval,
                    draft: draft,
                    userID: "local-user",
                    sessionID: generationId,
                    draftID: generationId
                )
                let item = try commitDraft(draft: draft, token: token)
                recordConfirmOutcome(taskId: item.id.uuidString)
                selection = item.id.uuidString
                onFinished()
            } catch {
                isSubmitting = false
                toast = String(localized: "生成失败，请稍后重试")
                hideToastLater()
            }
        }
    }

    private func currentDraft() -> AIPracticeDraft {
        var steps = editSteps
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if steps.isEmpty { steps = [String(localized: "新步骤")] }
        if steps.count > 12 { steps = Array(steps.prefix(12)) }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIPracticeDraft(
            title: title.isEmpty ? String(localized: "未命名练习") : title,
            category: draftCategory,
            targetMin: min(60, max(1, editMinutes)),
            steps: steps,
            chords: draftChords
        )
    }

    private func commitDraft(draft: AIPracticeDraft, token: PracticeEntryToken) throws -> PracticeItem {
        return try entryGate.submit(
            store: store,
            input: PracticeEntry.next(draft: draft, generationId: generationId),
            token: token,
            now: Date(),
            calendar: .current
        )
    }

    private func fail(with error: Error) {
        isGenerating = false
        phase = .duration
        generateTask = nil
        if let error = error as? NextSessionGeneratorError {
            toast = error.userMessage
        } else {
            toast = String(localized: "生成失败，请稍后重试")
        }
        hideToastLater()
    }

    private func recordConfirmOutcome(taskId: String) {
        guard !didFinishOutcome else { return }
        didFinishOutcome = true
        invocationStore.setDraftOutcome(
            id: generationId,
            outcome: AIDraftOutcomeRules.confirm(
                originalTitle: appliedTitle,
                originalMinutes: appliedMinutes,
                originalSteps: appliedSteps,
                editTitle: editTitle,
                editMinutes: editMinutes,
                editSteps: editSteps.map(\.text)
            ),
            taskId: taskId
        )
    }

    private func abandonPreviewIfNeeded() {
        guard phase == .preview, !didFinishOutcome else { return }
        didFinishOutcome = true
        invocationStore.setDraftOutcome(id: generationId, outcome: .abandoned, taskId: nil)
    }

    private func close() {
        if phase == .generating {
            generateTask?.cancel()
            generateTask = nil
            isGenerating = false
            phase = .duration
        } else {
            abandonPreviewIfNeeded()
            dismiss()
        }
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}

private struct EditStep: Identifiable {
    let id = UUID()
    var text: String
}
