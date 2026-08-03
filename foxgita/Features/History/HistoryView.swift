//
//  HistoryView.swift
//  foxgita
//

import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \PracticeSession.endedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var segment = 0
    @State private var month = Date()
    @State private var period = 0
    @State private var selectedDay: Date?
    @State private var toast: String?

    private var cal: Calendar { .current }
    private var summaries: [Date: DaySummary] { StatsAggregator.daySummaries(sessions: sessions, month: month) }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy 年 M 月"
        return f.string(from: month)
    }

    private var days: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let start = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = cal.component(.weekday, from: start)
        let pad = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for d in range {
            cells.append(cal.date(byAdding: .day, value: d - 1, to: start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var monthMinutes: Int { summaries.values.reduce(0) { $0 + $1.totalMinutes } }
    private var practiceDays: Int { summaries.count }
    private var longestStreak: Int { StatsAggregator.streakDays(from: sessions) }

    private var selectedSummary: DaySummary? {
        guard let selectedDay else { return summaries[cal.startOfDay(for: Date())] }
        return summaries[cal.startOfDay(for: selectedDay)]
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("练习历史").font(.system(size: 20, weight: .bold))
                            Text("回头看，也是在向前走")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        Spacer()
                        Button("今天") {
                            month = Date()
                            selectedDay = Date()
                            segment = 0
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                    }

                    SegmentedPills(titles: ["月历", "统计"], selection: $segment)

                    if segment == 0 {
                        calendarPane
                    } else {
                        statsPane
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
    }

    private var calendarPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("上月") { month = cal.date(byAdding: .month, value: -1, to: month) ?? month }
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                Spacer()
                Text(monthTitle).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("下月") { month = cal.date(byAdding: .month, value: 1, to: month) ?? month }
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GitaTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(minHeight: 52)
                    }
                }
            }
            .padding(12)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)

            MetricGrid(items: [
                ("\(practiceDays)", "练习天数"),
                ("\(monthMinutes)", "总分钟"),
                ("\(longestStreak)", "最长连续"),
            ])

            if let summary = selectedSummary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(dayTitle(summary.dayStart)).font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text("\(summary.totalMinutes) 分钟")
                            .font(.system(size: 13))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    ForEach(summary.sessions, id: \.id) { s in
                        HStack {
                            Text(s.taskTitle)
                            Spacer()
                            Text("\(s.durationMinutes) 分钟 · \(s.category.shortTag)")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 6)
                    }
                }
                .padding(14)
                .background(GitaTheme.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let start = cal.startOfDay(for: date)
        let summary = summaries[start]
        let isToday = cal.isDateInToday(date)
        let selected = selectedDay.map { cal.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            selectedDay = date
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isToday ? GitaTheme.brandOn : GitaTheme.textPrimary)
                    .frame(width: isToday ? 18 : nil, height: isToday ? 18 : nil)
                    .background(isToday ? GitaTheme.brand500 : Color.clear)
                    .clipShape(Circle())
                if let summary {
                    Text("\(summary.totalMinutes)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GitaTheme.brand500)
                    if let cat = summary.categories.first {
                        Text(cat.shortTag)
                            .font(.system(size: 9))
                            .foregroundStyle(GitaTheme.textSecondary)
                            .padding(.horizontal, 4)
                            .background(cat.accent.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(selected ? GitaTheme.brand50 : GitaTheme.bgDefault)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(GitaTheme.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var statsPane: some View {
        let interval: DateInterval = {
            switch period {
            case 1: return cal.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 86400 * 30)
            case 2: return cal.dateInterval(of: .year, for: Date()) ?? DateInterval(start: Date(), duration: 86400 * 365)
            default: return cal.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), duration: 86400 * 7)
            }
        }()
        let total = StatsAggregator.totalMinutes(sessions, in: interval)
        let prev = DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
        let prevTotal = StatsAggregator.totalMinutes(sessions, in: prev)
        let deltaPct: String = {
            guard prevTotal > 0 else { return "—" }
            let v = Int((Double(total - prevTotal) / Double(prevTotal) * 100).rounded())
            return v >= 0 ? "+\(v)%" : "\(v)%"
        }()
        let count = sessions.filter { $0.endedAt >= interval.start && $0.endedAt < interval.end }.count
        let chord = sessions.filter { $0.endedAt >= interval.start && $0.endedAt < interval.end && $0.category == .chord }
            .reduce(0) { $0 + $1.durationMinutes }
        let chart: [(String, Int)] = {
            if period == 0 {
                let map = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
                return StatsAggregator.minutesByDay(sessions: sessions, in: interval).map {
                    (map[cal.component(.weekday, from: $0.0)] ?? "", $0.1)
                }
            }
            return StatsAggregator.minutesByDay(sessions: sessions, in: interval).enumerated().map {
                ("\($0.offset + 1)", $0.element.1)
            }
        }()

        return VStack(alignment: .leading, spacing: 14) {
            SegmentedPills(titles: ["周", "月", "年"], selection: $period)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard("练琴时长", "\(total)", "分钟 · 环比 \(deltaPct)")
                statCard("连续日", "\(longestStreak)", "稳稳前行 · 不清零")
                statCard("完成次数", "\(count)", period == 0 ? "本周" : "本期")
                statCard("专项投入", "\(chord)", "和弦转换分钟")
            }

            Chart(chart, id: \.0) { p in
                BarMark(x: .value("x", p.0), y: .value("y", p.1))
                    .foregroundStyle(p.1 > 0 ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                    .cornerRadius(6)
            }
            .frame(height: 180)
            .padding(16)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                if router.role == .vip {
                    toast = "已生成分享卡片（演示）"
                } else {
                    toast = "再完成 3 次练习即可分享本周节奏"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
            } label: {
                Text("分享本周节奏")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(router.role == .vip ? GitaTheme.brandOn : GitaTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(router.role == .vip ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("语气中性，只鼓励，不制造压力")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
        }
    }

    private func statCard(_ k: String, _ v: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 12)).foregroundStyle(GitaTheme.textSecondary)
            Text(v).font(.system(size: 28, weight: .bold).monospacedDigit())
            Text(d).font(.system(size: 12)).foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M 月 d 日"
        return f.string(from: d)
    }
}
