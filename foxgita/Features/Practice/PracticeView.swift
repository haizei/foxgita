//
//  PracticeView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.sortOrder) private var tasks: [TaskItem]
    @Query(sort: \PracticeSession.endedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var showSheet = false

    private var todayTasks: [TaskItem] {
        tasks.filter { !$0.isTemplate && $0.status == .active }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var streak: Int { StatsAggregator.streakDays(from: sessions) }
    private var dots: [(String, StatsAggregator.WeekDot)] { StatsAggregator.weekDots(from: sessions) }
    private var weekDone: Int {
        dots.filter { $0.1 == .done }.count
    }
    private var totalTarget: Int { todayTasks.reduce(0) { $0 + $1.targetMin } }
    private var weekMinutes: Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return StatsAggregator.totalMinutes(sessions, in: interval)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "上午好" }
        if h < 18 { return "下午好" }
        return "晚上好"
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.practicePath) {
            ZStack(alignment: .bottomTrailing) {
                PageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(greeting)，\(router.displayName)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(GitaTheme.textPrimary)
                                Text("今天只练一点点")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            Spacer()
                            ZStack(alignment: .bottomTrailing) {
                                Text(String(router.displayName.prefix(1)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(GitaTheme.iconActive)
                                    .frame(width: 40, height: 40)
                                    .background(GitaTheme.brand50)
                                    .clipShape(Circle())
                                if router.role == .vip {
                                    Text("高光")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(GitaTheme.brand500)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(GitaTheme.brand50)
                                        .clipShape(Capsule())
                                        .offset(x: 4, y: 2)
                                }
                            }
                        }

                        StreakCard(streak: streak, weekDots: dots, weekDone: weekDone)

                        HStack {
                            Text("今日练习")
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text("\(todayTasks.count) 项 · \(totalTarget) 分钟")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }

                        ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in
                            TaskRowCard(task: task, solidCTA: index == 0) {
                                router.practicePath.append(.detail(taskId: task.id))
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("本周节奏")
                                    .font(.system(size: 16, weight: .bold))
                                Text("已练 \(weekDone) 天 · 累计 \(weekMinutes) 分钟")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                router.selectedTab = .record
                            } label: {
                                Text("查看记录")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(GitaTheme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(GitaTheme.bgSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 72)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                    }
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.bottom, 120)
                }

                Button {
                    showSheet = true
                } label: {
                    Text("＋")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(width: 56, height: 56)
                        .background(GitaTheme.brand500)
                        .clipShape(Circle())
                        .shadow(color: GitaTheme.shadowFab, radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PracticeRoute.self) { route in
                switch route {
                case .detail(let id): PracticeDetailView(taskId: id)
                }
            }
            .sheet(isPresented: $showSheet) {
                RecommendSheet { taskId in
                    router.practicePath.append(.detail(taskId: taskId))
                }
            }
        }
    }
}
