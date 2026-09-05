import SwiftData
import SwiftUI

struct ProjectCreateFromPracticeView: View {
    let itemId: UUID
    var fromPracticeTab: Bool = false

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [PracticeItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var name = ""
    @State private var initialName = ""
    @State private var didPrefill = false
    @State private var nameError: String?
    @State private var error: String?
    @State private var showAbandon = false
    @State private var showSwitchConfirm = false
    @State private var switchConfirmed = false
    @State private var isSubmitting = false
    @State private var createdProjectId: UUID?
    @State private var startedAt = Date()

    init(itemId: UUID, fromPracticeTab: Bool = false) {
        self.itemId = itemId
        self.fromPracticeTab = fromPracticeTab
        _items = Query(
            filter: #Predicate<PracticeItem> { $0.id == itemId && $0.deletedAt == nil }
        )
    }

    private var item: PracticeItem? { items.first }

    private var recordingCount: Int {
        item?.recordings.filter { $0.deletedAt == nil }.count ?? 0
    }

    private var currentProjectName: String? {
        guard let projectId = item?.projectId else { return nil }
        return projects.first(where: { $0.id == projectId })?.name
    }

    private var canSubmit: Bool {
        !ProjectSetupRules.trimmed(name).isEmpty
    }

    private var isDirty: Bool {
        ProjectSetupRules.isFromPracticeDirty(name: name, initialName: initialName)
    }

    private var todayKey: String {
        PracticeDayKey.make(from: Date(), calendar: .current)
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("把这次练习持续下去")
                            .font(GitaFont.headline())
                            .foregroundStyle(GitaTheme.textPrimary)
                        if let item {
                            sourceCard(item)
                        }
                        nameField
                        Text("这次练习会自动加入项目。完成标准和阶段可以稍后补充。")
                            .font(GitaFont.callout())
                            .foregroundStyle(GitaTheme.textSecondary)
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
            footer
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { prefillIfNeeded() }
        .onChange(of: item?.id) { _, _ in prefillIfNeeded() }
        .confirmationDialog("未保存的内容会丢失", isPresented: $showAbandon, titleVisibility: .visible) {
            Button("继续填写", role: .cancel) {}
            Button("放弃创建", role: .destructive) { abandon() }
        }
        .confirmationDialog(switchConfirmMessage, isPresented: $showSwitchConfirm, titleVisibility: .visible) {
            Button("取消", role: .cancel) {}
            Button("确认加入") {
                switchConfirmed = true
                create(link: true)
            }
        }
    }

    private var switchConfirmMessage: String {
        let projectName = currentProjectName ?? "原项目"
        return "这条练习已属于「\(projectName)」，加入新项目后会从原项目移除。"
    }

    private var header: some View {
        HStack {
            Button(action: requestClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.iconPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("返回"))
            Spacer(minLength: 0)
            Text("建立长期项目")
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, GitaTheme.s24)
        .frame(height: 56)
    }

    private func sourceCard(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                ProjectSetupRules.practiceSourceLabel(
                    practiceDayKey: item.practiceDayKey,
                    todayKey: todayKey
                )
            )
            .font(GitaFont.caption())
            .foregroundStyle(GitaTheme.textSecondary)
            Text(item.title)
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Text(
                ProjectSetupRules.practiceSourceMeta(
                    durationSeconds: item.durationSeconds,
                    recordingCount: recordingCount
                )
            )
            .font(GitaFont.caption())
            .foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(GitaTheme.brand50)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("项目名称 *")
                .font(GitaFont.footnote(.medium))
                .foregroundStyle(GitaTheme.textPrimary)
            TextField("学会《知足》", text: $name, axis: .vertical)
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
                .onChange(of: name) { _, newValue in
                    let clamped = ProjectSetupRules.clamp(newValue, max: ProjectSetupRules.nameMax)
                    if clamped != newValue {
                        name = clamped
                    }
                }
            if let nameError {
                Text(nameError)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.brand500)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button("仅创建空项目") {
                create(link: false)
            }
            .font(GitaFont.callout())
            .foregroundStyle(GitaTheme.textSecondary)
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)

            Button {
                create(link: true)
            } label: {
                Text("创建并加入项目")
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

    private func prefillIfNeeded() {
        guard !didPrefill, let item else { return }
        didPrefill = true
        name = item.title
        initialName = item.title
    }

    private func requestClose() {
        if isDirty {
            showAbandon = true
        } else {
            leave()
        }
    }

    private func abandon() {
        let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        RecordAnalytics.projectSetupAbandoned(source: "practice_detail", durationMs: ms)
        leave()
    }

    private func leave() {
        switch router.recordPath.last {
        case .projectCreateFromPractice:
            router.recordPath.removeLast()
        default:
            dismiss()
        }
    }

    private func create(link: Bool) {
        guard !isSubmitting else { return }
        nameError = nil
        error = nil
        let fields: ProjectSetupFields
        switch ProjectSetupRules.prepare(name: name, goal: "") {
        case .failure(let setupError):
            RecordAnalytics.projectSetupValidationFailed(
                fieldName: setupError.fieldName,
                reason: setupError.reason
            )
            nameError = setupError == .nameEmpty ? "请填写项目名称" : "名称过长"
            return
        case .success(let prepared):
            fields = prepared
        }

        guard let item else { return }
        let hadPreviousProject = item.projectId != nil
        if link, item.projectId != nil, !switchConfirmed {
            showSwitchConfirm = true
            return
        }

        isSubmitting = true
        do {
            let projectId: UUID
            if let createdProjectId {
                projectId = createdProjectId
            } else {
                let project = try store.createProject(name: fields.name, goal: fields.goal, now: Date())
                createdProjectId = project.id
                projectId = project.id
            }

            if !link {
                RecordAnalytics.projectCreatedFromPractice(
                    linkResult: "empty_only",
                    hadPreviousProject: hadPreviousProject
                )
                router.presentCreatedProject(projectId, fromPracticeTab: fromPracticeTab)
                if fromPracticeTab { dismiss() }
                return
            }

            try store.setPracticeItemProject(id: itemId, projectId: projectId, now: Date())
            RecordAnalytics.projectCreatedFromPractice(
                linkResult: "linked",
                hadPreviousProject: hadPreviousProject
            )
            router.presentCreatedProject(projectId, fromPracticeTab: fromPracticeTab)
            if fromPracticeTab { dismiss() }
        } catch {
            isSubmitting = false
            if createdProjectId != nil, link {
                self.error = "项目已创建，加入失败，请重试"
                RecordAnalytics.projectCreatedFromPractice(
                    linkResult: "link_failed",
                    hadPreviousProject: hadPreviousProject
                )
            } else {
                RecordAnalytics.projectCreateFailed(source: "practice_detail", errorCode: "save_failed")
                self.error = String(localized: "保存失败，请重试")
            }
        }
    }
}
