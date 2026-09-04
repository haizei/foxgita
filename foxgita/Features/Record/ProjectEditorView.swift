import SwiftData
import SwiftUI

enum ProjectEditorMode: Equatable {
    case create
    case edit(UUID)
}

struct ProjectEditorView: View {
    let mode: ProjectEditorMode
    var fromEmpty: Bool = false
    var onCreated: ((UUID) -> Void)? = nil

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var name = ""
    @State private var goal = ""
    @State private var currentFocus = ""
    @State private var kind = ""
    @State private var stage = ""
    @State private var loadedName = ""
    @State private var loadedGoal = ""
    @State private var loadedFocus = ""
    @State private var loadedKind = ""
    @State private var loadedStage = ""
    @State private var nameError: String?
    @State private var goalError: String?
    @State private var error: String?
    @State private var didLoadEditFields = false
    @State private var showAbandon = false
    @State private var showStagePicker = false
    @State private var isSubmitting = false
    @State private var startedAt = Date()

    private var canSubmit: Bool {
        !ProjectSetupRules.trimmed(name).isEmpty && !ProjectSetupRules.trimmed(goal).isEmpty
    }

    private var isDirty: Bool {
        switch mode {
        case .create:
            return ProjectSetupRules.isCreateDirty(name: name, goal: goal)
        case .edit:
            return ProjectSetupRules.isEditDirty(
                name: name,
                goal: goal,
                loadedName: loadedName,
                loadedGoal: loadedGoal
            )
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                editorHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        requiredCard
                        optionalSection
                        if let error {
                            Text(error)
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.brand500)
                        }
                    }
                    .padding(.horizontal, GitaTheme.s24)
                    .padding(.top, GitaTheme.s16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorFooter
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { loadEditFieldsIfNeeded() }
        .confirmationDialog("未保存的内容会丢失", isPresented: $showAbandon, titleVisibility: .visible) {
            Button("继续填写", role: .cancel) {}
            Button("放弃创建", role: .destructive) { abandon() }
        }
    }

    private var editorHeader: some View {
        HStack {
            Color.clear.frame(width: 24, height: 24)
            Spacer(minLength: 0)
            Text(mode == .create ? "创建项目" : "编辑项目")
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("关闭"))
        }
        .padding(.horizontal, GitaTheme.s24)
        .frame(height: 56)
    }

    private var requiredCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            field(
                title: "项目名称 *",
                placeholder: "学会《知足》",
                text: $name,
                max: ProjectSetupRules.nameMax,
                emphasized: false,
                minHeight: 48,
                error: nameError
            )
            field(
                title: "完成目标 *",
                placeholder: "跟着原唱，稳定完成整首弹唱",
                text: $goal,
                max: ProjectSetupRules.goalMax,
                emphasized: true,
                minHeight: 62,
                error: goalError
            )
        }
        .padding(GitaTheme.s16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("补充练习方向")
                    .font(GitaFont.footnote(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                Text("选填")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach(ProjectSetupRules.kinds, id: \.self) { item in
                    let selected = ProjectSetupRules.trimmed(kind) == item
                    Button {
                        kind = selected ? "" : item
                    } label: {
                        Text(item)
                            .font(GitaFont.footnote(selected ? .medium : .regular))
                            .foregroundStyle(selected ? GitaTheme.brand500 : GitaTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            Button { showStagePicker = true } label: {
                HStack {
                    Text("当前阶段")
                        .font(GitaFont.footnote())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Spacer(minLength: 0)
                    Text(ProjectSetupRules.trimmed(stage).isEmpty ? "未选择" : stage)
                        .font(GitaFont.callout(.medium))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("›")
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GitaTheme.radius12)
                        .stroke(GitaTheme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
            }
            .buttonStyle(.plain)
            .confirmationDialog("当前阶段", isPresented: $showStagePicker, titleVisibility: .visible) {
                Button("不选择") { stage = "" }
                ForEach(ProjectSetupRules.stages, id: \.self) { item in
                    Button(item) { stage = item }
                }
                Button("取消", role: .cancel) {}
            }

            field(
                title: "当前重点",
                placeholder: "主歌进入副歌时保持节奏",
                text: $currentFocus,
                max: ProjectSetupRules.focusMax,
                emphasized: true,
                minHeight: 52,
                error: nil
            )
            Text("写下一次练习最值得关注的一件事，不是待办。")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
        }
    }

    private var editorFooter: some View {
        Button(action: save) {
            Text(mode == .create ? "创建项目" : "保存")
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
                .opacity(canSubmit && !isSubmitting ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .padding(.horizontal, GitaTheme.s24)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(GitaTheme.bgDefault)
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        max: Int,
        emphasized: Bool,
        minHeight: CGFloat,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(GitaFont.footnote(.medium))
                .foregroundStyle(GitaTheme.textPrimary)
            TextField(placeholder, text: text, axis: .vertical)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textPrimary)
                .tint(GitaTheme.brand500)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(emphasized ? GitaTheme.brand50 : GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GitaTheme.radius12)
                        .stroke(emphasized ? GitaTheme.brand50 : GitaTheme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
                .onChange(of: text.wrappedValue) { _, newValue in
                    let clamped = ProjectSetupRules.clamp(newValue, max: max)
                    if clamped != newValue {
                        text.wrappedValue = clamped
                    }
                }
            if let error {
                Text(error)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.brand500)
            }
        }
    }

    private func loadEditFieldsIfNeeded() {
        guard case .edit(let id) = mode, !didLoadEditFields else { return }
        guard let project = projects.first(where: { $0.id == id }) else { return }
        didLoadEditFields = true
        name = project.name
        goal = project.goal
        currentFocus = project.currentFocus
        kind = project.kindRaw
        stage = project.stageRaw
        loadedName = project.name
        loadedGoal = project.goal
        loadedFocus = project.currentFocus
        loadedKind = project.kindRaw
        loadedStage = project.stageRaw
    }

    private func requestClose() {
        if isDirty {
            showAbandon = true
        } else {
            leave()
        }
    }

    private func abandon() {
        if mode == .create {
            let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            RecordAnalytics.projectSetupAbandoned(fromEmpty: fromEmpty, durationMs: ms)
        }
        leave()
    }

    private func leave() {
        if onCreated != nil {
            dismiss()
        } else if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }

    private func save() {
        guard !isSubmitting else { return }
        nameError = nil
        goalError = nil
        error = nil
        switch ProjectSetupRules.prepare(name: name, goal: goal) {
        case .failure(let setupError):
            RecordAnalytics.projectSetupValidationFailed(
                fieldName: setupError.fieldName,
                reason: setupError.reason
            )
            switch setupError {
            case .nameEmpty, .nameTooLong:
                nameError = setupError == .nameEmpty ? "请填写项目名称" : "名称过长"
            case .goalEmpty, .goalTooLong:
                goalError = setupError == .goalEmpty ? "请填写完成目标" : "目标过长"
            case .focusTooLong:
                error = "当前重点过长"
            }
            return
        case .success(let fields):
            isSubmitting = true
            do {
                switch mode {
                case .create:
                    RecordAnalytics.projectSetupSubmitClicked(
                        fromEmpty: fromEmpty,
                        hasFocus: ProjectSetupRules.hasFocus(currentFocus)
                    )
                    let project = try store.createProject(
                        name: fields.name,
                        goal: fields.goal,
                        now: Date()
                    )
                    let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
                    let source: String
                    if onCreated != nil {
                        source = "join"
                    } else if fromEmpty {
                        source = "empty"
                    } else {
                        source = "list"
                    }
                    RecordAnalytics.projectCreated(
                        source: source,
                        fromEmpty: fromEmpty,
                        hasFocus: ProjectSetupRules.hasFocus(currentFocus),
                        durationMs: ms
                    )
                    finishCreate(projectId: project.id)
                case .edit(let id):
                    try store.updateProjectBasics(
                        id: id,
                        name: fields.name,
                        goal: fields.goal,
                        now: Date()
                    )
                    if onCreated != nil {
                        dismiss()
                    } else if !router.recordPath.isEmpty {
                        router.recordPath.removeLast()
                    }
                }
            } catch {
                isSubmitting = false
                self.error = String(localized: "保存失败，请重试")
            }
        }
    }

    private func finishCreate(projectId: UUID) {
        if let onCreated {
            onCreated(projectId)
            dismiss()
            return
        }
        if fromEmpty {
            router.replaceLastRecordRoute(.projectDetail(projectId: projectId))
        } else if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }
}
