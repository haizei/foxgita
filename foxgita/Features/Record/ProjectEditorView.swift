//
//  ProjectEditorView.swift
//  foxgita
//

import SwiftData
import SwiftUI

enum ProjectEditorMode: Equatable {
    case create
    case edit(UUID)
}

struct ProjectEditorView: View {
    let mode: ProjectEditorMode
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
    @State private var kindRaw = ""
    @State private var stageRaw = ""
    @State private var currentFocus = ""
    @State private var error: String?
    @State private var didLoadEditFields = false

    var body: some View {
        ZStack {
            PageBackground()
            VStack(alignment: .leading, spacing: 16) {
                Button("关闭") { close() }
                Text(mode == .create ? "创建项目" : "编辑项目").font(GitaFont.title())
                TextField("项目名称", text: $name)
                TextField("完成目标", text: $goal)
                TextField("类型（选填）", text: $kindRaw)
                TextField("阶段（选填）", text: $stageRaw)
                TextField("当前重点（选填）", text: $currentFocus)
                if let error { Text(error).foregroundStyle(GitaTheme.brand500) }
                Button("保存") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer(minLength: 0)
            }
            .padding(GitaTheme.pagePadding)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { loadEditFieldsIfNeeded() }
    }

    private func loadEditFieldsIfNeeded() {
        guard case .edit(let id) = mode, !didLoadEditFields else { return }
        guard let project = projects.first(where: { $0.id == id }) else { return }
        didLoadEditFields = true
        name = project.name
        goal = project.goal
        kindRaw = project.kindRaw
        stageRaw = project.stageRaw
        currentFocus = project.currentFocus
    }

    private func close() {
        router.pendingJoinPracticeItemId = nil
        if onCreated != nil {
            dismiss()
        } else if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }

    private func save() {
        do {
            switch mode {
            case .create:
                let project = try store.createProject(
                    name: name, goal: goal, kindRaw: kindRaw, stageRaw: stageRaw,
                    currentFocus: currentFocus, now: Date()
                )
                if let onCreated {
                    onCreated(project.id)
                    dismiss()
                } else {
                    if let joinId = router.pendingJoinPracticeItemId {
                        let from = practiceItems.first { $0.id == joinId }?.projectId?.uuidString ?? ""
                        try store.setPracticeItemProject(id: joinId, projectId: project.id, now: Date())
                        RecordAnalytics.practiceProjectChanged(
                            fromProjectId: from,
                            toProjectId: project.id.uuidString
                        )
                        router.pendingJoinPracticeItemId = nil
                    }
                    if !router.recordPath.isEmpty {
                        router.recordPath.removeLast()
                    }
                }
            case .edit(let id):
                try store.updateProject(
                    id: id, name: name, goal: goal, kindRaw: kindRaw, stageRaw: stageRaw,
                    currentFocus: currentFocus, now: Date()
                )
                if onCreated != nil {
                    dismiss()
                } else if !router.recordPath.isEmpty {
                    router.recordPath.removeLast()
                }
            }
        } catch {
            self.error = String(localized: "保存失败，请重试")
        }
    }
}
