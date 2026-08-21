import SwiftUI

struct AIMemorySettingsView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @State private var showAdd = false
    @State private var addKind: MemoryScope = .goal
    @State private var addSummary = ""
    @State private var editingId: String?
    @State private var editSummary = ""
    @State private var pendingDelete: MemoryItem?
    @State private var showClear = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toggleCard
                if memoryStore.lastError != nil {
                    errorCaption
                }
                ForEach(MemoryConsentCopy.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                group(title: "目标", items: memoryStore.items.filter { $0.kind == .goal })
                group(title: "偏好", items: memoryStore.items.filter { $0.kind == .preference })
                readOnlyGroup(title: "能力", items: memoryStore.items.filter { $0.kind == .ability })
                readOnlyGroup(title: "事实", items: memoryStore.items.filter { $0.kind == .fact })
                readOnlyGroup(title: "摘要", items: memoryStore.items.filter { $0.kind == .summary })
                if memoryStore.consent == .enabled {
                    Button("添加记忆") { showAdd = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                if !memoryStore.items.isEmpty {
                    Button("清除全部 AI 记忆", role: .destructive) { showClear = true }
                }
            }
            .padding(16)
        }
        .background(PageBackground())
        .navigationTitle(MemoryConsentCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            memoryStore.reload()
            presentStoreErrorIfNeeded()
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(isPresented: Binding(
            get: { editingId != nil },
            set: { if !$0 { editingId = nil } }
        )) {
            editSheet
        }
        .alert("删除这条记忆？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id { _ = memoryStore.delete(id: id) }
                pendingDelete = nil
                presentStoreErrorIfNeeded()
            }
        }
        .alert("清除全部 AI 记忆？", isPresented: $showClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                _ = memoryStore.clearAll()
                presentStoreErrorIfNeeded()
            }
        } message: {
            Text("删除后不会再发给模型。练习记录不会动。")
        }
    }

    private var toggleCard: some View {
        Toggle(isOn: Binding(
            get: { memoryStore.consent == .enabled },
            set: {
                _ = memoryStore.setConsent($0 ? .enabled : .disabled)
                presentStoreErrorIfNeeded()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("允许 AI 使用长期记忆").font(.system(size: 14, weight: .semibold))
                Text("关闭后不读取也不再弹出说明")
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .tint(GitaTheme.brand500)
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func group(title: String, items: [MemoryItem]) -> some View {
        if items.isEmpty && memoryStore.consent == .enabled && title == "目标"
            && memoryStore.items.filter({ $0.kind == .goal || $0.kind == .preference }).isEmpty
        {
            Text("还没有记忆，添加一条目标或偏好")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
        }
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            ForEach(items, id: \.id) { item in
                row(item, canEdit: item.kind == .goal || item.kind == .preference)
            }
        }
    }

    @ViewBuilder
    private func readOnlyGroup(title: String, items: [MemoryItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            ForEach(items, id: \.id) { item in row(item, canEdit: false) }
        }
    }

    private func row(_ item: MemoryItem, canEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.summaryText).font(.system(size: 14, weight: .semibold))
            Text(sourceLabel(item.sourceType))
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack {
                if canEdit {
                    Button("编辑") {
                        editSummary = item.summaryText
                        editingId = item.id
                    }
                }
                Button("删除", role: .destructive) { pendingDelete = item }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "user": return String(localized: "你添加的")
        case "task": return String(localized: "来自练习任务")
        case "ai": return String(localized: "AI 观察")
        case "debug_seed": return String(localized: "调试种子")
        default: return raw
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $addKind) {
                    Text("目标").tag(MemoryScope.goal)
                    Text("偏好").tag(MemoryScope.preference)
                }
                TextField("摘要", text: $addSummary, axis: .vertical)
                if memoryStore.lastError != nil {
                    errorCaption
                }
            }
            .navigationTitle("添加记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if memoryStore.add(kind: addKind, summary: addSummary) {
                            addSummary = ""
                            showAdd = false
                        } else {
                            presentStoreErrorIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                TextField("摘要", text: $editSummary, axis: .vertical)
                if memoryStore.lastError != nil {
                    errorCaption
                }
            }
            .navigationTitle("编辑记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingId = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let id = editingId else { return }
                        if memoryStore.updateSummary(id: id, summary: editSummary) {
                            editingId = nil
                        } else {
                            presentStoreErrorIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private var errorCaption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(memoryStore.lastError?.errorDescription ?? String(localized: "保存失败"))
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
            Button("重试") { retryReload() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
        }
    }

    private func retryReload() {
        memoryStore.reload()
        presentStoreErrorIfNeeded()
    }

    private func presentStoreErrorIfNeeded() {
        guard let error = memoryStore.lastError else { return }
        toast = error.errorDescription ?? String(localized: "保存失败")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}
