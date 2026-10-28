//
//  PracticeDetailView.swift
//  foxgita
//

import AudioToolbox
import SwiftData
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

private let practiceMetronomeLog = Logger(
    subsystem: "com.haizei.foxgita", category: "metronome-lifecycle"
)

enum PracticeDetailMode: Equatable {
    case editable
    case historical
}

enum PracticeDetailState {
    static func practiceRoute(itemId: UUID) -> PracticeRoute {
        .detail(itemId: itemId)
    }

    static func practiceRoute(fromSheetSelection raw: String) -> PracticeRoute? {
        guard let itemId = UUID(uuidString: raw) else { return nil }
        return .detail(itemId: itemId)
    }

    static func mode(
        practiceDayKey: String,
        today: Date = Date(),
        calendar: Calendar = .current,
        allowPastDayEdits: Bool = false
    ) -> PracticeDetailMode {
        if allowPastDayEdits { return .editable }
        return practiceDayKey == PracticeDayKey.make(from: today, calendar: calendar)
            ? .editable
            : .historical
    }

    static func initialElapsedSeconds(storedDurationSeconds: Int) -> Int {
        max(0, storedDurationSeconds)
    }

    static func isDirty(
        elapsedSeconds: Int,
        note: String,
        storedDurationSeconds: Int,
        storedNote: String,
        steps: [String] = [],
        storedSteps: [String] = [],
        bpm: Int? = nil,
        storedBpm: Int? = nil,
        timeSignature: String? = nil,
        storedTimeSignature: String? = nil,
        accentPatternRaw: String? = nil,
        storedAccentPatternRaw: String? = nil,
        subdivisionRaw: Int? = nil,
        storedSubdivisionRaw: Int? = nil,
        metronomeSoundModeRaw: String? = nil,
        storedMetronomeSoundModeRaw: String? = nil,
        metronomeVolume: Int? = nil,
        storedMetronomeVolume: Int? = nil,
        metronomeStrongBeatBoost: Bool? = nil,
        storedMetronomeStrongBeatBoost: Bool? = nil
    ) -> Bool {
        max(0, elapsedSeconds) != max(0, storedDurationSeconds)
            || note != storedNote
            || steps != storedSteps
            || bpm != storedBpm
            || timeSignature != storedTimeSignature
            || accentPatternRaw != storedAccentPatternRaw
            || subdivisionRaw != storedSubdivisionRaw
            || metronomeSoundModeRaw != storedMetronomeSoundModeRaw
            || metronomeVolume != storedMetronomeVolume
            || metronomeStrongBeatBoost != storedMetronomeStrongBeatBoost
    }

    static func initialSteps(_ stored: [String]) -> [String] {
        stored.isEmpty ? [String(localized: "新步骤")] : stored
    }

    static func shouldAutoSaveOnDisappear(mode: PracticeDetailMode, isDirty: Bool) -> Bool {
        mode == .editable && isDirty
    }

    static func shouldAllowContentEditing(mode: PracticeDetailMode) -> Bool {
        switch mode {
        case .editable, .historical:
            return true
        }
    }

    static func shouldAllowTimer(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func shouldAllowCapture(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func shouldPreventScreenSleep(
        isMetronomePlaying: Bool, isForeground: Bool
    ) -> Bool {
        isMetronomePlaying && isForeground
    }

    static func shouldAllowComplete(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func projectChangeRequiresConfirmation(
        originalProjectId: UUID?,
        draftProjectId: UUID?,
        isVersionMarker: Bool
    ) -> Bool {
        originalProjectId != draftProjectId && isVersionMarker
    }

    static func loadedItem(
        requestedId: UUID,
        candidates: [PracticeItemSnapshot]
    ) -> PracticeItemSnapshot? {
        candidates.first { $0.id == requestedId && !$0.isDeleted }
    }
}

struct PracticeDetailView: View {
    let itemId: UUID
    var allowPastDayEdits: Bool = false
    var openedFromRecord: Bool = false
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(ReviewJobRunner.self) private var reviewRunner
    @Environment(MemoryConsentCoordinator.self) private var consent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var items: [PracticeItem]
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var allPracticeItems: [PracticeItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""
    private let llmCredentials = LLMCredentialsStore()

    private enum ToolMode {
        case audio, note, video
    }

    @State private var tempoController = MetronomeTempoController()
    @State private var practiceTimer = PracticeTimer()
    @State private var countdown = PracticeCountdown(defaultMinutes: 10)
    @State private var recorder = AudioRecorderService()
    @State private var runtime: PracticeRuntimeCoordinator
    @State private var noteDictation = NoteDictationService()
    @State private var video = VideoRecorderService()
    @State private var noteText = ""
    @State private var noteAutosaver: PracticeNoteAutosaver?
    @State private var noteSelection: TextSelection?
    @State private var dictationInsertionSelection: TextSelection?
    @State private var dictationInsertionText = ""
    @State private var noteImages: [NoteImage] = []
    private let noteImageStore = NoteImageStore()
    @State private var selectedNotePhotos: [PhotosPickerItem] = []
    @State private var noteAttachmentsExpanded = false
    @State private var noteCameraPresented = false
    @State private var showAttachmentImporter = false
    @State private var attachmentImportInProgress = false
    @State private var previewNoteImage: NoteImage?
    @State private var noteVoiceHeld = false
    @State private var noteVoiceCancelArmed = false
    @State private var storedNote = ""
    @State private var storedDurationSeconds = 0
    @State private var steps: [String] = []
    @State private var storedSteps: [String] = []
    @State private var storedBpm: Int? = nil
    @State private var storedTimeSignature: String? = nil
    @State private var storedAccentPatternRaw: String? = nil
    @State private var storedSubdivisionRaw: Int? = nil
    @State private var storedMetronomeSoundModeRaw: String? = nil
    @State private var storedMetronomeVolume: Int? = nil
    @State private var storedMetronomeStrongBeatBoost: Bool? = nil
    @State private var storedResumeState: ResumeState? = nil
    @State private var draftTitle = ""
    @State private var draftSubtitle = ""
    @State private var draftCategory: PracticeCategory = .chord
    @State private var draftTargetMin = 1
    @State private var draftProjectId: UUID?
    @State private var showDiscardHistoricalChanges = false
    @State private var leaveAfterDiscard = false
    @State private var showProjectChangeWarning = false
    @State private var createProjectAfterHistoricalSave = false
    @State private var awaitingCreatedProjectAssignment = false
    @State private var toolMode: ToolMode = .note
    @State private var expandedReviewId: String?
    @State private var toast: String?
    @State private var isCompleting = false
    @State private var didLoadItem = false
    /// Live project associated when this detail session started (or last explicit join/switch).
    @State private var sessionProjectId: UUID?
    @State private var analysisRoute: VideoRoute?
    @State private var diagnosisRoute: VideoRoute?
    /// Set only by analysis `onReady`; presented from the analysis cover's `onDismiss`.
    @State private var pendingDiagnosisRoute: VideoRoute?
    @State private var isSourcePresented = false
    @State private var pendingCamera = false
    @State private var player = AudioPlayerService()
    @State private var videoPlayURL: URL?
    @State private var showCreateFromPracticeSheet = false
    @State private var metronomeSheetAnchor: MetronomeSheetAnchor?
    @State private var showMetronomeSoundSheet = false
    @State private var showFullscreenMetronome = false
    @State private var expandAfterSoundSheet = false
    @State private var showCountdownSettings = false
    @State private var showCountdownNotificationDenied = false
    @State private var activeTrainingSessionId: UUID?
    @State private var activeTrainingStartedAt: Date?
    @State private var interruptionObserverToken: UUID?
    @FocusState private var noteFocused: Bool

    private var metronome: MetronomeEngine { tempoController.engine }

    init(itemId: UUID, allowPastDayEdits: Bool = false, openedFromRecord: Bool = false) {
        self.itemId = itemId
        self.allowPastDayEdits = allowPastDayEdits
        self.openedFromRecord = openedFromRecord
        let controller = MetronomeTempoController()
        let timer = PracticeTimer()
        let countdown = PracticeCountdown(defaultMinutes: 10)
        let recorder = AudioRecorderService()
        _tempoController = State(initialValue: controller)
        _practiceTimer = State(initialValue: timer)
        _countdown = State(initialValue: countdown)
        _recorder = State(initialValue: recorder)
        _runtime = State(initialValue: PracticeRuntimeCoordinator(
            timer: timer, countdown: countdown, playback: controller.engine, recording: recorder
        ))
        let identifier = itemId
        _items = Query(filter: #Predicate<PracticeItem> { $0.id == identifier && $0.deletedAt == nil })
    }

    private var item: PracticeItem? { items.first }

    private var isHistoricalPractice: Bool {
        guard let item else { return false }
        return !allowPastDayEdits
            && PracticeDetailState.mode(practiceDayKey: item.practiceDayKey) == .historical
    }

    private var isPastDayRecord: Bool {
        guard let item else { return false }
        return item.practiceDayKey != PracticeDayKey.make(from: Date(), calendar: .current)
    }

    private var mode: PracticeDetailMode {
        guard let item else { return .historical }
        return PracticeDetailState.mode(
            practiceDayKey: item.practiceDayKey,
            allowPastDayEdits: allowPastDayEdits
        )
    }

    private var isDirty: Bool {
        PracticeDetailState.isDirty(
            elapsedSeconds: practiceTimer.elapsedSec,
            note: noteText,
            storedDurationSeconds: storedDurationSeconds,
            storedNote: storedNote,
            steps: steps,
            storedSteps: storedSteps,
            bpm: metronome.bpm,
            storedBpm: storedBpm,
            timeSignature: metronome.configuredTimeSignatureText,
            storedTimeSignature: storedTimeSignature,
            accentPatternRaw: metronome.configuredAccentPatternRaw,
            storedAccentPatternRaw: storedAccentPatternRaw,
            subdivisionRaw: metronome.configuredSubdivisionRaw,
            storedSubdivisionRaw: storedSubdivisionRaw,
            metronomeSoundModeRaw: metronome.soundPreset.rawValue,
            storedMetronomeSoundModeRaw: storedMetronomeSoundModeRaw,
            metronomeVolume: metronome.volume,
            storedMetronomeVolume: storedMetronomeVolume,
            metronomeStrongBeatBoost: metronome.strongBeatBoost,
            storedMetronomeStrongBeatBoost: storedMetronomeStrongBeatBoost
        )
    }

    private var isHistoricalEditDirty: Bool {
        guard let item else { return false }
        return isDirty
            || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) != item.title
            || draftSubtitle.trimmingCharacters(in: .whitespacesAndNewlines) != item.subtitle
            || draftCategory.rawValue != item.categoryRaw
            || draftTargetMin != PracticeHomeState.initialTargetMin(item.targetMin)
            || draftProjectId != item.projectId
    }

    private var visibleClips: [RecordingRef] {
        guard let item else { return [] }
        let descriptors = item.recordings.map {
            PracticeClipDescriptor(
                id: $0.id, fileName: $0.fileName, createdAt: $0.createdAt, deletedAt: $0.deletedAt
            )
        }
        let visible = (PracticeClipQuery.visible(clips: descriptors, videoMode: false)
            + PracticeClipQuery.visible(clips: descriptors, videoMode: true))
            .sorted { $0.createdAt > $1.createdAt }
        let byId = Dictionary(
            item.recordings.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visible.compactMap { byId[$0.id] }
    }

    /// Anything worth losing a confirmation tap over.
    private var hasUnsavedWork: Bool {
        isDirty || !recorder.pending.isEmpty || !video.pending.isEmpty
    }

    /// True while this detail's route is still on either stack (including when covered
    /// by `.projectCreate` on `recordPath`).
    private var isItemStillOnNavigationStack: Bool {
        router.practicePath.contains {
            if case .detail(let id) = $0 { return id == itemId }
            return false
        } || router.recordPath.contains {
            if case .practiceDetail(let id) = $0 { return id == itemId }
            return false
        }
    }

    var body: some View { presentedContent }

    private var screen: some View {
        ZStack {
            PageBackground()
            if let item {
                content(item)
            } else {
                Text("任务不存在").foregroundStyle(GitaTheme.textSecondary)
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private var lifecycleContent: some View {
        screen.onAppear {
            guard let item else { return }
            metronome.applyVisualPreferences(MetronomeVisualPreferencesStore.shared.value)
            countdown.onCompletion = { handleCountdownCompletion(item) }
            let reminderItemId = item.id
            let reminderTitle = item.title
            runtime.onCountdownStarted = { seconds in
                Task {
                    await CountdownReminderScheduler.schedule(itemId: reminderItemId, title: reminderTitle, after: Int(ceil(seconds)))
                }
            }
            if !didLoadItem {
                didLoadItem = true
                draftTitle = item.title
                draftSubtitle = item.subtitle
                draftCategory = PracticeCategory(rawValue: item.categoryRaw) ?? .chord
                draftTargetMin = PracticeHomeState.initialTargetMin(item.targetMin)
                draftProjectId = item.projectId
                noteText = item.note
                storedNote = item.note
                storedDurationSeconds = PracticeDetailState.initialElapsedSeconds(
                    storedDurationSeconds: item.durationSeconds
                )
                let loadedSteps = mode == .editable
                    ? PracticeDetailState.initialSteps(item.steps)
                    : item.steps
                steps = loadedSteps
                storedSteps = loadedSteps
                practiceTimer.restore(elapsedSec: storedDurationSeconds, startedAt: nil)
                let resume = resumeState(for: item)
                storedResumeState = resume
                metronome.setBpm(resume.bpm)
                storedBpm = resume.bpm
                let loadedTimeSignature = normalizedTimeSignature(item.timeSignature)
                metronome.configureMeter(
                    timeSignature: loadedTimeSignature,
                    accentRaw: item.metronomeAccentRaw
                )
                metronome.configureSubdivision(raw: item.metronomeSubdivisionRaw)
                metronome.configureSound(
                    modeRaw: item.metronomeSoundModeRaw,
                    volume: item.metronomeVolume,
                    strongBeatBoost: item.metronomeStrongBeatBoost
                )
                storedTimeSignature = metronome.configuredTimeSignatureText
                storedAccentPatternRaw = metronome.configuredAccentPatternRaw
                storedSubdivisionRaw = metronome.configuredSubdivisionRaw
                storedMetronomeSoundModeRaw = metronome.soundPreset.rawValue
                storedMetronomeVolume = metronome.volume
                storedMetronomeStrongBeatBoost = metronome.strongBeatBoost
                loadLatestRampPlan()
                if let projectId = item.projectId,
                   projects.contains(where: { $0.id == projectId }) {
                    sessionProjectId = projectId
                }
            }
            if noteAutosaver == nil {
                let noteStore = store
                let noteItemId = item.id
                noteAutosaver = PracticeNoteAutosaver(initialText: noteText) { text in
                    try noteStore.savePracticeNote(id: noteItemId, note: text, now: Date())
                }
            }
            if let interruptionObserverToken {
                AudioSessionCoordinator.shared.removeInterruptionObserver(interruptionObserverToken)
            }
            interruptionObserverToken = AudioSessionCoordinator.shared.addInterruptionObserver {
                event in
                switch event {
                case .began:
                    handlePlaybackBoundary(reason: "audio_session", itemTitle: item.title)
                case .ended:
                    tempoController.handleInterruptionEnded()
                case .outputRouteLost:
                    handlePlaybackBoundary(reason: "output_route_lost", itemTitle: item.title)
                    tempoController.handleInterruptionEnded()
                    show(String(localized: "音频设备已断开，请手动恢复节拍器"))
                case .audioServicesReset:
                    handlePlaybackBoundary(reason: "audio_services_reset", itemTitle: item.title)
                    tempoController.engine.prepareAfterAudioServicesReset()
                    tempoController.handleInterruptionEnded()
                    show(String(localized: "系统音频已重置，请手动恢复节拍器"))
                }
            }
            updatePlaybackPresentation()
        }
        .onDisappear {
            guard !video.isPresenting, !isSourcePresented, !noteCameraPresented, !showFullscreenMetronome,
                  previewNoteImage == nil, analysisRoute == nil, diagnosisRoute == nil,
                  videoPlayURL == nil else { return }
            noteVoiceHeld = false
            noteDictation.cancel()
            recorder.cancelStart()
            UIApplication.shared.isIdleTimerDisabled = false
            metronome.foregroundFeedbackEnabled = false
            if let interruptionObserverToken {
                AudioSessionCoordinator.shared.removeInterruptionObserver(interruptionObserverToken)
                self.interruptionObserverToken = nil
            }
            if !isItemStillOnNavigationStack {
                finishActiveTraining(reason: .userStopped)
            } else if tempoController.isRampActive {
                tempoController.pauseRamp()
                updateActiveTrainingSnapshot()
            }
            practiceTimer.pause()
            metronome.stop()
            if countdown.isActive {
                countdown.close()
                CountdownReminderScheduler.cancel(itemId: itemId)
            }
            if recorder.isRecording { recorder.stop(label: item?.title ?? "") }
            player.stop()
            videoPlayURL = nil
            if let item {
                _ = flushNote()
                persistPending(item: item)
                saveItemIfNeeded(item)
                queueProjectDeletedToastIfNeeded(for: item)
            }
        }
    }

    private var observedContent: some View {
        lifecycleContent.onChange(of: metronome.isPlaying) { _, _ in
            updatePlaybackPresentation()
        }
        .onChange(of: MetronomeVisualPreferencesStore.shared.value) { _, value in
            metronome.applyVisualPreferences(value)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { _ = flushNote() }
            metronome.foregroundFeedbackEnabled = newPhase == .active
            UIApplication.shared.isIdleTimerDisabled = PracticeDetailState.shouldPreventScreenSleep(
                isMetronomePlaying: metronome.isPlaying,
                isForeground: newPhase == .active
            )
            if newPhase == .active {
                if practiceTimer.isRunning { practiceTimer.refresh() }
                countdown.refresh()
            }
        }
        .onChange(of: noteText) { _, text in
            guard PracticeDetailState.shouldAllowContentEditing(mode: mode) else { return }
            noteAutosaver?.schedule(text)
        }
        .onChange(of: noteAutosaver?.savedText) { _, text in
            if let text { storedNote = text }
        }
        .onChange(of: item?.projectId) { _, newProjectId in
            // Record-stack create-and-join updates projectId via setPracticeItemProject
            // (not assignProject). Keep session in sync for mid-practice delete toast.
            // Do not clear when projectId becomes nil — that would break the toast.
            if let newProjectId {
                sessionProjectId = newProjectId
                if awaitingCreatedProjectAssignment {
                    draftProjectId = newProjectId
                    awaitingCreatedProjectAssignment = false
                }
            }
        }
        .onChange(of: recorder.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: video.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: store.lastError) { _, value in
            if let value { show(value.localizedDescription) }
        }
        .onChange(of: tempoController.completedStageCount) { _, _ in
            updateActiveTrainingSnapshot()
        }
        .onChange(of: tempoController.currentStageBPM) { oldBPM, newBPM in
            guard tempoController.isRampActive, oldBPM != newBPM else { return }
            let event = newBPM == tempoController.rampSettings?.targetBPM
                ? "metronome_ramp_target_reached" : "metronome_ramp_step_changed"
            MetronomeAnalytics.emit(
                event, itemId: itemId.uuidString,
                sessionId: activeTrainingSessionId?.uuidString ?? "",
                ["from_bpm": String(oldBPM), "to_bpm": String(newBPM),
                 "target_bpm": String(tempoController.rampSettings?.targetBPM ?? newBPM),
                 "completed_bars": String(tempoController.completedBars)]
            )
        }
        .onChange(of: tempoController.rampState) { _, state in
            if state == .targetHold {
                MetronomeAnalytics.emit(
                    "metronome_ramp_completed", itemId: itemId.uuidString,
                    sessionId: activeTrainingSessionId?.uuidString ?? "",
                    ["target_bpm": String(metronome.bpm),
                     "completed_bars": String(tempoController.completedBars),
                     "duration": String(max(0, Int(Date().timeIntervalSince(activeTrainingStartedAt ?? Date())))),
                     "pause_count": String(tempoController.pauseCount)]
                )
                finishActiveTraining(reason: .targetCompleted)
            }
        }
    }

    private var alertedContent: some View {
        observedContent.alert("放弃修改？", isPresented: $showDiscardHistoricalChanges) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃", role: .destructive) {
                restoreHistoricalDraft()
                if leaveAfterDiscard { leave() }
                leaveAfterDiscard = false
            }
        } message: {
            Text("尚未保存的历史练习修改将会丢失。")
        }
        .alert("更换项目会清除版本标记", isPresented: $showProjectChangeWarning) {
            Button("取消", role: .cancel) {
                createProjectAfterHistoricalSave = false
            }
            Button("继续保存") { saveHistoricalChanges() }
        } message: {
            Text("这条练习是原项目的阶段版或最终版。更换或移出项目后，该标记会被清除。")
        }
    }

    private var presentedContent: some View {
        alertedContent.fullScreenCover(isPresented: Binding(
            get: { video.isPresenting },
            set: { if !$0 { video.dismiss() } }
        )) {
            VideoCameraPicker(
                isPresented: Binding(
                    get: { video.isPresenting },
                    set: { if !$0 { video.dismiss() } }
                ),
                onPicked: { url in
                    video.ingest(tempURL: url, label: item?.title ?? "")
                    if let item { persistPending(item: item) }
                },
                onCancel: { video.dismiss() }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCreateFromPracticeSheet, onDismiss: {
            if awaitingCreatedProjectAssignment,
               let assignedProjectId = item?.projectId,
               assignedProjectId != draftProjectId {
                draftProjectId = assignedProjectId
            }
            awaitingCreatedProjectAssignment = false
        }) {
            ProjectCreateFromPracticeView(itemId: itemId, fromPracticeTab: true)
        }
    }

    @ViewBuilder
    private func content(_ item: PracticeItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回") { requestExit() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                if isHistoricalPractice {
                    TextField("标题", text: $draftTitle)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(item.title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                if isHistoricalPractice {
                    Button("保存") { requestSaveHistoricalChanges() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("完成") { complete(item) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .disabled(!PracticeDetailState.shouldAllowComplete(mode: mode))
                }
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .fullScreenCover(isPresented: $isSourcePresented, onDismiss: {
                if pendingCamera {
                    pendingCamera = false
                    player.stop()
                    videoPlayURL = nil
                    video.presentCamera()
                    if video.isPresenting {
                        runtime.beginVideoPresentation(label: item.title)
                        persistPending(item: item)
                    }
                }
            }) {
                VideoSourceView(
                    taskTitle: item.title,
                    onDismiss: { isSourcePresented = false },
                    onStartCamera: {
                        pendingCamera = true
                        isSourcePresented = false
                    },
                    onImported: { clip in
                        persist(audioClip(clip), item: item)
                        isSourcePresented = false
                    },
                    onToast: { show($0) }
                )
            }

            projectCapsule(item)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let subtitle = isHistoricalPractice ? draftSubtitle : item.subtitle
                    if isHistoricalPractice,
                       !subtitle.isEmpty,
                       !AIPracticePresentation.isAIGenerated(subtitle: subtitle) {
                        TextField("练习说明", text: $draftSubtitle, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }

                    if let resume = storedResumeState,
                       let line = PracticeResumeQuery.focusLine(state: resume) {
                        Text(line)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .accessibilityLabel(Text(line))
                    }

                    MetronomeDisplayCard(
                        metronome: metronome,
                        onEntryTap: { anchor in
                            guard PracticeDetailState.shouldAllowContentEditing(mode: mode) else { return }
                            noteFocused = false
                            showMetronomeSoundSheet = false
                            metronomeSheetAnchor = anchor
                        },
                        onSoundTap: {
                            guard PracticeDetailState.shouldAllowContentEditing(mode: mode) else { return }
                            noteFocused = false
                            metronomeSheetAnchor = nil
                            showMetronomeSoundSheet = true
                        },
                        onAccentTap: { index in
                            guard PracticeDetailState.shouldAllowContentEditing(mode: mode) else { return }
                            metronome.cycleAccent(at: index)
                            Haptics.selection()
                        },
                        isAccentEditingLocked: tempoController.isRampActive
                            || !PracticeDetailState.shouldAllowContentEditing(mode: mode),
                        onLockedAccentTap: {
                            guard tempoController.isRampActive else { return }
                            show(String(localized: "变速训练中暂不可调整重音"))
                        }
                    )
                    timerCard
                    if tempoController.isRampActive || tempoController.rampState == .interrupted {
                        rampStatusBanner
                    }
                    if PracticeDetailState.shouldAllowContentEditing(mode: mode) || !steps.isEmpty {
                        stepsCard
                    }
                    noteCard(item)

                    Button { complete(item) } label: {
                        Text("完成本次练习")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GitaTheme.brand500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .disabled(!PracticeDetailState.shouldAllowComplete(mode: mode))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            // Two covers on the same view would leave only the last one live, so
            // the diagnosis cover hangs off the scroll view instead.
            .fullScreenCover(item: $diagnosisRoute) { route in
                VideoDiagnosisView(
                    recordingId: route.id,
                    taskTitle: item.title,
                    onClose: { diagnosisRoute = nil }
                )
            }
        }
        .fullScreenCover(item: $analysisRoute, onDismiss: {
            if let pending = pendingDiagnosisRoute {
                diagnosisRoute = pending
                pendingDiagnosisRoute = nil
            }
        }) { route in
            VideoAnalysisView(
                recordingId: route.id,
                taskTitle: item.title,
                durationSec: route.durationSec,
                onDismiss: { analysisRoute = nil },
                onReady: {
                    pendingDiagnosisRoute = VideoRoute(id: route.id, durationSec: route.durationSec)
                    analysisRoute = nil
                }
            )
        }
        .sheet(item: $metronomeSheetAnchor, onDismiss: { _ = saveItemIfNeeded(item) }) { anchor in
            switch anchor {
            case .speed:
                MetronomeSpeedSheet(
                    controller: tempoController,
                    onDone: { metronomeSheetAnchor = nil },
                    onStartRamp: { settings in startRamp(settings) },
                    onEndRamp: { selectedBPM in endRampFromSpeedSheet(selectedBPM: selectedBPM) },
                    practiceItemId: itemId
                )
            case .meter, .subdivision:
                MetronomeSettingsSheet(
                    metronome: metronome,
                    anchor: anchor,
                    isLocked: tempoController.isRampActive,
                    onDone: { metronomeSheetAnchor = nil }
                )
            }
        }
        .sheet(isPresented: $showMetronomeSoundSheet, onDismiss: {
            _ = saveItemIfNeeded(item)
            if expandAfterSoundSheet {
                expandAfterSoundSheet = false
                showFullscreenMetronome = true
            }
        }) {
            MetronomeSoundSheet(metronome: metronome, metronomeEnabled: metronomeEnabledBinding, onRecord: {
                showMetronomeSoundSheet = false
                toggleRecording(item)
            }, onExpand: {
                expandAfterSoundSheet = true
                showMetronomeSoundSheet = false
            }, onDone: { showMetronomeSoundSheet = false })
        }
        .fullScreenCover(isPresented: $showFullscreenMetronome) {
            MetronomeFullscreenView(
                controller: tempoController, isPracticeRunning: practiceTimer.isRunning,
                metronomeEnabled: metronomeEnabledBinding,
                onToggle: togglePlay, onRecord: { toggleRecording(item) },
                onStartRamp: startRamp, onEndRamp: { endRampFromSpeedSheet(selectedBPM: $0) },
                onDone: { showFullscreenMetronome = false }
            )
        }
        .sheet(isPresented: $showCountdownSettings) {
            CountdownSettingsSheet(
                minutes: countdown.isActive
                    ? countdown.configuredSeconds / 60
                    : initialCountdownMinutes(for: item),
                reminderEnabled: countdown.reminderEnabled,
                isExistingPlan: countdown.isActive,
                onApply: { minutes, reminderEnabled, startImmediately in
                    applyCountdownPlan(
                        minutes: minutes,
                        wantsReminder: reminderEnabled,
                        startImmediately: startImmediately,
                        item: item
                    )
                },
                onCloseCountdown: { closeCountdown() }
            )
        }
        .alert("无法开启通知", isPresented: $showCountdownNotificationDenied) {
            Button("前往设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            Button("暂不开启", role: .cancel) {}
        } message: {
            Text("倒计时仍可正常使用；如需后台结束提醒，请在系统设置中允许通知。")
        }
    }

    private func normalizedTimeSignature(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "4/4" : trimmed
    }

    private func adaptiveLayout(spacing: CGFloat) -> AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: spacing))
    }

    private var timerCard: some View {
        adaptiveLayout(spacing: 8).callAsFunction {
            VStack(alignment: .leading, spacing: 2) {
                Text(countdown.isActive ? countdown.display : practiceTimer.display)
                    .font(GitaFont.timer())
                Text(timerSupportingText)
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if PracticeDetailState.shouldAllowTimer(mode: mode) {
                Button("倒计时") { openCountdownSettings() }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 44)
                    .background(GitaTheme.brand50)
                    .clipShape(Capsule())
                    .disabled(tempoController.isRampActive)
                    .accessibilityLabel(countdown.isActive ? "调整倒计时" : "倒计时")
                    .accessibilityIdentifier("countdown.open-settings")
            }

            Button(timerPrimaryTitle) { togglePlay() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
                .disabled(!PracticeDetailState.shouldAllowTimer(mode: mode))
                .accessibilityIdentifier("practice.toggle-running")
            Button("TAP") {
                _ = tempoController.registerTap()
            }
            .font(GitaFont.caption(.medium))
            .foregroundStyle(GitaTheme.brand500)
            .frame(minWidth: 44, minHeight: 44)
            .overlay(Capsule().stroke(GitaTheme.brand500))
            .disabled(!PracticeDetailState.shouldAllowTimer(mode: mode) || tempoController.isRampActive)
        }
        .overlay(alignment: .bottomLeading) {
            if tempoController.tapReadyToApply, let estimate = tempoController.tapAttempt.estimatedBPM {
                Button("采用测速 \(estimate) BPM") { tempoController.applyMeasuredTempo(estimate) }
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.brand500)
                    .offset(y: 24)
            }
        }
        .contextMenu { Button("重置计时", action: resetTimerCard) }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var rampStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: tempoController.rampState == .targetHold ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                .foregroundStyle(GitaTheme.brand500)
            VStack(alignment: .leading, spacing: 2) {
                Text(rampStatusTitle)
                    .font(GitaFont.callout(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                if let settings = tempoController.rampSettings {
                    Text("当前 \(metronome.bpm) BPM · 目标 \(settings.targetBPM) BPM")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    if tempoController.rampState == .running {
                        Text("\(tempoController.completedBarsInStage)/\(settings.barsPerStage) 小节 · 再练 \(tempoController.remainingBarsInStage) 小节升至 \(tempoController.nextStageBPM) BPM")
                            .font(GitaFont.micro())
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                }
            }
            Spacer()
            if tempoController.rampState == .running || tempoController.rampState == .countIn {
                Button("暂停") { togglePlay() }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
            } else if tempoController.rampState == .paused {
                Button("继续") { togglePlay() }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
            } else if tempoController.rampState == .interrupted {
                Button("继续") { togglePlay() }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minHeight: 44)
                    .disabled(!tempoController.interruptionRecoveryAvailable)
            }
            Button("结束") { endRampFromSpeedSheet() }
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.statusError)
                .accessibilityIdentifier("metronome.ramp.stop")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var rampStatusTitle: String {
        switch tempoController.rampState {
        case .countIn: return String(localized: "预备拍")
        case .running: return String(localized: "变速训练中")
        case .paused: return String(localized: "变速训练已暂停")
        case .targetHold: return String(localized: "目标速度保持")
        case .interrupted: return String(localized: "训练已中断，等待继续")
        default: return String(localized: "变速训练")
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("练习步骤").font(.system(size: 18, weight: .bold))
                Spacer()
                if PracticeDetailState.shouldAllowContentEditing(mode: mode) {
                    Button("新增步骤") { steps.append(String(localized: "新步骤")) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
            }
            .padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                    TextField("步骤", text: binding(index))
                        .font(.system(size: 14))
                        .disabled(!PracticeDetailState.shouldAllowContentEditing(mode: mode))
                    if index < steps.count,
                       let minutes = AIPracticePresentation.stepParts(steps[index]).minutes {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    if PracticeDetailState.shouldAllowContentEditing(mode: mode) && steps.count > 1 {
                        Button("删除") { steps.remove(at: index) }
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textTertiary)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < steps.count ? steps[index] : "" },
            set: { if index < steps.count { steps[index] = $0 } }
        )
    }

    private func noteCard(_ item: PracticeItem) -> some View {
        PracticeNoteSection {
            VStack(alignment: .leading, spacing: 8) {
            TextField(
                "记下卡点或这次的进步…", text: $noteText, selection: $noteSelection, axis: .vertical
            )
            .font(.system(size: 14))
            .lineLimit(3...6)
            .focused($noteFocused)
            .accessibilityIdentifier("practice.note-editor")
            .disabled(!PracticeDetailState.shouldAllowContentEditing(mode: mode))

            HStack {
                Spacer()
                if let noteAutosaver {
                    switch noteAutosaver.state {
                    case .saved: Text("已保存").font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
                    case .saving: Text("保存中…").font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
                    case .failed:
                        Button("保存失败，重试") { _ = flushNote() }
                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.statusError)
                    }
                }
            }.accessibilityIdentifier("practice.note-save-state")

            }
            .padding(12)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            toolsRow(item)
            if recorder.isRecording { recordingActivePanel(item) }
            if !visibleClips.isEmpty { clipList(item) }

            if noteAttachmentsExpanded && !isPastDayRecord {
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedNotePhotos,
                        maxSelectionCount: max(1, NoteImageStore.maximumImages - noteImages.count),
                        matching: .images
                    ) {
                        noteAttachmentTile("照片", systemImage: "photo")
                    }
                    .disabled(noteImages.count >= NoteImageStore.maximumImages)

                    Button {
                        noteCameraPresented = true
                    } label: {
                        noteAttachmentTile("拍摄", systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                    .disabled(noteImages.count >= NoteImageStore.maximumImages)

                    Button { showAttachmentImporter = true } label: {
                        noteAttachmentTile("导入文件", systemImage: "folder")
                    }
                    .disabled(attachmentImportInProgress)
                }
            }

            if attachmentImportInProgress {
                ProgressView("正在导入…").font(GitaFont.caption())
            }

            if !noteImages.isEmpty {
                HStack(spacing: 10) {
                    ForEach(noteImages) { image in
                        Button { previewNoteImage = image } label: {
                            if let photo = UIImage(contentsOfFile: image.url.path) {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看笔记图片")
                    }
                }
            }
        }
        .onChange(of: selectedNotePhotos) { _, photos in
            guard !photos.isEmpty else { return }
            Task { await importNotePhotos(photos, for: item) }
        }
        .fileImporter(isPresented: $showAttachmentImporter, allowedContentTypes: [.image, .audio, .movie], allowsMultipleSelection: false) { result in
            guard !attachmentImportInProgress else { return }
            switch result {
            case .failure(let error): show(error.localizedDescription)
            case .success(let urls):
                guard let source = urls.first else { return }
                attachmentImportInProgress = true
                Task { @MainActor in
                    defer { attachmentImportInProgress = false }
                    do {
                        try await PracticeAttachmentImporter().importFile(at: source, practiceItemID: item.id) { attachment in
                            switch attachment {
                            case .image:
                                try store.savePracticeNote(id: item.id, note: noteText, now: Date())
                            case .media(let clip):
                                guard persist(clip, item: item) else { throw store.lastError ?? StoreError.saveFailed }
                            }
                        }
                        loadNoteImages()
                    } catch { show(error.localizedDescription) }
                }
            }
        }
        .fullScreenCover(isPresented: $noteCameraPresented) {
            StillImageCameraPicker(
                isPresented: $noteCameraPresented,
                onPicked: { data in addNoteImage(data, for: item) },
                onCancel: {}
            )
            .ignoresSafeArea()
        }
        .sheet(item: $previewNoteImage) { image in
            VStack(spacing: 16) {
                HStack {
                    Button("关闭") { previewNoteImage = nil }
                    Spacer()
                    if !isPastDayRecord {
                        Button("删除图片", role: .destructive) {
                            removeNoteImage(image, for: item)
                            previewNoteImage = nil
                        }
                    }
                }
                .padding(.horizontal, 20)
                if let photo = UIImage(contentsOfFile: image.url.path) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.vertical, 20)
            .presentationDetents([.large])
        }
    }

    private func noteAttachmentTile(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 26))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(GitaTheme.textSecondary)
        .frame(width: 108, height: 96)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func beginNoteDictation(_ item: PracticeItem) {
        guard !noteVoiceHeld, !noteDictation.isFinishing else { return }
        noteVoiceHeld = true
        noteVoiceCancelArmed = false
        dictationInsertionSelection = noteSelection
        dictationInsertionText = noteText
        noteFocused = false
        if recorder.isRecording {
            recorder.stop(label: item.title)
            persistPending(item: item)
        }
        if countdown.phase == .running {
            pauseCountdownPlayback()
        } else {
            if tempoController.isRampActive { tempoController.pauseRamp() }
            practiceTimer.pause()
            metronome.stop()
        }
        Task {
            let started = await noteDictation.start()
            if !noteVoiceHeld && started {
                noteDictation.cancel()
                show("请再次按住说话")
            }
            if !started, let error = noteDictation.lastError { show(error) }
        }
    }

    private func endNoteDictation(cancelled: Bool) {
        guard noteVoiceHeld else { return }
        noteVoiceHeld = false
        noteVoiceCancelArmed = false
        if cancelled {
            noteDictation.cancel()
            dictationInsertionSelection = nil
            return
        }
        Task {
            if let text = await noteDictation.finish() {
                insertDictation(text)
                noteFocused = true
            } else if let error = noteDictation.lastError {
                show(error)
                noteFocused = true
            } else if !noteDictation.isPreparing {
                show("没有识别到语音，请重试")
            }
            dictationInsertionSelection = nil
        }
    }

    private func insertDictation(_ text: String) {
        let range: Range<String.Index>?
        if case .selection(let selection) = dictationInsertionSelection?.indices {
            range = selection
        } else {
            range = nil
        }
        let result = NoteDictationInsertion.insert(
            text, into: noteText, replacing: range, capturedText: dictationInsertionText
        )
        noteText = result.text
        let caret = noteText.index(noteText.startIndex, offsetBy: result.caretOffset)
        noteSelection = TextSelection(range: caret..<caret)
        dictationInsertionSelection = nil
    }

    private func loadNoteImages() {
        do { noteImages = try noteImageStore.images(for: itemId) }
        catch { show("无法读取笔记图片") }
    }

    private func importNotePhotos(_ photos: [PhotosPickerItem], for item: PracticeItem) async {
        defer { selectedNotePhotos = [] }
        for photo in photos where noteImages.count < NoteImageStore.maximumImages {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else {
                    show("无法读取所选图片")
                    continue
                }
                addNoteImage(data, for: item)
            } catch {
                show("无法读取所选图片")
            }
        }
    }

    private func addNoteImage(_ data: Data, for item: PracticeItem) {
        guard !isPastDayRecord else { return }
        do {
            let image = try noteImageStore.add(data, to: item.id)
            do { try store.noteImagesDidChange(for: item.id) }
            catch {
                try? noteImageStore.remove(image, from: item.id)
                throw error
            }
            loadNoteImages()
            noteAttachmentsExpanded = false
        } catch NoteImageStore.StoreError.limitReached {
            show("每次练习最多添加 3 张图片")
        } catch {
            show("无法保存笔记图片")
        }
    }

    private func removeNoteImage(_ image: NoteImage, for item: PracticeItem) {
        guard !isPastDayRecord else { return }
        do {
            try noteImageStore.remove(image, from: item.id)
            try store.noteImagesDidChange(for: item.id)
            loadNoteImages()
        } catch {
            show("无法删除笔记图片")
        }
    }

    /// Historical items stay view-only: notes, existing clips, and review remain;
    /// 录音 / 录视频 / import and the complete CTA must not start capture or persist.
    private func toolsRow(_ item: PracticeItem) -> some View {
        adaptiveLayout(spacing: 4).callAsFunction {
            noteDictationButton(item)
            tool(title: recorder.isRecording ? "录音中" : "录音", systemImage: "mic", on: recorder.isRecording) {
                toggleRecording(item)
            }
            .disabled(!PracticeDetailState.shouldAllowCapture(mode: mode))
            tool(title: "录像", systemImage: "video", on: false) {
                noteFocused = false
                recorder.cancelStart()
                player.stop()
                videoPlayURL = nil
                isSourcePresented = true
            }
            .disabled(!PracticeDetailState.shouldAllowCapture(mode: mode))
            tool(title: "添加附件", systemImage: "paperclip", on: noteAttachmentsExpanded) {
                noteFocused = false
                noteAttachmentsExpanded.toggle()
            }
            .disabled(isPastDayRecord)
            .accessibilityLabel("添加笔记图片")
        }
    }

    private func toggleRecording(_ item: PracticeItem) {
        guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return }
        noteFocused = false
        noteDictation.cancel()
        Task { @MainActor in
            if recorder.isRecording {
                recorder.stop(label: item.title)
                persistPending(item: item)
            } else {
                player.stop()
                videoPlayURL = nil
                await recorder.start(label: item.title)
                if recorder.isRecording { runtime.recordingStarted() }
            }
        }
    }

    private var metronomeEnabledBinding: Binding<Bool> {
        Binding(get: { runtime.metronomeEnabled }, set: { enabled in
            do { try runtime.setMetronomeEnabled(enabled) }
            catch { show(String(localized: "节拍器无法启动，计时仍在继续")) }
        })
    }

    private func noteDictationButton(_ item: PracticeItem) -> some View {
        Label(noteVoiceCancelArmed ? "上滑取消" : noteDictation.isFinishing ? "转文字中" : noteDictation.isRecording ? "松手转文字" : "语音输入", systemImage: "mic")
            .font(GitaFont.caption())
            .foregroundStyle(noteVoiceCancelArmed ? GitaTheme.brand500 : GitaTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !noteVoiceHeld { beginNoteDictation(item) }
                    noteVoiceCancelArmed = value.translation.height < -60
                }
                .onEnded { value in endNoteDictation(cancelled: value.translation.height < -60) }
            )
            .accessibilityLabel("语音转文字")
            .accessibilityHint("按住说话，松手转成文字，上滑取消")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if noteDictation.isRecording { endNoteDictation(cancelled: false) }
                else { beginNoteDictation(item) }
            }
            .disabled(!PracticeDetailState.shouldAllowContentEditing(mode: mode))
    }

    private func clipList(_ item: PracticeItem) -> some View {
        VStack(spacing: 10) {
            if visibleClips.isEmpty {
                VStack(spacing: 8) {
                    Text(
                        toolMode == .video
                            ? String(localized: "还没有视频")
                            : String(localized: "还没有录音")
                    )
                    .font(.system(size: 14, weight: .semibold))
                    Text(
                        toolMode == .video
                            ? String(localized: "点上方「录视频」即可拍摄或从相册导入")
                            : String(localized: "点上方「录音」即可留下片段")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(visibleClips, id: \.id) { rec in
                    clipCard(rec, taskTitle: item.title)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoPlayURL != nil },
            set: { if !$0 { videoPlayURL = nil } }
        )) {
            if let videoPlayURL {
                SystemVideoPlayer(url: videoPlayURL) {
                    self.videoPlayURL = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private func clipCard(_ rec: RecordingRef, taskTitle: String) -> some View {
        let video = MediaReviewMedia.isVideo(fileName: rec.fileName)
        let configured = llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(video ? GitaTheme.categoryBlue : GitaTheme.brand500)
                    .frame(width: 6, height: 6)
                Text(video ? String(localized: "视频记录") : String(localized: "录音记录"))
                    .font(.system(size: 12, weight: .semibold))
                Text("·")
                Text(PracticeClipQuery.timestamp(rec.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
                Spacer()
                Button {
                    presentIfFileExists(rec) {
                        metronome.stop()
                        if MediaReviewMedia.isVideo(fileName: rec.fileName) {
                            player.stop()
                            do {
                                try AudioSessionCoordinator.shared.acquire(.playback)
                                videoPlayURL = rec.fileURL
                            } catch {
                                show(String(localized: "无法播放"))
                            }
                        } else {
                            player.toggle(url: rec.fileURL, id: rec.id)
                        }
                    }
                } label: {
                    Image(systemName: player.playingId == rec.id ? "pause.fill" : "play.fill")
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 36, height: 36)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        MediaReviewMedia.isVideo(fileName: rec.fileName)
                            ? String(localized: "播放这段视频")
                            : (player.playingId == rec.id
                                ? String(localized: "暂停播放")
                                : String(localized: "播放这段录音"))
                    )
                )
            }
            Text("\(taskTitle) · \(rec.durationLabel)")
                .font(.system(size: 16, weight: .semibold))
            Text(video ? String(localized: "姿势、指法与节奏分析") : String(localized: "节奏与和弦切换分析"))
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            if !RecordingStore.fileExists(fileName: rec.fileName) {
                Text(String(localized: "文件缺失"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.statusError)
            }
            if configured {
                aiRow(rec)
            }
            if expandedReviewId == rec.id, rec.reviewStatus == .ready, !hasDiagnosis(rec) {
                reviewFields(rec)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func aiRow(_ rec: RecordingRef) -> some View {
        let running = reviewRunner.isRunning(rec.id)
        switch rec.reviewStatus {
        case .ready:
            HStack(spacing: 12) {
                Text(String(localized: "AI 复盘已生成"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Spacer()
                // A diagnosis page already shows the three fields under 总结, so the
                // inline expander stays only where the page is summary-only.
                if !hasDiagnosis(rec) {
                    Button(
                        expandedReviewId == rec.id
                            ? String(localized: "收起")
                            : String(localized: "查看复盘")
                    ) {
                        expandedReviewId = expandedReviewId == rec.id ? nil : rec.id
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                }
                if MediaReviewMedia.isVideo(fileName: rec.fileName) {
                    Button(String(localized: "查看诊断")) {
                        presentIfFileExists(rec) {
                            diagnosisRoute = VideoRoute(id: rec.id, durationSec: rec.durationSec)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                }
            }
        case .pending where running:
            Text(String(localized: "分析中")).font(.system(size: 12, weight: .semibold))
        case .pending:
            Text(String(localized: "未完成")).font(.system(size: 12, weight: .semibold))
        case .failed:
            Text(String(localized: "生成失败")).font(.system(size: 12, weight: .semibold))
        case .none:
            EmptyView()
        }
    }

    /// A video with findings reads its summary on the diagnosis page instead of
    /// expanding the card in place.
    private func hasDiagnosis(_ rec: RecordingRef) -> Bool {
        MediaReviewMedia.isVideo(fileName: rec.fileName) && !rec.videoFindings.isEmpty
    }

    private func reviewFields(_ rec: RecordingRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("亮点", rec.reviewHighlight)
            labeled("优先改善", rec.reviewFocus)
            labeled("下次练法", rec.reviewNextAction)
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            Text(body).font(.system(size: 14))
        }
    }

    private func presentIfFileExists(_ rec: RecordingRef, present: () -> Void) {
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            show(String(localized: "文件不存在或已被移除"))
            return
        }
        present()
    }

    private func recordingActivePanel(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(GitaTheme.statusError)
                    .frame(width: 8, height: 8)
                    .opacity(recorder.isPaused ? 0.35 : 1)
                Text(recorder.isPaused ? "已暂停" : "正在录音")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text(recorder.elapsedDisplay)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(GitaTheme.statusError)
            }

            HStack(spacing: 3) {
                ForEach(0..<32, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(GitaTheme.statusError.opacity(recorder.isPaused ? 0.25 : 0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: waveHeight(index))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)

            HStack(spacing: 10) {
                Button {
                    if recorder.isPaused { runtime.resumeRecordingOnly() }
                    else { runtime.pauseRecordingOnly() }
                } label: {
                    Text(recorder.isPaused ? "继续" : "暂停")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(GitaTheme.bgSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.recording.toggle-pause")

                Button {
                    recorder.stop(label: item.title)
                    persistPending(item: item)
                } label: {
                    Text("停止")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(GitaTheme.statusError)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.recording.stop")
            }
        }
        .padding(14)
        .background(GitaTheme.brand50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(GitaTheme.statusError.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.recording.active")
        .accessibilityLabel(Text("正在录音 \(recorder.elapsedDisplay)"))
    }

    private func waveHeight(_ index: Int) -> CGFloat {
        guard recorder.inputLevels.indices.contains(index) else { return 3 }
        return max(3, CGFloat(recorder.inputLevels[index]) * 28)
    }

    private func tool(
        title: String, systemImage: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? GitaTheme.brand500 : GitaTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(GitaTheme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? GitaTheme.brand500 : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: GitaTheme.shadowCard, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var timerSupportingText: String {
        guard countdown.isActive else {
            let target = item.map(initialCountdownMinutes(for:)) ?? 10
            return String(localized: "已练 / 目标 \(target):00")
        }
        let total = String(format: "%02d:%02d", countdown.configuredSeconds / 60, countdown.configuredSeconds % 60)
        switch countdown.phase {
        case .running: return String(localized: "剩余 / 共 \(total)")
        case .paused: return String(localized: "已暂停 / 共 \(total)")
        case .completed: return String(localized: "已完成 / 共 \(total)")
        case .inactive: return String(localized: "已练")
        }
    }

    private var timerPrimaryTitle: String {
        switch countdown.phase {
        case .running: return String(localized: "暂停")
        case .completed: return String(localized: "再来一次")
        case .paused: return String(localized: "继续")
        case .inactive: return practiceTimer.isRunning ? String(localized: "暂停") : String(localized: "开始")
        }
    }

    private func initialCountdownMinutes(for item: PracticeItem) -> Int {
        let target = item.targetMin > 0 ? item.targetMin : 10
        return min(60, max(1, target))
    }

    private func resetTimerCard() {
        if countdown.isActive {
            pauseCountdownPlayback()
            countdown.reset()
        } else {
            resetTrip()
        }
    }

    private func openCountdownSettings() {
        guard !tempoController.isRampActive else { return }
        if countdown.phase == .running { pauseCountdownPlayback() }
        showCountdownSettings = true
    }

    private func applyCountdownPlan(
        minutes: Int,
        wantsReminder: Bool,
        startImmediately: Bool,
        item: PracticeItem
    ) {
        Task { @MainActor in
            let reminderEnabled = wantsReminder
                ? await CountdownReminderScheduler.requestAuthorization()
                : false
            guard isItemStillOnNavigationStack else { return }
            if wantsReminder && !reminderEnabled {
                showCountdownNotificationDenied = true
            }
            runtime.saveCountdownPlan(minutes: minutes, reminderEnabled: reminderEnabled)
            if startImmediately { startCountdownPlayback(item) }
        }
    }

    private func startCountdownPlayback(_ item: PracticeItem) {
        guard countdown.phase == .paused || countdown.phase == .completed else { return }
        do { try runtime.startPractice() }
        catch { show(String(localized: "节拍器无法启动，计时仍在继续")) }
    }

    private func pauseCountdownPlayback() {
        runtime.pausePractice()
        CountdownReminderScheduler.cancel(itemId: itemId)
    }

    private func closeCountdown() {
        pauseCountdownPlayback()
        countdown.close()
    }

    private func handleCountdownCompletion(_ item: PracticeItem) {
        guard runtime.handleCountdownCompletion(label: item.title) else { return }
        persistPending(item: item)
        if countdown.reminderEnabled, scenePhase == .active {
            CountdownReminderScheduler.cancel(itemId: itemId)
            AudioServicesPlaySystemSound(1005)
            Haptics.success()
        }
    }

    private func togglePlay() {
        guard PracticeDetailState.shouldAllowTimer(mode: mode) else { return }
        if countdown.isActive {
            guard let item else { return }
            if countdown.phase == .running {
                pauseCountdownPlayback()
            } else {
                startCountdownPlayback(item)
            }
            return
        }
        if tempoController.rampState == .interrupted,
           !tempoController.interruptionRecoveryAvailable { return }
        noteFocused = false
        if practiceTimer.isRunning {
            tempoController.pauseRamp()
            updateActiveTrainingSnapshot()
            runtime.pausePractice()
            return
        }
        do {
            try runtime.resumePractice()
            if tempoController.rampState == .paused || tempoController.rampState == .interrupted {
                tempoController.resumeRamp()
                MetronomeAnalytics.emit(
                    "metronome_ramp_resumed", itemId: itemId.uuidString,
                    sessionId: activeTrainingSessionId?.uuidString ?? "",
                    ["current_bpm": String(metronome.bpm),
                     "remaining_bars": String(tempoController.remainingBarsInStage)]
                )
            }
        } catch {
            show(String(localized: "节拍器无法启动"))
        }
    }

    private func updatePlaybackPresentation() {
        let isForeground = scenePhase == .active
        metronome.foregroundFeedbackEnabled = isForeground
        UIApplication.shared.isIdleTimerDisabled = PracticeDetailState.shouldPreventScreenSleep(
            isMetronomePlaying: metronome.isPlaying,
            isForeground: isForeground
        )
    }

    private func handlePlaybackBoundary(reason: String, itemTitle: String) {
        practiceMetronomeLog.notice(
            "boundary reason=\(reason, privacy: .public) playing=\(self.metronome.isPlaying, privacy: .public) recording=\(self.recorder.isRecording, privacy: .public) ramp=\(self.tempoController.isRampActive, privacy: .public)"
        )
        tempoController.handleInterruption()
        updateActiveTrainingSnapshot()
        metronome.stop()
        practiceTimer.pause()
        if countdown.phase == .running {
            countdown.pause()
            CountdownReminderScheduler.cancel(itemId: itemId)
        }
        if recorder.isRecording { recorder.stop(label: itemTitle) }
        updatePlaybackPresentation()
    }

    private func startRamp(_ settings: TempoRampSettings) {
        guard PracticeDetailState.shouldAllowTimer(mode: mode) else { return }
        guard !countdown.isActive else {
            show(String(localized: "请先关闭倒计时再开始变速训练"))
            return
        }
        if metronome.isPreviewing { metronome.stopPreview() }
        if !metronome.isPlaying { metronome.stop() }
        let startContext = metronome.isPlaying ? "while_playing" : "from_idle"
        do {
            try saveRampPlanAndBeginSession(settings)
        } catch {
            modelContext.rollback()
            show(StoreError.from(error).localizedDescription)
            return
        }
        tempoController.startRamp(settings)
        practiceTimer.start()
        MetronomeAnalytics.emit(
            "metronome_ramp_started", itemId: itemId.uuidString,
            sessionId: activeTrainingSessionId?.uuidString ?? "",
            ["start_bpm": String(settings.startBPM), "target_bpm": String(settings.targetBPM),
             "interval_bars": String(settings.barsPerStage), "step_bpm": String(settings.stepBPM),
             "count_in_bars": String(settings.countInBars), "start_context": startContext]
        )
        do {
            try runtime.setMetronomeEnabled(true)
        } catch {
            tempoController.endRamp(cancelled: true)
            finishActiveTraining(reason: .interrupted)
            show(String(localized: "节拍器无法启动，计时仍在继续"))
            return
        }
        metronomeSheetAnchor = nil
        show(String(localized: settings.countInBars > 0 ? "预备拍开始" : "变速训练将在下一小节开始"))
    }

    private func requestExit() {
        guard !attachmentImportInProgress else { show("请等待文件导入完成"); return }
        noteFocused = false
        if isHistoricalPractice && isHistoricalEditDirty {
            leaveAfterDiscard = true
            showDiscardHistoricalChanges = true
            return
        }
        finishActiveTraining(reason: .userStopped)
        tempoController.endRamp()
        practiceTimer.pause()
        metronome.stop()
        if let item {
            if recorder.isRecording { recorder.stop(label: item.title) }
            guard flushNote(), persistPending(item: item), saveItemIfNeeded(item) else { return }
            queueProjectDeletedToastIfNeeded(for: item)
        }
        leave()
    }

    private func requestSaveHistoricalChanges() {
        guard let item else { return }
        if PracticeDetailState.projectChangeRequiresConfirmation(
            originalProjectId: item.projectId,
            draftProjectId: draftProjectId,
            isVersionMarker: isVersionMarker(item)
        ) {
            showProjectChangeWarning = true
        } else {
            saveHistoricalChanges()
        }
    }

    private func requestCreateProjectFromHistorical(_ item: PracticeItem) {
        createProjectAfterHistoricalSave = true
        if isVersionMarker(item) {
            showProjectChangeWarning = true
        } else {
            saveHistoricalChanges()
        }
    }

    private func isVersionMarker(_ item: PracticeItem) -> Bool {
        projects.contains {
            $0.stageVersionItemId == item.id || $0.finalVersionItemId == item.id
        }
    }

    private func saveHistoricalChanges() {
        guard let item else { return }
        do {
            let projectId = createProjectAfterHistoricalSave ? item.projectId : draftProjectId
            let update = HistoricalPracticeUpdate(
                title: draftTitle,
                subtitle: draftSubtitle,
                targetMin: draftTargetMin,
                category: draftCategory,
                note: noteText,
                steps: steps,
                bpm: metronome.bpm,
                timeSignature: metronome.configuredTimeSignatureText,
                metronomeAccentRaw: metronome.configuredAccentPatternRaw,
                metronomeSubdivisionRaw: metronome.configuredSubdivisionRaw,
                metronomeSoundModeRaw: metronome.soundPreset.rawValue,
                metronomeVolume: metronome.volume,
                metronomeStrongBeatBoost: metronome.strongBeatBoost,
                projectId: projectId
            )
            try store.updateHistoricalPracticeItem(id: item.id, update: update, now: Date())
            storedNote = noteText
            storedSteps = steps
            storedBpm = metronome.bpm
            storedTimeSignature = metronome.configuredTimeSignatureText
            storedAccentPatternRaw = metronome.configuredAccentPatternRaw
            storedSubdivisionRaw = metronome.configuredSubdivisionRaw
            storedMetronomeSoundModeRaw = metronome.soundPreset.rawValue
            storedMetronomeVolume = metronome.volume
            storedMetronomeStrongBeatBoost = metronome.strongBeatBoost
            draftProjectId = projectId
            show(String(localized: "修改已保存"))
            if createProjectAfterHistoricalSave {
                createProjectAfterHistoricalSave = false
                startCreateAndJoin()
            }
        } catch {
            createProjectAfterHistoricalSave = false
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func restoreHistoricalDraft() {
        guard let item else { return }
        draftTitle = item.title
        draftSubtitle = item.subtitle
        draftCategory = PracticeCategory(rawValue: item.categoryRaw) ?? .chord
        draftTargetMin = PracticeHomeState.initialTargetMin(item.targetMin)
        draftProjectId = item.projectId
        noteText = storedNote
        steps = storedSteps
        if let storedBpm { metronome.setBpm(storedBpm) }
        if let storedTimeSignature {
            metronome.configureMeter(
                timeSignature: storedTimeSignature,
                accentRaw: storedAccentPatternRaw
            )
            metronome.configureSubdivision(raw: storedSubdivisionRaw)
            metronome.configureSound(
                modeRaw: storedMetronomeSoundModeRaw,
                volume: storedMetronomeVolume,
                strongBeatBoost: storedMetronomeStrongBeatBoost
            )
        }
        createProjectAfterHistoricalSave = false
    }

    private func loadLatestRampPlan() {
        let id = itemId
        let descriptor = FetchDescriptor<TempoRampPlan>(
            predicate: #Predicate { $0.practiceItemId == id },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            if let latest = try modelContext.fetch(descriptor).first {
                tempoController.savedRampSettings = latest.settings
            }
        } catch {
            show(StoreError.from(error).localizedDescription)
        }
    }

    private func saveRampPlanAndBeginSession(_ settings: TempoRampSettings) throws {
        let id = itemId
        let descriptor = FetchDescriptor<TempoRampPlan>(
            predicate: #Predicate { $0.practiceItemId == id }
        )
        let plans = try modelContext.fetch(descriptor)
        let plan: TempoRampPlan
        if let existing = plans.first {
            existing.startBPM = settings.startBPM
            existing.targetBPM = settings.targetBPM
            existing.barsPerStage = settings.barsPerStage
            existing.stepBPM = settings.stepBPM
            existing.countInBars = settings.countInBars
            existing.meterRaw = metronome.configuredTimeSignatureText
            existing.subdivisionRaw = metronome.configuredSubdivisionRaw
            existing.accentPatternRaw = metronome.configuredAccentPatternRaw
            existing.updatedAt = Date()
            plan = existing
        } else {
            let created = TempoRampPlan(
                practiceItemId: itemId,
                settings: settings,
                meterRaw: metronome.configuredTimeSignatureText,
                subdivisionRaw: metronome.configuredSubdivisionRaw,
                accentPatternRaw: metronome.configuredAccentPatternRaw
            )
            modelContext.insert(created)
            plan = created
        }
        let session = MetronomeTrainingSession(
            practiceItemId: itemId,
            planId: plan.id,
            settings: settings,
            timeSignature: metronome.configuredTimeSignatureText,
            accentPatternRaw: metronome.configuredAccentPatternRaw,
            subdivisionRaw: metronome.configuredSubdivisionRaw
        )
        modelContext.insert(session)
        try modelContext.save()
        activeTrainingSessionId = session.id
        activeTrainingStartedAt = session.startedAt
        tempoController.savedRampSettings = settings
    }

    private func updateActiveTrainingSnapshot() {
        do {
            guard let session = try activeTrainingSession() else { return }
            session.finalBPM = metronome.bpm
            session.stableMaxBPM = tempoController.stableMaxBPM
            session.completedBars = tempoController.completedBars
            session.completedStageCount = tempoController.completedStageCount
            session.pauseCount = tempoController.pauseCount
            session.interruptionCount = tempoController.interruptionCount
            session.updatedAt = Date()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            show(StoreError.from(error).localizedDescription)
        }
    }

    private func finishActiveTraining(reason: MetronomeTrainingCompletionReason) {
        do {
            guard activeTrainingSessionId != nil else { return }
            guard let session = try activeTrainingSession() else { throw StoreError.notFound }
            session.state = .completed
            session.completionReason = reason
            session.finalBPM = metronome.bpm
            session.stableMaxBPM = tempoController.stableMaxBPM
            session.completedBars = tempoController.completedBars
            session.completedStageCount = tempoController.completedStageCount
            session.pauseCount = tempoController.pauseCount
            session.interruptionCount = tempoController.interruptionCount
            session.endedAt = Date()
            session.updatedAt = Date()
            try modelContext.save()
            self.activeTrainingSessionId = nil
            self.activeTrainingStartedAt = nil
        } catch {
            modelContext.rollback()
            show(StoreError.from(error).localizedDescription)
        }
    }

    private func activeTrainingSession() throws -> MetronomeTrainingSession? {
        guard let activeTrainingSessionId else { return nil }
        let id = activeTrainingSessionId
        let descriptor = FetchDescriptor<MetronomeTrainingSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func endRampFromSpeedSheet(selectedBPM: Int? = nil) {
        if let selectedBPM {
            tempoController.handleManualChange(selectedBPM, choice: .adjustCurrentStage)
        }
        MetronomeAnalytics.emit(
            "metronome_ramp_stopped", itemId: itemId.uuidString,
            sessionId: activeTrainingSessionId?.uuidString ?? "",
            ["current_bpm": String(metronome.bpm),
             "stable_max_bpm": String(tempoController.stableMaxBPM), "reason": "user_stopped"]
        )
        finishActiveTraining(reason: .userStopped)
        tempoController.handleManualChange(metronome.bpm, choice: .endTraining)
    }

    private func leave() {
        router.dismissPracticeDetail(fromRecord: openedFromRecord)
    }

    private func audioClip(_ clip: VideoRecorderService.Clip) -> AudioRecorderService.Clip {
        AudioRecorderService.Clip(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
    }

    @discardableResult
    private func persist(_ clip: AudioRecorderService.Clip, item: PracticeItem) -> Bool {
        guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return false }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            show(String(localized: MediaReviewMedia.isVideo(fileName: clip.fileName) ? "录像没保存" : "录音没保存"))
            return false
        }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
        do {
            try store.attachRecording(recording, toPracticeItemId: item.id)
        } catch {
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
            return false
        }
        recorder.detach(clip.id)
        video.detach(clip.id)
        if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            let clipId = clip.id
            let fileName = clip.fileName
            Task { @MainActor in
                guard await consent.ensureDecided() == .proceed else { return }
                store.markReviewsPending(recordingIds: [clipId])
                reviewRunner.enqueue([clipId], baseURL: llmBaseURL, model: llmModel)
                if MediaReviewMedia.isVideo(fileName: fileName) {
                    analysisRoute = VideoRoute(id: clipId, durationSec: clip.durationSec)
                }
            }
        }
        return true
    }

    @discardableResult
    private func persistPending(item: PracticeItem) -> Bool {
        guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return true }
        var succeeded = true
        for clip in recorder.pending { if !persist(clip, item: item) { succeeded = false } }
        for clip in video.pending { if !persist(audioClip(clip), item: item) { succeeded = false } }
        return succeeded
    }

    private func flushNote() -> Bool {
        guard let noteAutosaver else { return true }
        noteAutosaver.schedule(noteText)
        do { try noteAutosaver.flush(); storedNote = noteAutosaver.savedText; return true }
        catch { show(error.localizedDescription); return false }
    }

    @discardableResult
    private func saveItemIfNeeded(_ item: PracticeItem) -> Bool {
        guard PracticeDetailState.shouldAutoSaveOnDisappear(mode: mode, isDirty: isDirty) else {
            return true
        }
        do {
            try store.savePracticeItem(
                id: item.id,
                durationSeconds: practiceTimer.elapsedSec,
                note: noteText,
                now: Date(),
                steps: steps,
                bpm: metronome.bpm,
                timeSignature: metronome.configuredTimeSignatureText,
                metronomeAccentRaw: metronome.configuredAccentPatternRaw,
                metronomeSubdivisionRaw: metronome.configuredSubdivisionRaw,
                metronomeSoundModeRaw: metronome.soundPreset.rawValue,
                metronomeVolume: metronome.volume,
                metronomeStrongBeatBoost: metronome.strongBeatBoost
            )
            storedDurationSeconds = max(0, practiceTimer.elapsedSec)
            storedNote = noteText
            storedSteps = steps
            storedBpm = metronome.bpm
            storedTimeSignature = metronome.configuredTimeSignatureText
            storedAccentPatternRaw = metronome.configuredAccentPatternRaw
            storedSubdivisionRaw = metronome.configuredSubdivisionRaw
            storedMetronomeSoundModeRaw = metronome.soundPreset.rawValue
            storedMetronomeVolume = metronome.volume
            storedMetronomeStrongBeatBoost = metronome.strongBeatBoost
            return true
        } catch {
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
            return false
        }
    }

    /// Spec §6.5: project vanished mid-practice → independent save + toast that survives dismiss.
    /// Skips explicit 移出/更换 (session id cleared or still points at a live project).
    private func queueProjectDeletedToastIfNeeded(for item: PracticeItem) {
        guard let sessionProjectId else { return }
        guard item.projectId == nil else { return }
        guard !projects.contains(where: { $0.id == sessionProjectId }) else { return }
        router.practiceToast = String(localized: "项目已删除，本次练习已保存为独立练习")
    }

    private func resumeState(for item: PracticeItem) -> ResumeState {
        let peers = allPracticeItems.filter { $0.profileId == item.profileId }
        return PracticeItemResumeQuery.resume(
            current: PracticeItemResumeQuery.lineageItem(from: item),
            items: peers.map(PracticeItemResumeQuery.lineageItem(from:)),
            recordings: PracticeItemResumeQuery.recordings(from: peers),
            defaultBpm: 80
        )
    }

    private func resetTrip() {
        guard PracticeDetailState.shouldAllowTimer(mode: mode) else { return }
        noteFocused = false
        runtime.pausePractice()
        metronome.stop()
        practiceTimer.restore(elapsedSec: storedDurationSeconds, startedAt: nil)
    }

    private func complete(_ item: PracticeItem) {
        guard !attachmentImportInProgress else { show("请等待文件导入完成"); return }
        guard PracticeDetailState.shouldAllowComplete(mode: mode) else { return }
        guard !isCompleting else { return }
        noteFocused = false
        isCompleting = true
        recorder.cancelStart()
        finishActiveTraining(reason: .practiceFinished)
        tempoController.endRamp()
        if recorder.isRecording { recorder.stop(label: item.title) }
        practiceTimer.pause()
        metronome.stop()
        player.stop()
        videoPlayURL = nil
        guard flushNote(), persistPending(item: item), saveItemIfNeeded(item) else {
            isCompleting = false
            return
        }
        queueProjectDeletedToastIfNeeded(for: item)
        let hadContent = hasUnsavedWork
            || storedDurationSeconds > 0
            || !storedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !item.recordings.filter({ $0.deletedAt == nil }).isEmpty
        if hadContent {
            Haptics.success()
            router.lastCompletedPracticeItemId = item.id
            router.markPracticeItemCompleted(item.id)
        } else if router.practiceToast == nil {
            router.practiceToast = String(localized: "这次没有留下记录")
        }
        if !openedFromRecord {
            router.returnPracticeToToday = true
        }
        router.dismissPracticeDetail(fromRecord: openedFromRecord)
    }

    private func activeProjects(for item: PracticeItem) -> [Project] {
        projects
            .filter { $0.profileId == item.profileId && $0.status == .active }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private func projectCapsule(_ item: PracticeItem) -> some View {
        if let projectId = item.projectId,
           let name = projects.first(where: { $0.id == projectId })?.name {
            HStack {
                Text("项目 · \(name)")
                    .font(GitaFont.caption(.medium))
                    .foregroundStyle(GitaTheme.brand500)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(GitaTheme.brand50)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .highPriorityGesture(TapGesture().onEnded { _ in
                        router.showProjectDetail(projectId, fromPracticeTab: !openedFromRecord)
                    })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("项目 · \(name)")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func practiceProjectAssociation(_ item: PracticeItem) -> some View {
        if isHistoricalPractice {
            historicalProjectMenu(item)
        } else {
            associationMenu(item)
        }
    }

    private func historicalProjectMenu(_ item: PracticeItem) -> some View {
        let currentId = draftProjectId
        let candidates = activeProjects(for: item)
        let label: String = {
            if let currentId,
               let name = candidates.first(where: { $0.id == currentId })?.name
                ?? projects.first(where: { $0.id == currentId })?.name {
                return name
            }
            return String(localized: "关联项目")
        }()
        return HStack {
            Menu {
                if currentId == nil {
                    Menu("加入现有项目") {
                        ForEach(candidates, id: \.id) { project in
                            Button(project.name) { draftProjectId = project.id }
                        }
                    }
                } else {
                    Menu("更换项目") {
                        ForEach(candidates.filter { $0.id != currentId }, id: \.id) { project in
                            Button(project.name) { draftProjectId = project.id }
                        }
                    }
                    Button("移出项目") { draftProjectId = nil }
                }
                Button("建立长期项目") {
                    requestCreateProjectFromHistorical(item)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func associationMenu(_ item: PracticeItem) -> some View {
        let currentId = item.projectId
        let candidates = activeProjects(for: item)
        let label: String = {
            if let currentId,
               let name = candidates.first(where: { $0.id == currentId })?.name
                ?? projects.first(where: { $0.id == currentId })?.name {
                return name
            }
            return String(localized: "关联项目")
        }()
        HStack {
            Menu {
                if currentId == nil {
                    Menu("加入现有项目") {
                        ForEach(candidates, id: \.id) { project in
                            Button(project.name) { assignProject(project.id, to: item) }
                        }
                    }
                } else {
                    Menu("更换项目") {
                        ForEach(candidates.filter { $0.id != currentId }, id: \.id) { project in
                            Button(project.name) { assignProject(project.id, to: item) }
                        }
                    }
                    Button("移出项目") { assignProject(nil, to: item) }
                }
                Button("建立长期项目") { startCreateAndJoin() }
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func startCreateAndJoin() {
        RecordAnalytics.projectCreateEntryViewed(source: "practice_detail")
        RecordAnalytics.projectCreateStarted(source: "practice_detail")
        if isHistoricalPractice {
            awaitingCreatedProjectAssignment = true
        }
        if openedFromRecord {
            router.recordPath.append(.projectCreateFromPractice(itemId: itemId))
        } else {
            showCreateFromPracticeSheet = true
        }
    }

    private func assignProject(_ projectId: UUID?, to item: PracticeItem) {
        let from = item.projectId?.uuidString ?? ""
        do {
            try store.setPracticeItemProject(id: item.id, projectId: projectId, now: Date())
            // Track explicit leave/switch so mid-practice delete toast is not confused with them.
            sessionProjectId = item.projectId
            if projectId != nil && item.projectId == nil {
                show(String(localized: "项目已删除，本次练习已保存为独立练习"))
                RecordAnalytics.practiceProjectChanged(fromProjectId: from, toProjectId: "")
            } else {
                RecordAnalytics.practiceProjectChanged(
                    fromProjectId: from,
                    toProjectId: item.projectId?.uuidString ?? ""
                )
            }
        } catch {
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

private struct VideoRoute: Identifiable {
    var id: String
    var durationSec: Int
}
