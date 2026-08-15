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
                        .font(GitaFont.footnote(.semibold))
                        .foregroundStyle(selection == i ? GitaTheme.brand500 : GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
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
    let sessions: [PracticeSession]
    let weekDone: Int
    let isCurrentWeek: Bool
    @Binding var selectedDay: Date
    @Binding var weekAnchor: Date

    @State private var weekStarts = StatsAggregator.weekStarts(back: 26)
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续练习 \(streak) 天")
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("稳稳地练，比猛练更长久")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: 180, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(isCurrentWeek ? "本周 \(weekDone)/7" : "该周 \(weekDone)/7")
                    .font(GitaFont.caption(.medium))
                    .foregroundStyle(GitaTheme.iconActive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GitaTheme.brand50)
                    .clipShape(Capsule())
            }
            TabView(selection: $weekAnchor) {
                ForEach(weekStarts, id: \.self) { start in
                    weekStrip(
                        days: StatsAggregator.weekDays(from: sessions, containing: start)
                    )
                    .tag(start)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 62)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("week-pager")
            .accessibilityHint(Text("左右滑动查看其他星期"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius24))
        .shadow(color: GitaTheme.shadowCard, radius: 10, y: 6)
        .onAppear {
            let latest = StatsAggregator.weekStarts(back: 26)
            if latest.last != weekStarts.last {
                weekStarts = latest
            }
            let start = StatsAggregator.week(containing: selectedDay).start
            if !calendar.isDate(start, inSameDayAs: weekAnchor) {
                weekAnchor = start
            }
        }
        .onChange(of: weekAnchor) { _, newStart in
            selectedDay = StatsAggregator.clampedDay(
                selected: selectedDay, inWeekStarting: newStart
            )
        }
    }

    private func weekStrip(days: [StatsAggregator.WeekDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    selectedDay = day.date
                } label: {
                    VStack(spacing: 6) {
                        Text(day.weekdayLabel)
                            .font(GitaFont.micro())
                            .foregroundStyle(labelColor(day))
                        Text("\(day.dayNumber)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(numberColor(day))
                            .frame(width: 32, height: 32)
                            .background(numberBackground(day))
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(day.weekdayLabel) \(day.dayNumber)"))
                .accessibilityAddTraits(isSelected(day) ? [.isSelected] : [])
            }
        }
    }

    private func isSelected(_ day: StatsAggregator.WeekDay) -> Bool {
        Calendar.current.isDate(day.date, inSameDayAs: selectedDay)
    }

    private func labelColor(_ day: StatsAggregator.WeekDay) -> Color {
        if day.isFuture { return GitaTheme.textTertiary }
        return isSelected(day) || day.practiced ? GitaTheme.textPrimary : GitaTheme.textSecondary
    }

    private func numberColor(_ day: StatsAggregator.WeekDay) -> Color {
        if isSelected(day) { return GitaTheme.brandOn }
        if day.isFuture { return GitaTheme.textTertiary }
        if day.practiced { return GitaTheme.brand500 }
        return GitaTheme.textPrimary
    }

    private func numberBackground(_ day: StatsAggregator.WeekDay) -> Color {
        if isSelected(day) { return GitaTheme.brand500 }
        if day.practiced { return GitaTheme.brand50 }
        return .clear
    }
}

struct TaskRowCard: View {
    let task: TaskItem
    var solidCTA: Bool = false
    var ctaTitle: String = String(localized: "开始")
    var enabled: Bool = true
    /// When embedded in `SwipeableTaskRow`, parent owns clip / shadow and taps.
    var showsShadow: Bool = true
    var action: (() -> Void)?

    var body: some View {
        let card = HStack(spacing: 12) {
            Capsule()
                .fill(task.category.accent)
                .frame(width: 5)
                .frame(minHeight: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .lineLimit(2)
                Text(task.subtitle)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(task.targetMin) 分钟")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(ctaTitle)
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(solidCTA && enabled ? GitaTheme.brandOn : GitaTheme.iconActive)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(solidCTA && enabled ? GitaTheme.brand500 : GitaTheme.brand50)
                    .clipShape(Capsule())
                    .opacity(enabled ? 1 : 0.45)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(
            showsShadow
                ? AnyShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                : AnyShape(Rectangle())
        )
        .shadow(color: showsShadow ? GitaTheme.shadowCard : .clear, radius: 8, y: 4)

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityLabel(Text("\(task.title)，\(task.targetMin) 分钟，\(ctaTitle)"))
        } else {
            card
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(task.title)，\(task.targetMin) 分钟，\(ctaTitle)"))
        }
    }
}

/// Left-swipe reveal matching Figma: gray 编辑 + red 删除.
/// The actions sit behind the row; only the card is offset, so the row keeps the
/// container's width and the buttons become tappable once uncovered.
struct SwipeRevealRow<Content: View>: View {
    let id: String
    @Binding var openRowId: String?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 72
    private var revealWidth: CGFloat { actionWidth * 2 }
    /// Stationary parent space. Measuring translation on the offset card (even
    /// `.global`) feeds the card's own displacement back into the gesture.
    private let swipeSpace = "swipe-reveal"
    private let settleSpring = Animation.spring(response: 0.28, dampingFraction: 1)
    /// Figma swipe edit fill ≈ `#b2b2bd`
    private let editFill = Color(red: 178 / 255, green: 178 / 255, blue: 189 / 255)

    private var isOpen: Bool { openRowId == id }
    private var settledOffset: CGFloat { isOpen ? -revealWidth : 0 }

    private var visualOffset: CGFloat {
        min(0, max(-revealWidth, settledOffset + dragTranslation))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        swipeAction(
                            title: String(localized: "编辑"),
                            systemImage: "square.and.pencil",
                            fill: editFill,
                            action: {
                                close()
                                onEdit()
                            }
                        )
                        swipeAction(
                            title: String(localized: "删除"),
                            systemImage: "trash",
                            fill: GitaTheme.statusError,
                            action: {
                                close()
                                onDelete()
                            }
                        )
                    }
                    .frame(width: revealWidth)
                }

            content()
                .contentShape(Rectangle())
                .offset(x: visualOffset)
                // Tap must lose to the drag, otherwise swiping opens the row's destination.
                .onTapGesture {
                    if isOpen {
                        close()
                    } else {
                        onTap()
                    }
                }
                .gesture(dragGesture)
        }
        .coordinateSpace(.named(swipeSpace))
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
        .accessibilityHint(Text("左滑可编辑或删除"))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .named(swipeSpace))
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Prefer horizontal so ScrollView vertical scroll still works.
                guard abs(horizontal) > abs(vertical) || dragTranslation != 0 else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = horizontal
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let projected = settledOffset + value.predictedEndTranslation.width
                let shouldOpen = projected < -revealWidth * 0.35 || horizontal < -revealWidth * 0.35
                // Reset translation in the same animation as open/close. Zeroing it
                // first snaps the card to `settledOffset` (a rightward jerk on left-swipe).
                withAnimation(settleSpring) {
                    dragTranslation = 0
                    if shouldOpen {
                        openRowId = id
                    } else if openRowId == id {
                        openRowId = nil
                    }
                }
            }
    }

    private func close() {
        withAnimation(settleSpring) {
            dragTranslation = 0
            if openRowId == id { openRowId = nil }
        }
    }

    private func swipeAction(
        title: String, systemImage: String, fill: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(fill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

struct SwipeableTaskRow: View {
    let task: TaskItem
    var solidCTA: Bool = false
    @Binding var openRowId: String?
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SwipeRevealRow(
            id: task.id,
            openRowId: $openRowId,
            onTap: onStart,
            onEdit: onEdit,
            onDelete: onDelete
        ) {
            TaskRowCard(task: task, solidCTA: solidCTA, showsShadow: false)
        }
    }
}

struct SwipeableSessionRow: View {
    let session: PracticeSession
    @Binding var openRowId: String?
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SwipeRevealRow(
            id: session.id,
            openRowId: $openRowId,
            onTap: onOpen,
            onEdit: onEdit,
            onDelete: onDelete
        ) {
            DaySessionCard(session: session, showsShadow: false)
        }
    }
}

struct DaySessionCard: View {
    let title: String
    let minutes: Int
    let category: PracticeCategory
    var showsShadow: Bool = true
    var action: (() -> Void)?

    init(
        title: String,
        minutes: Int,
        category: PracticeCategory,
        showsShadow: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.minutes = minutes
        self.category = category
        self.showsShadow = showsShadow
        self.action = action
    }

    init(session: PracticeSession, showsShadow: Bool = true, action: (() -> Void)? = nil) {
        self.init(
            title: session.taskTitle,
            minutes: session.durationMinutes,
            category: session.category,
            showsShadow: showsShadow,
            action: action
        )
    }

    var body: some View {
        let card = HStack(spacing: 12) {
            Capsule()
                .fill(category.accent)
                .frame(width: 5)
                .frame(minHeight: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .lineLimit(2)
                Text("已练 \(minutes) 分钟")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Text("查看")
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(GitaTheme.bgSubtle)
                .clipShape(Capsule())
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(
            showsShadow
                ? AnyShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                : AnyShape(Rectangle())
        )
        .shadow(color: showsShadow ? GitaTheme.shadowCard : .clear, radius: 8, y: 4)

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(title)，已练 \(minutes) 分钟"))
        } else {
            card
        }
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
                    .frame(width: 4)
                    .frame(minHeight: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(aggregate.task.title)
                        .font(GitaFont.callout(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    if aggregate.task.status == .done {
                        Text("已完成 · 共练 \(aggregate.sessionCount) 次")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                    } else {
                        Text("\(aggregate.lastLabel) · \(aggregate.weekCount) 次本周")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计 \(aggregate.totalMinutes) 分钟")
                        .font(GitaFont.footnote(.semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("查看详情")
                        .font(GitaFont.micro())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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
            .font(GitaFont.footnote(.semibold))
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
                        .font(GitaFont.metric())
                        .foregroundStyle(GitaTheme.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(item.1)
                        .font(GitaFont.micro())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .multilineTextAlignment(.center)
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
