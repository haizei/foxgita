//
//  RecordView.swift
//  foxgita
//

import SwiftData
import SwiftUI

enum RecordPlayback {
    /// Pause of the same id is not a failure. Start fails only when `playingIdAfter`
    /// is not the clip we meant to start.
    static func startFailed(
        playingIdBefore: String?,
        intendedId: String,
        playingIdAfter: String?
    ) -> Bool {
        if playingIdBefore == intendedId { return false }
        return playingIdAfter != intendedId
    }
}

struct RecordView: View {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]

    @State private var toast: String?
    @State private var player = AudioPlayerService()
    @State private var videoPlayURL: URL?
    @State private var showProjectComingSoon = false

    private var calendar: Calendar { .current }

    private var currentProfileId: UUID? {
        profiles.first.flatMap { UUID(uuidString: $0.id) }
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        guard let profileId = currentProfileId else { return [] }
        return practiceItems
            .filter { $0.profileId == profileId }
            .map(PracticeStore.snapshot(from:))
    }

    private var timeline: RecordTimelineState {
        RecordTimelineState.make(
            allItems: allSnapshots,
            weekContaining: router.recordWeekStart,
            now: Date(),
            calendar: calendar
        )
    }

    private var segmentIndex: Binding<Int> {
        Binding(
            get: { router.recordSegment == .practice ? 0 : 1 },
            set: { router.recordSegment = $0 == 0 ? .practice : .project }
        )
    }

    private var showPracticePane: Bool {
        router.recordSegment == .practice
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.recordPath) {
            ZStack {
                PageBackground()
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SegmentedPills(titles: ["练习", "项目"], selection: segmentIndex)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            practicePane
                        }
                        .padding(.bottom, 32)
                    }
                    .opacity(showPracticePane ? 1 : 0)
                    .allowsHitTesting(showPracticePane)
                    .overlay(alignment: .top) {
                        if !showPracticePane {
                            projectPane
                        }
                    }
                }
                .padding(.horizontal, GitaTheme.pagePadding)

                if let toast {
                    VStack {
                        Spacer()
                        ToastBanner(text: toast).padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: RecordRoute.self) { route in
                switch route {
                case .history(let segment):
                    HistoryView(initialSegment: segment)
                case .practiceDetail(let itemId):
                    PracticeDetailView(itemId: itemId, allowPastDayEdits: true, openedFromRecord: true)
                case .projectCreate:
                    ProjectEditorView(mode: .create)
                case .projectDetail:
                    Text("项目详情")
                case .projectEdit(let id):
                    ProjectEditorView(mode: .edit(id))
                }
            }
            .onAppear {
                emitViewOpened()
            }
            .onChange(of: router.recordSegment) { _, _ in
                emitViewOpened()
            }
            .onChange(of: router.recordPath) { oldPath, newPath in
                if containsHistory(oldPath) && !containsHistory(newPath) {
                    snapWeekFromFocusedDay()
                }
            }
            .onDisappear {
                player.stop()
                videoPlayURL = nil
            }
            .alert("项目创建将在下一版开放", isPresented: $showProjectComingSoon) {
                Button("知道了", role: .cancel) {}
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
    }

    private var header: some View {
        HStack {
            Text("记录")
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer()
            Button("数据统计") {
                RecordAnalytics.statsOpened(granularity: "week")
                router.recordPath.append(.history(.stats))
            }
            .font(GitaFont.callout(.semibold))
            .foregroundStyle(GitaTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var practicePane: some View {
        weekNavigator
        if !timeline.hasAnyEffectiveItem {
            emptyState(
                title: String(localized: "还没有练习记录"),
                subtitle: String(localized: "完成一次练习后，时间、笔记和媒体会保存在这里"),
                actionTitle: String(localized: "去练习")
            ) {
                router.selectedTab = .practice
            }
        } else if timeline.days.isEmpty {
            emptyState(
                title: String(localized: "这周还没有记录"),
                subtitle: String(localized: "可以切换上一周，或点日历查看其他日期")
            )
        } else {
            ForEach(timeline.days, id: \.dayKey) { group in
                dayGroup(group)
            }
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 8) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.iconPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("上一周"))

            Text(RecordTimelineRules.weekTitle(interval: timeline.weekInterval, calendar: calendar))
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.iconPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("下一周"))

            Button {
                openCalendarForToday()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.iconPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("练习历史月历"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var projectPane: some View {
        emptyState(
            title: String(localized: "用项目组织跨天目标"),
            subtitle: String(localized: "项目把多天练习收在一起，方便你持续推进一首歌或一个阶段"),
            actionTitle: String(localized: "创建项目")
        ) {
            showProjectComingSoon = true
        }
    }

    private func dayGroup(_ group: RecordTimelineDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(RecordTimelineRules.dayTitle(dayKey: group.dayKey, now: Date(), calendar: calendar))
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text("\(RecordMinutes.display(fromSeconds: group.totalSeconds)) 分钟")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    timelineRow(item)
                    if index < group.items.count - 1 {
                        Divider()
                            .overlay(GitaTheme.borderSubtle)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
        }
    }

    private func timelineRow(_ item: PracticeItemSnapshot) -> some View {
        let hasMedia = item.recordingCount > 0
        let accent = hasMedia ? nil : PracticeCategory(rawValue: item.categoryRaw)?.accent
        return HStack(spacing: 12) {
            if let accent {
                Capsule()
                    .fill(accent)
                    .frame(width: 5)
                    .frame(minHeight: 42)
            } else if hasMedia {
                Button {
                    playNewestRecording(of: item)
                } label: {
                    Image(systemName: player.playingId == newestRecordingId(of: item) ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 28, height: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("播放最近一条媒体"))
            }

            Button {
                openPractice(item)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeLabel(item.createdAt))
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                        Text(item.title)
                            .font(GitaFont.body(.bold))
                            .foregroundStyle(GitaTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Text("\(RecordMinutes.display(fromSeconds: item.durationSeconds)) 分钟")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.iconSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }

    private func emptyState(
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(GitaFont.callout(.bold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .padding(.vertical, 24)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func emitViewOpened() {
        let segment = router.recordSegment == .practice ? "practice" : "project"
        RecordAnalytics.viewOpened(segment: segment, entry: "tab")
    }

    private func shiftWeek(by weeks: Int) {
        let next = RecordTimelineRules.shiftWeek(
            interval: timeline.weekInterval,
            byWeeks: weeks,
            calendar: calendar
        )
        router.recordWeekStart = next.start
    }

    private func containsHistory(_ path: [RecordRoute]) -> Bool {
        path.contains { route in
            if case .history = route { return true }
            return false
        }
    }

    private func snapWeekFromFocusedDay() {
        guard let key = router.recordFocusDayKey,
              let start = RecordHistoryRules.weekStart(forDayKey: key, calendar: calendar)
        else { return }
        router.recordWeekStart = start
    }

    private func openCalendarForToday() {
        router.recordFocusDayKey = PracticeDayKey.make(from: Date(), calendar: calendar)
        router.recordPath.append(.history(.calendar))
    }

    private func openPractice(_ item: PracticeItemSnapshot) {
        let todayKey = PracticeDayKey.make(from: Date(), calendar: calendar)
        RecordAnalytics.practiceOpened(
            itemId: item.id.uuidString,
            practiceDay: item.practiceDayKey,
            isToday: item.practiceDayKey == todayKey
        )
        router.recordPath.append(.practiceDetail(itemId: item.id))
    }

    private func liveItem(id: UUID) -> PracticeItem? {
        practiceItems.first { $0.id == id }
    }

    private func newestRecording(of item: PracticeItemSnapshot) -> RecordingRef? {
        liveItem(id: item.id)?
            .recordings
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func newestRecordingId(of item: PracticeItemSnapshot) -> String? {
        newestRecording(of: item)?.id
    }

    private func playNewestRecording(of item: PracticeItemSnapshot) {
        guard item.recordingCount > 0, let rec = newestRecording(of: item) else {
            showToast(String(localized: "无法播放"))
            return
        }
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            showToast(String(localized: "文件不存在或已被移除"))
            return
        }
        if MediaReviewMedia.isVideo(fileName: rec.fileName) {
            player.stop()
            do {
                try AudioSessionCoordinator.shared.acquire(.playback)
                videoPlayURL = rec.fileURL
            } catch {
                showToast(String(localized: "无法播放"))
            }
        } else {
            videoPlayURL = nil
            let playingIdBefore = player.playingId
            player.toggle(url: rec.fileURL, id: rec.id)
            if RecordPlayback.startFailed(
                playingIdBefore: playingIdBefore,
                intendedId: rec.id,
                playingIdAfter: player.playingId
            ) {
                showToast(String(localized: "无法播放"))
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
