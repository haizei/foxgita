//
//  SharedUI.swift
//  foxgita
//

import SwiftUI

struct PageBackground: View {
    var body: some View {
        GitaTheme.bgDefault.ignoresSafeArea()
    }
}

struct SegmentedPills: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
                Button {
                    selection = i
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == i ? GitaTheme.brand500 : GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selection == i ? GitaTheme.bgSurface : Color.clear)
                        .clipShape(Capsule())
                        .shadow(color: selection == i ? GitaTheme.shadowCard : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(GitaTheme.bgSubtle)
        .clipShape(Capsule())
    }
}

struct StreakCard: View {
    let streak: Int
    let weekDots: [(String, StatsAggregator.WeekDot)]
    let weekDone: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续练习 \(streak) 天")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("稳稳地练，比猛练更长久")
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(width: 140, alignment: .leading)
                }
                Spacer()
                Text("本周 \(weekDone)/7")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GitaTheme.iconActive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GitaTheme.brand50)
                    .clipShape(Capsule())
            }
            HStack {
                ForEach(Array(weekDots.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(dotFill(item.1))
                            .overlay {
                                if item.1 == .today {
                                    Circle().stroke(GitaTheme.brand500, lineWidth: 2.5)
                                }
                            }
                            .frame(width: item.1 == .today ? 16 : 12, height: item.1 == .today ? 16 : 12)
                        Text(item.0)
                            .font(.system(size: 11))
                            .foregroundStyle(item.1 == .done || item.1 == .today ? GitaTheme.textPrimary : GitaTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius24))
        .shadow(color: GitaTheme.shadowCard, radius: 10, y: 6)
    }

    private func dotFill(_ state: StatsAggregator.WeekDot) -> Color {
        switch state {
        case .done: return GitaTheme.brand500
        case .today: return .clear
        case .future, .empty: return GitaTheme.iconInactive
        }
    }
}

struct TaskRowCard: View {
    let task: TaskItem
    var solidCTA: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Capsule()
                    .fill(task.category.accent)
                    .frame(width: 5, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(task.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(task.targetMin) 分钟")
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                    Text("开始")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(solidCTA ? GitaTheme.brandOn : GitaTheme.iconActive)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(solidCTA ? GitaTheme.brand500 : GitaTheme.brand50)
                        .clipShape(Capsule())
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct RecordRowCard: View {
    let aggregate: TaskAggregate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Capsule()
                    .fill(aggregate.task.category.accent)
                    .frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(aggregate.task.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    if aggregate.task.status == .done {
                        Text("已完成 · 共练 \(aggregate.sessionCount) 次")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    } else {
                        Text("\(aggregate.lastLabel) · \(aggregate.weekCount) 次本周")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计 \(aggregate.totalMinutes) 分钟")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("查看详情")
                        .font(.system(size: 11))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            .padding(14)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct ToastBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.78))
            .clipShape(Capsule())
    }
}

struct MetricGrid: View {
    let items: [(String, String)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(item.1)
                        .font(.system(size: 11))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }
}
