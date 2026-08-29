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
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]

    @State private var name = ""
    @State private var goal = ""
    @State private var currentFocus = ""
    @State private var loadedName = ""
    @State private var loadedGoal = ""
    @State private var loadedFocus = ""
    @State private var nameError: String?
    @State private var goalError: String?
    @State private var error: String?
    @State private var didLoadEditFields = false
    @State private var showAbandon = false
    @State private var isSubmitting = false
    @State private var startedAt = Date()

    private var canSubmit: Bool {
        !ProjectSetupRules.trimmed(name).isEmpty && !ProjectSetupRules.trimmed(goal).isEmpty
    }

    private var isDirty: Bool {
        switch mode {
        case .create:
            return ProjectSetupRules.isCreateDirty(name: name, goal: goal, currentFocus: currentFocus)
        case .edit:
            return ProjectSetupRules.isEditDirty(
                name: name,
                goal: goal,
                currentFocus: currentFocus,
                loadedName: loadedName,
                loadedGoal: loadedGoal,
                loadedFocus: loadedFocus
            )
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button("关闭") { requestClose() }
                    Text(mode == .create ? "创建项目" : "编辑项目")
                        .font(GitaFont.title())
                    field(
                        title: "项目名称（必填）",
                        text: $name,
                        max: ProjectSetupRules.nameMax,
                        error: nameError
                    )
                    field(
                        title: "完成目标（必填）",
                        text: $goal,
                        max: ProjectSetupRules.goalMax,
                        error: goalError
                    )
                    field(
                        title: "当前重点（选填）",
                        text: $currentFocus,
                        max: ProjectSetupRules.focusMax,
                        error: nil
                    )
                    Text("下一次行动提示，不是待办")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    if let error {
                        Text(error).foregroundStyle(GitaTheme.brand500)
                    }
                    Button(mode == .create ? "创建项目" : "保存") { save() }
                        .disabled(!canSubmit || isSubmitting)
                    Spacer(minLength: 0)
                }
                .padding(GitaTheme.pagePadding)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { loadEditFieldsIfNeeded() }
        .confirmationDialog("未保存的内容会丢失", isPresented: $showAbandon, titleVisibility: .visible) {
            Button("继续填写", role: .cancel) {}
            Button("放弃创建", role: .destructive) { abandon() }
        }
    }

    private func field(
        title: String,
        text: Binding<String>,
        max: Int,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            TextField(title, text: text)
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
        loadedName = project.name
        loadedGoal = project.goal
        loadedFocus = project.currentFocus
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
        router.pendingJoinPracticeItemId = nil
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
        switch ProjectSetupRules.prepare(name: name, goal: goal, currentFocus: currentFocus) {
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
                        hasFocus: ProjectSetupRules.hasFocus(fields.currentFocus)
                    )
                    let project = try store.createProject(
                        name: fields.name,
                        goal: fields.goal,
                        kindRaw: "",
                        stageRaw: "",
                        currentFocus: fields.currentFocus,
                        now: Date()
                    )
                    let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
                    let source: String
                    if onCreated != nil {
                        source = "join"
                    } else if fromEmpty {
                        source = "empty"
                    } else if router.pendingJoinPracticeItemId != nil {
                        source = "join"
                    } else {
                        source = "list"
                    }
                    RecordAnalytics.projectCreated(
                        source: source,
                        fromEmpty: fromEmpty,
                        hasFocus: ProjectSetupRules.hasFocus(fields.currentFocus),
                        durationMs: ms
                    )
                    finishCreate(projectId: project.id)
                case .edit(let id):
                    try store.updateProject(
                        id: id,
                        name: fields.name,
                        goal: fields.goal,
                        kindRaw: "",
                        stageRaw: "",
                        currentFocus: fields.currentFocus,
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
        if let joinId = router.pendingJoinPracticeItemId {
            let from = practiceItems.first { $0.id == joinId }?.projectId?.uuidString ?? ""
            do {
                try store.setPracticeItemProject(id: joinId, projectId: projectId, now: Date())
                RecordAnalytics.practiceProjectChanged(
                    fromProjectId: from,
                    toProjectId: projectId.uuidString
                )
            } catch {
                isSubmitting = false
                self.error = String(localized: "保存失败，请重试")
                return
            }
            router.pendingJoinPracticeItemId = nil
        }
        if fromEmpty {
            router.replaceLastRecordRoute(.projectReady(projectId: projectId))
        } else if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }
}
