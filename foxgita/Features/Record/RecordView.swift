//
//  RecordView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(AppRouter.self) private var router
    @Query(
        filter: #Predicate<TaskItem> { !$0.isTemplate && $0.deletedAt == nil },
        sort: \TaskItem.sortOrder
    )
    private var tasks: [TaskItem]
    @Query(
        filter: #Predicate<PracticeSession> { $0.deletedAt == nil },
        sort: \PracticeSession.endedAt, order: .reverse
    )
    private var sessions: [PracticeSession]
    @State private var filter = 0

    private var aggregates: [TaskAggregate] {
        StatsAggregator.aggregate(tasks: tasks, sessions: sessions)
    }

    private var filtered: [TaskAggregate] {
        aggregates.filter { filter == 0 ? $0.task.status == .active : $0.task.status == .done }
    }

    private var weekCount: Int {
        let week = StatsAggregator.week()
        return sessions.filter { $0.endedAt >= week.start && $0.endedAt < week.end }.count
    }

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + $1.durationMinutes }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.recordPath) {
            ZStack {
                PageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("练习记录")
                                    .font(GitaFont.title())
                                Text("把每一次进步留在这里")
                                    .font(GitaFont.caption())
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            Spacer()
                            Button("数据统计") {
                                router.selectedTab = .history
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(GitaTheme.textSecondary)
                        }

                        SegmentedPills(titles: ["进行中", "已完成"], selection: $filter)

                        MetricGrid(items: [
                            ("\(filtered.count)", filter == 0 ? "进行中" : "已完成"),
                            ("\(weekCount)", "本周次数"),
                            ("\(totalMinutes)", "累计分钟"),
                        ])

                        HStack {
                            Text("继续积累").font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text("最近更新")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }

                        if filtered.isEmpty {
                            VStack(spacing: 12) {
                                Text(filter == 0 ? "还没有进行中的练习" : "完成一次练习后会出现在这里")
                                    .font(.system(size: 14, weight: .semibold))
                                if filter == 0 {
                                    Button("去练习") { router.selectedTab = .practice }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(GitaTheme.brandOn)
                                        .padding(.horizontal, 20)
                                        .frame(height: 40)
                                        .background(GitaTheme.brand500)
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filtered) { item in
                                RecordRowCard(aggregate: item) {
                                    router.recordPath.append(.detail(taskId: item.id))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: RecordRoute.self) { route in
                switch route {
                case .detail(let id): RecordDetailView(taskId: id)
                }
            }
        }
    }
}
