//
//  RecordDetailView.swift
//  foxgita
//

import Charts
import SwiftData
import SwiftUI

struct RecordDetailView: View {
    let taskId: String
    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [PracticeSession]
    @State private var tab = 0
    @State private var player = AudioPlayerService()

    init(taskId: String) {
        self.taskId = taskId
        _tasks = Query(
            filter: #Predicate<TaskItem> { $0.id == taskId && $0.deletedAt == nil },
            sort: \.sortOrder
        )
        _sessions = Query(
            filter: #Predicate<PracticeSession> { $0.taskId == taskId && $0.deletedAt == nil },
            sort: \.endedAt,
            order: .reverse
        )
    }

    private var task: TaskItem? { tasks.first }
    private var totalMinutes: Int { sessions.reduce(0) { $0 + $1.durationMinutes } }

    private var currentWeek: DateInterval { StatsAggregator.week() }

    private var weekPoints: [(String, Int)] {
        StatsAggregator.minutesByDay(sessions: sessions, in: currentWeek).map {
            (StatsAggregator.weekdaySymbol(for: $0.0), $0.1)
        }
    }

    private var weekCount: Int {
        let week = currentWeek
        return sessions.filter { $0.endedAt >= week.start && $0.endedAt < week.end }.count
    }

    private var avgMin: Int {
        let nonzero = weekPoints.filter { $0.1 > 0 }
        guard !nonzero.isEmpty else { return 0 }
        return nonzero.reduce(0) { $0 + $1.1 } / nonzero.count
    }

    private var notes: [(Date, String)] {
        sessions.filter { !$0.noteText.isEmpty }.map { ($0.endedAt, $0.noteText) }
    }

    private var recordings: [RecordingRef] {
        sessions.flatMap(\.recordings).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button("返回") { router.recordPath.removeAll() }
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text("记录详情")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Text("更多")
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task?.title ?? "练习")
                                        .font(.system(size: 18, weight: .bold))
                                    Text(task?.subtitle ?? "")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(totalMinutes)")
                                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                                    Text("累计分钟")
                                        .font(.system(size: 11))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(GitaTheme.bgSubtle).frame(height: 8)
                                    Capsule().fill(GitaTheme.brand500)
                                        .frame(width: geo.size.width * min(1, CGFloat(totalMinutes) / 100), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(18)
                        .background(GitaTheme.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)

                        SegmentedPills(titles: ["数据", "录音", "笔记"], selection: $tab)

                        Group {
                            switch tab {
                            case 1: audioPane
                            case 2: notePane
                            default: dataPane
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { player.stop() }
    }

    private var dataPane: some View {
        VStack(spacing: 14) {
            MetricGrid(items: [
                ("\(weekCount)", "本周次数"),
                ("\(avgMin)", "平均分钟"),
                (StatsAggregator.deltaLabel(sessions, in: currentWeek), "环比"),
            ])
            Chart(weekPoints, id: \.0) { p in
                BarMark(x: .value("d", p.0), y: .value("m", p.1))
                    .foregroundStyle(p.1 > 0 ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                    .cornerRadius(6)
            }
            .frame(height: 160)
            .padding(16)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var audioPane: some View {
        Group {
            if recordings.isEmpty {
                empty("还没有录音", "在练习详情点「录音」即可留下片段")
            } else {
                VStack(spacing: 10) {
                    ForEach(recordings, id: \.id) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(timeLabel(r.createdAt))
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(r.durationLabel)\(r.label.isEmpty ? "" : " · \(r.label)")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                player.toggle(url: r.fileURL, id: r.id)
                            } label: {
                                Image(systemName: player.playingId == r.id ? "pause.fill" : "play.fill")
                                    .foregroundStyle(GitaTheme.brand500)
                                    .frame(width: 36, height: 36)
                                    .background(GitaTheme.brand50)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                Text(player.playingId == r.id ? "暂停播放" : "播放这段录音")
                            )
                        }
                        .padding(14)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var notePane: some View {
        Group {
            if notes.isEmpty {
                empty("还没有笔记", "练完写一点感受，以后回看会很有用")
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dayLabel(n.0))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GitaTheme.textSecondary)
                            Text(n.1).font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func empty(_ t: String, _ s: String) -> some View {
        VStack(spacing: 8) {
            Text(t).font(.system(size: 14, weight: .semibold))
            Text(s).font(.system(size: 13)).foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func timeLabel(_ d: Date) -> String {
        d.formatted(.dateTime.month().day().hour().minute())
    }

    private func dayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.month().day())
    }
}
