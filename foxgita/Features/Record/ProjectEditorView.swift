import SwiftData
import SwiftUI

enum ProjectEditorMode: Equatable {
    case create
    case edit(UUID)
}

struct ProjectEditorView: View {
    let mode: ProjectEditorMode
    var createSource: String = "projects_list"

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var name = ""
    @State private var goal = ""
    @State private var loadedName = ""
    @State private var loadedGoal = ""
    @State private var nameError: String?
    @State private var goalError: String?
    @State private var error: String?
    @State private var didLoadEditFields = false
    @State private var showAbandon = false
    @State private var isSubmitting = false
    @State private var startedAt = Date()
    @State private var goalExpanded = false

    private var canSubmit: Bool {
        !ProjectSetupRules.trimmed(name).isEmpty
    }

    private var isDirty: Bool {
        switch mode {
        case .create:
            return ProjectSetupRules.isCreateDirty(name: name, goal: goal)
        case .edit:
            return ProjectSetupRules.isEditDirty(
                name: name, goal: goal, loadedName: loadedName, loadedGoal: loadedGoal
            )
        }
    }

    private var analyticsSource: String {
        mode == .create ? createSource : "edit"
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                editorHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("你想持续练什么？")
                            .font(GitaFont.headline())
                            .foregroundStyle(GitaTheme.textPrimary)
                        Text("用一句话创建，其他信息以后再补充。")
                            .font(GitaFont.callout())
                            .foregroundStyle(GitaTheme.textSecondary)
                        field(
                            title: "项目名称 *",
                            placeholder: "学会《知足》",
                            text: $name,
                            max: ProjectSetupRules.nameMax,
                            error: nameError
                        )
                        if goalExpanded {
                            field(
                                title: "完成标准",
                                placeholder: "",
                                text: $goal,
                                max: ProjectSetupRules.goalMax,
                                error: goalError
                            )
                        } else {
                            goalFoldedRow
                        }
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
            Text(mode == .create ? "新建项目" : "编辑项目")
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

    private var goalFoldedRow: some View {
        Button(action: expandGoal) {
            HStack(spacing: 8) {
                Text("＋")
                    .font(GitaFont.callout(.medium))
                    .foregroundStyle(GitaTheme.brand500)
                Text("添加完成标准")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                Text("选填  ›")
                    .font(GitaFont.caption())
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
    }

    private var editorFooter: some View {
        VStack(spacing: 8) {
            Text("只需要一个项目名称")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
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
        }
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
                .frame(minHeight: 48, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GitaTheme.radius12)
                        .stroke(GitaTheme.borderSubtle, lineWidth: 1)
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
        loadedName = project.name
        loadedGoal = project.goal
        if ProjectSetupRules.hasGoal(project.goal) {
            goalExpanded = true
        }
    }

    private func expandGoal() {
        guard !goalExpanded else { return }
        goalExpanded = true
        RecordAnalytics.projectGoalExpanded(source: createSource)
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
            RecordAnalytics.projectSetupAbandoned(source: analyticsSource, durationMs: ms)
        }
        leave()
    }

    private func leave() {
        switch router.recordPath.last {
        case .projectCreate, .projectCreateFromPractice, .projectEdit:
            router.recordPath.removeLast()
        default:
            dismiss()
        }
    }

    private func save() {
        guard !isSubmitting else { return }
        nameError = nil
        goalError = nil
        error = nil
        switch ProjectSetupRules.prepare(name: name, goal: goal) {
        case .failure(let setupError):
            RecordAnalytics.projectSetupValidationFailed(fieldName: setupError.fieldName, reason: setupError.reason)
            if setupError.fieldName == "name" {
                nameError = setupError == .nameEmpty ? "请填写项目名称" : "名称过长"
            } else {
                goalError = "完成标准过长"
            }
        case .success(let fields):
            isSubmitting = true
            do {
                switch mode {
                case .create:
                    RecordAnalytics.projectCreateSubmitted(source: createSource, hasGoal: ProjectSetupRules.hasGoal(fields.goal))
                    let project = try store.createProject(name: fields.name, goal: fields.goal, now: Date())
                    let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
                    RecordAnalytics.projectCreated(source: createSource, hasGoal: ProjectSetupRules.hasGoal(fields.goal), durationMs: ms)
                    router.presentCreatedProject(project.id, fromPracticeTab: false)
                case .edit(let id):
                    try store.updateProjectBasics(id: id, name: fields.name, goal: fields.goal, now: Date())
                    if !router.recordPath.isEmpty { router.recordPath.removeLast() }
                }
            } catch {
                isSubmitting = false
                RecordAnalytics.projectCreateFailed(source: createSource, errorCode: "save_failed")
                self.error = String(localized: "保存失败，请重试")
            }
        }
    }
}
