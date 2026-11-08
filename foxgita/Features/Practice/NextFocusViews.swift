import SwiftUI
import SwiftData

private struct FocusEditorSelection: Identifiable {
    var id: UUID
}

struct SuggestedPracticeSection: View {
    let profileID: UUID
    let items: [PracticeItemSnapshot]
    @Environment(PracticeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PracticePrograms.self) private var programs
    @State private var editor: FocusEditorSelection?
    @State private var error: String?
    @State private var launchChoice: NextFocusLaunchError?
    @State private var showLaunchChoice = false
    @State private var showDelete = false

    private var today: String { PracticeDayKey.make(from: .now, calendar: .current) }
    private var action: NextFocusAction? { store.suggestions.documents[profileID]?.action }
    private var execution: PracticeItemSnapshot? {
        guard let action else { return nil }
        return items.first { $0.originId == action.originID && $0.practiceDayKey == today && !$0.isDeleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = store.suggestions.readErrors[profileID] {
                Text("下次重点暂时无法读取").font(GitaFont.headline())
                Text(message).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                Button("重试") { load() }
            } else if let action, action.skippedDay != today {
                HStack {
                    Text("建议练习").font(GitaFont.title())
                    Spacer()
                    Text((execution?.durationSeconds ?? 0) > 0 ? "已暂停" : "待开始")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
                DaySessionCard(
                    title: action.context.title, minutes: 0,
                    category: PracticeCategory(rawValue: action.context.categoryRaw) ?? .chord,
                    actionTitle: (execution?.durationSeconds ?? 0) > 0 ? "继续" : "开始",
                    showsShadow: false, subtitle: action.text,
                    minutesText: elapsedLabel, subtitleLineLimit: nil
                ) { launch() }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(GitaTheme.borderSubtle, lineWidth: 1))
                .accessibilityIdentifier("suggested-practice.card")
                HStack {
                    Button("来自 \(action.context.sourceDay)练习") { openSource() }
                        .accessibilityIdentifier("suggested-practice.source")
                    Spacer()
                    Button("修改") { editor = .init(id: action.context.sourceID) }
                    Button("这次跳过") {
                        perform { try store.suggestions.skip(profileID: profileID, day: today) }
                    }
                    Menu {
                        Button("删除建议", role: .destructive) { showDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("更多建议练习操作")
                }
                .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }
            if action?.skippedDay == today {
                HStack {
                    Text("今天已跳过，明天再显示").font(GitaFont.caption())
                    Spacer()
                    Button("撤销") { perform { try store.suggestions.skip(profileID: profileID, day: nil) } }
                }
            }
            if let error { Text(error).font(GitaFont.caption()).foregroundStyle(GitaTheme.statusError) }
        }
        .padding(.bottom, action?.skippedDay != today && action != nil ? 24 : 0)
        .task(id: profileID) { load() }
        .sheet(item: $editor) { selection in
            NextFocusEditor(profileID: profileID, sourceID: selection.id) { editor = nil }
        }
        .confirmationDialog("删除这条建议练习？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除建议", role: .destructive) { perform { try store.suggestions.delete(profileID: profileID) } }
        } message: { Text("已发生的练习记录会保留。") }
        .confirmationDialog("无法直接接续", isPresented: $showLaunchChoice, titleVisibility: .visible) {
            if case .unavailableSource = launchChoice {
                Button("作为自由练习开始") { launch(free: true) }
                Button("修改重点") { if let action { editor = .init(id: action.context.sourceID) } }
            } else {
                Button("重新开始当天练习") { launch(restart: true) }
            }
            Button("取消", role: .cancel) { }
        } message: { Text(launchChoice?.localizedDescription ?? "请重试") }
    }

    private var elapsedLabel: String {
        guard let seconds = execution?.durationSeconds, seconds > 0 else { return "待开始" }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func load() {
        perform {
            let doc = try store.suggestions.document(profileID)
            for id in doc.completedExecutionIDs ?? [] where !router.completedPracticeItemIds.contains(id) {
                router.markPracticeItemCompleted(id)
            }
        }
    }
    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil } catch { self.error = error.localizedDescription }
    }
    private func openSource() {
        guard let action else { return }
        perform {
            _ = try store.scorePracticeItem(id: action.context.sourceID)
            router.practicePath.append(.detail(itemId: action.context.sourceID))
        }
    }
    private func launch(free: Bool = false, restart: Bool = false) {
        guard let action else { return }
        guard !programs.timer.isRunning else {
            error = "请先从顶部方案返回并暂停当前训练，再开始建议练习。"
            return
        }
        do {
            let item = try store.openSuggestedPractice(actionID: action.id,
                completedIDs: router.completedPracticeItemIds, allowFreePractice: free, restartMissing: restart)
            error = nil
            router.practicePath.append(.detail(itemId: item.id))
        } catch let choice as NextFocusLaunchError {
            launchChoice = choice
            showLaunchChoice = true
        } catch { self.error = error.localizedDescription }
    }
}

struct NextFocusEditor: View {
    let profileID: UUID
    let sourceID: UUID
    var completed = false
    var startupError: String? = nil
    var onClose: () -> Void
    @Environment(PracticeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true }) private var activeProfiles: [LocalProfile]
    @AppStorage(LLMSettingsKey.baseURL) private var baseURL = ""
    @AppStorage(LLMSettingsKey.model) private var model = ""
    @AppStorage("gita.nextFocus.autoGenerate") private var autoGenerate = true
    @ScaledMetric(relativeTo: .body) private var inputHeight: CGFloat = 64
    @State private var context: NextFocusContext?
    @State private var text = ""
    @State private var supplement = ""
    @State private var manualEntry = false
    @State private var userEdited = false
    @State private var didLoad = false
    @State private var updateProject = false
    @State private var error: String?
    @State private var showReplace = false
    @State private var showReview = false
    @State private var showStaleReview = false
    @State private var pendingSaveContext: NextFocusContext?
    @State private var pendingReplacement = false
    @State private var sourceUnavailable = false
    @State private var projectFailed = false
    @State private var latestProjectFocus = ""
    @State private var confirmProjectOverwrite = false
    @State private var projectCanBeReviewed = false
    @State private var textSaveFailed = false
    @State private var providerConfigured = false

    private var draft: NextFocusDraft? { store.suggestions.documents[profileID]?.drafts[sourceID.uuidString] }
    private var isGenerating: Bool { context.map(store.suggestions.isGenerating) ?? false }
    private var configured: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if NextFocusUITestScenario.isActive { return true }
        #endif
        return providerConfigured
    }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 600 }

    private var needsSupplement: Bool {
        configured && !manualEntry && (draft?.requiresSupplement ?? (draft?.generated == true && draft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true))
    }

    private var input: Binding<String> {
        Binding(get: { needsSupplement ? supplement : text }, set: { value in
            userEdited = true
            if needsSupplement { supplement = value } else { text = value }
            persistText()
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            completionHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本次总结").font(GitaFont.headline())
                        Text(draft?.recap ?? context?.factualRecap ?? "正在读取本次练习…")
                            .font(GitaFont.body()).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("下次练习重点").font(GitaFont.headline())
                            Spacer()
                            Text(needsSupplement ? "待补充" : (draft?.generated == true ? "AI 建议" : "可填写"))
                                .font(GitaFont.caption())
                                .foregroundStyle(needsSupplement ? GitaTheme.textSecondary : GitaTheme.brand500)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(needsSupplement ? GitaTheme.bgSubtle : GitaTheme.brand50, in: Capsule())
                        }
                        focusCard
                    }
                    HStack {
                        Button { showReview = true } label: {
                            HStack(spacing: 4) {
                                Text("查看本次复盘")
                                Image(systemName: "chevron.right").font(GitaFont.caption(.semibold))
                            }.frame(minHeight: 32)
                        }
                        .accessibilityIdentifier("next-focus.review")
                        Spacer()
                        if configured {
                            Menu {
                                Button(draft?.generated == true ? "重新整理重点" : "生成下次重点") { generate() }
                                    .disabled(isGenerating)
                                Toggle("完成后自动整理", isOn: $autoGenerate)
                            } label: {
                                Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 32)
                            }
                            .accessibilityLabel("AI 建议设置")
                        }
                    }
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    statusMessages.font(GitaFont.caption())
                    secondaryControls
                }
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20).padding(.top, 32)
        .foregroundStyle(GitaTheme.textPrimary)
        .background(GitaTheme.bgSurface)
        .safeAreaInset(edge: .bottom, spacing: 0) { fixedActions }
        .task { load() }
        .onChange(of: baseURL) { _, _ in refreshProviderConfiguration() }
        .onChange(of: model) { _, _ in refreshProviderConfiguration() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshProviderConfiguration() }
        }
        .onChange(of: draft) { _, latest in
            if !userEdited, let latest {
                text = latest.text
                supplement = latest.supplement ?? ""
                if latest.generated, didLoad { NextFocusPageTiming.mark(sourceID: sourceID, .viewStateReady) }
            }
        }
        .onChange(of: activeProfiles.first?.id) { _, _ in onClose() }
        .sheet(isPresented: $showReview, onDismiss: { refreshContext() }) {
            NavigationStack {
                PracticeDetailView(itemId: sourceID, openedFromRecord: true)
                    .safeAreaInset(edge: .top) {
                        HStack { Button("返回下次重点") { showReview = false }; Spacer() }.padding(12)
                            .background(GitaTheme.bgSurface)
                    }
            }
        }
        .confirmationDialog("替换原来的未完成重点？", isPresented: $showReplace, titleVisibility: .visible) {
            Button("替换为新重点") { save(replace: true) }
            Button("保留原重点", role: .cancel) { }
        } message: {
            Text(store.suggestions.documents[profileID]?.action?.text ?? "原安排将被替换")
        }
        .confirmationDialog("依据已变化，请重新核对", isPresented: $showStaleReview, titleVisibility: .visible) {
            Button("核对后保存重点") { save(replace: pendingReplacement, reviewed: pendingSaveContext) }
            Button("继续编辑", role: .cancel) { }
        } message: {
            Text("原记录或项目当前重点已改变。草稿已保留。\n最新项目重点：\(pendingSaveContext?.projectFocus.isEmpty == false ? pendingSaveContext!.projectFocus : "尚未设置")\n将保存：\(text)")
        }
        .confirmationDialog("确认覆盖项目当前重点？", isPresented: $confirmProjectOverwrite, titleVisibility: .visible) {
            Button("确认覆盖") { applyProject(overwrite: true) }
        } message: { Text("当前：\(latestProjectFocus)\n将更新为：\(text)") }
        .presentationDetents([.height(needsSupplement ? 620 : 560), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(GitaTheme.bgSurface)
        .interactiveDismissDisabled(textSaveFailed || text.count > 600 || supplement.count > 600)
    }

    private var completionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28, weight: .regular)).foregroundStyle(GitaTheme.brand500)
                    .accessibilityHidden(true)
                Text(completed ? "本次练习完成" : "本次总结与下次重点").font(GitaFont.metric())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let seconds = context?.durationSeconds {
                    Text(seconds >= 60 ? "\(seconds / 60) 分钟" : "\(seconds) 秒")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                        .accessibilityLabel("实际练习 \(seconds / 60)分\(seconds % 60)秒")
                }
            }
            Text("\(context?.title ?? "本次练习") · 练习记录已保存")
                .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
        }
        .accessibilityIdentifier("next-focus.header")
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if needsSupplement {
                Text("下次最想继续哪部分？").font(GitaFont.body(.medium)).foregroundStyle(GitaTheme.textPrimary)
            }
            if isGenerating { ProgressView("正在整理下次重点…").font(GitaFont.callout()) }
            ZStack(alignment: .topLeading) {
                if input.wrappedValue.isEmpty {
                    Text(needsSupplement ? "写下想继续的内容或关注点…" : "写下下次想继续的重点…")
                        .font(needsSupplement ? GitaFont.callout() : GitaFont.body())
                        .foregroundStyle(GitaTheme.textSecondary).padding(.horizontal, 12).padding(.vertical, needsSupplement ? 12 : 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: input)
                    .font(needsSupplement ? GitaFont.callout() : GitaFont.body())
                    .scrollContentBackground(.hidden).padding(.horizontal, 7).padding(.vertical, needsSupplement ? 4 : 0)
                    .frame(height: inputHeight)
                    .foregroundStyle(GitaTheme.textPrimary)
                    .accessibilityLabel(needsSupplement ? "补充下次想继续的内容" : "下次练习重点")
                    .accessibilityIdentifier("next-focus.input")
            }
            .background(GitaTheme.bgSubtle, in: RoundedRectangle(cornerRadius: 12))
            if needsSupplement {
                Text("补充后，为你整理下次练习重点。")
                Text("也可以返回首页，稍后再补充。")
            } else if let basis = draft?.basis, !basis.isEmpty {
                Text(basis.hasPrefix("依据") ? basis : "依据：\(basis)")
            }
        }
        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
        .padding(16)
        .background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GitaTheme.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder private var statusMessages: some View {
        if text.count > 600 || supplement.count > 600 {
            Text("重点最多 600 字").foregroundStyle(GitaTheme.statusError)
        }
        if let context, let draft, context != draft.context {
            Text("依据已变化，草稿已保留。请核对本次记录和最新项目重点后保存，或重新整理。")
                .foregroundStyle(GitaTheme.brand500)
        }
        if let failure = context.flatMap({ store.suggestions.generationError($0) }) ?? draft?.generationError {
            Text("整理失败：\(failure)。可以重试或直接手动填写。")
                .foregroundStyle(GitaTheme.statusError)
        }
        if projectFailed {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.suggestions.documents[profileID]?.action?.text == text && !textSaveFailed
                     ? "练习重点已保存，项目重点未更新。" : "已保存上次重点，当前修改尚未确认。")
                    .font(GitaFont.callout(.semibold))
                Text("项目最新重点：\(latestProjectFocus)")
                Button("重试更新项目") { applyProject() }
                Button("用这份重点覆盖项目") { reviewProjectOverwrite() }.disabled(!projectCanBeReviewed)
                Button("不更新项目，返回首页") {
                    do { try store.suggestions.clearProjectUpdate(profileID: profileID, sourceID: sourceID); close() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
        if context == nil { Button("重试读取") { load() } }
    }

    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if configured, needsSupplement {
                Button("直接手动填写重点") { manualEntry = true }
                    .frame(minHeight: 32)
            } else if configured, draft?.generated != true || draft?.generationError != nil {
                Button("生成下次重点") { generate() }.disabled(isGenerating)
                    .frame(minHeight: 32)
            } else if !configured {
                Text("AI 尚未配置，可以直接手动填写下次重点。")
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            if let context, context.projectID != nil {
                Toggle("一并更新项目当前重点", isOn: $updateProject)
                if updateProject {
                    Text("项目：\(context.projectName)\n原重点：\(context.projectFocus.isEmpty ? "尚未设置" : context.projectFocus)\n新重点：\(text)")
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
        }
        .font(GitaFont.caption()).tint(GitaTheme.brand500)
    }

    private var fixedActions: some View {
        VStack(spacing: 8) {
            Button {
                if needsSupplement { generate() } else { save() }
            } label: {
                Text(needsSupplement ? "生成下次重点" : "保存下次重点")
                    .font(GitaFont.body()).frame(maxWidth: .infinity).frame(minHeight: 50)
                    .foregroundStyle(primaryEnabled ? GitaTheme.brandOn : GitaTheme.textSecondary)
                    .background(primaryEnabled ? GitaTheme.brand500 : GitaTheme.borderSubtle, in: Capsule())
            }
            .buttonStyle(.plain).disabled(!primaryEnabled)
            .accessibilityIdentifier("next-focus.save")
            Button("返回首页") { close() }
                .font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .accessibilityIdentifier("next-focus.return")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
        .background(GitaTheme.bgSurface)
    }

    private var primaryEnabled: Bool {
        guard context != nil else { return false }
        if needsSupplement { return !isGenerating && !supplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && supplement.count <= 600 }
        return canSave
    }

    private func load() {
        guard !didLoad else { return }
        refreshProviderConfiguration()
        do {
            _ = try store.suggestions.document(profileID)
            do { context = try store.nextFocusContext(itemID: sourceID) }
            catch {
                guard let saved = draft?.context else { throw error }
                context = saved
                sourceUnavailable = true
                self.error = "来源记录暂不可用，已保留原重点和来源信息。"
            }
            guard let context else { return }
            var prepared = try store.suggestions.prepare(context)
            #if DEBUG && targetEnvironment(simulator)
            if NextFocusUITestScenario.isActive, !prepared.generated {
                let ticket = try store.suggestions.beginGeneration(context)
                try store.suggestions.applyGenerated(NextFocusUITestScenario.initialOutput(context), ticket: ticket)
                prepared = try store.suggestions.prepare(context)
            }
            #endif
            text = prepared.text
            supplement = prepared.supplement ?? ""
            didLoad = true
            NextFocusPageTiming.mark(sourceID: sourceID, .editorLoaded)
            if prepared.generated {
                NextFocusPageTiming.preparedDraftReady(sourceID: sourceID)
            }
            projectFailed = prepared.pendingProjectUpdate != nil
            if projectFailed { readLatestProjectFocus() }
            if let startupError { self.error = startupError }
            if completed, startupError == nil, autoGenerate, configured, !prepared.generated,
               prepared.revision == 0, prepared.generationError == nil,
               store.suggestions.generationError(context) == nil, !isGenerating { generate() }
        } catch { self.error = error.localizedDescription }
    }

    private func refreshContext() {
        do { context = try store.nextFocusContext(itemID: sourceID) }
        catch { self.error = error.localizedDescription }
    }

    private func refreshProviderConfiguration() {
        providerConfigured = LLMCredentialsStore().isConfigured(baseURL: baseURL, model: model)
    }

    private func persistText() {
        do {
            if needsSupplement {
                try store.suggestions.editSupplement(profileID: profileID, sourceID: sourceID, text: supplement)
            } else {
                try store.suggestions.edit(profileID: profileID, sourceID: sourceID, text: text)
            }
            textSaveFailed = false
            error = nil
        } catch { textSaveFailed = true; self.error = error.localizedDescription }
    }

    private func generate() {
        var key = LLMCredentialsStore().loadAPIKey()
        var client: any NextFocusGenerating = store.nextFocusGenerator()
        #if DEBUG && targetEnvironment(simulator)
        if NextFocusUITestScenario.isActive { key = "ui-fixture"; client = NextFocusUITestGenerator() }
        #endif
        guard let key else { error = "AI 接口暂不可用，可以直接手动填写重点。"; return }
        do {
            if textSaveFailed {
                if needsSupplement { try store.suggestions.editSupplement(profileID: profileID, sourceID: sourceID, text: supplement) }
                else { try store.suggestions.edit(profileID: profileID, sourceID: sourceID, text: text) }
                textSaveFailed = false
            }
            let context = try store.nextFocusContext(itemID: sourceID)
            self.context = context
            let intention = needsSupplement ? supplement : (userEdited || draft?.editedByUser == true ? text : "")
            try store.suggestions.generate(context, supplement: intention, baseURL: baseURL,
                                           model: model, apiKey: key, client: client)
            manualEntry = false
            userEdited = false
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save(replace: Bool = false, reviewed: NextFocusContext? = nil) {
        do {
            guard UUID(uuidString: activeProfiles.first?.id ?? "") == profileID else { throw NextFocusError.changedAction }
            let latest: NextFocusContext
            do { latest = try store.nextFocusContext(itemID: sourceID) }
            catch {
                let wasUnavailable = sourceUnavailable
                if (error as? StoreError) == .notFound { sourceUnavailable = true }
                guard sourceUnavailable, let saved = draft?.context else { throw error }
                if updateProject { throw NextFocusLaunchError.unavailableSource }
                if !wasUnavailable {
                    self.error = "来源练习已不可用，草稿已保留。可再次保存重点，或返回首页。"
                    return
                }
                latest = saved
            }
            if latest != (reviewed ?? draft?.context) {
                context = latest
                pendingSaveContext = latest
                pendingReplacement = replace
                showStaleReview = true
                return
            }
            try store.suggestions.edit(profileID: profileID, sourceID: sourceID, text: text)
            _ = try store.suggestions.confirm(profileID: profileID, sourceID: sourceID,
                replace: replace, updateProject: updateProject, reviewedContext: latest)
            if updateProject { applyProject() } else { onClose() }
        } catch NextFocusError.replacementRequired { showReplace = true }
        catch { self.error = error.localizedDescription }
    }

    private func applyProject(overwrite: Bool = false) {
        do {
            if let pending = draft?.pendingProjectUpdate, pending.text != text {
                try store.suggestions.edit(profileID: profileID, sourceID: sourceID, text: text)
                try store.suggestions.editProjectUpdate(profileID: profileID, sourceID: sourceID, text: text)
                textSaveFailed = false
            }
            try store.applyNextFocusProjectUpdate(profileID: profileID, sourceID: sourceID,
                                                  overwrite: overwrite, reviewedFocus: latestProjectFocus)
            projectFailed = false
            onClose()
        } catch {
            projectFailed = true
            self.error = error.localizedDescription
            readLatestProjectFocus()
        }
    }

    private func readLatestProjectFocus() {
        guard let id = context?.projectID else { projectCanBeReviewed = false; return }
        do {
            latestProjectFocus = try store.nextFocusProjectText(projectID: id)
            projectCanBeReviewed = true
        } catch { latestProjectFocus = "项目暂不可用"; projectCanBeReviewed = false }
    }

    private func reviewProjectOverwrite() {
        readLatestProjectFocus()
        if projectCanBeReviewed { confirmProjectOverwrite = true }
    }

    private func close() {
        if didLoad, userEdited {
            do {
                if needsSupplement { try store.suggestions.editSupplement(profileID: profileID, sourceID: sourceID, text: supplement) }
                else { try store.suggestions.edit(profileID: profileID, sourceID: sourceID, text: text) }
            }
            catch { self.error = error.localizedDescription; return }
        }
        onClose()
    }
}
