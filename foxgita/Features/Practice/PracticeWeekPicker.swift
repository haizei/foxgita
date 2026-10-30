import SwiftUI

/// Owns horizontal week paging independently of the hero's header swipe.
struct PracticeWeekPicker: View {
    let checkedDays: Set<String>
    @Binding var selectedDay: Date
    @Binding var weekAnchor: Date
    let now: Date

    @State private var weekStarts: [Date]
    @State private var scrolledWeek: Date?
    @State private var userIsScrolling = false
    @ScaledMetric(relativeTo: .body) private var height = 56.0

    init(checkedDays: Set<String>, selectedDay: Binding<Date>, weekAnchor: Binding<Date>, now: Date) {
        self.checkedDays = checkedDays
        _selectedDay = selectedDay
        _weekAnchor = weekAnchor
        self.now = now
        let starts = StatsAggregator.weekStarts(back: 26, from: now)
        _weekStarts = State(initialValue: starts)
        _scrolledWeek = State(initialValue: StatsAggregator.matchingWeekStart(weekAnchor.wrappedValue, in: starts))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(pagingStarts, id: \.self) { start in
                        let displayed = boundedWeek(start)
                        dates(in: displayed)
                            .frame(width: geometry.size.width)
                            .id(start)
                            .accessibilityHidden(start != displayed)
                            .allowsHitTesting(start == displayed)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            // The edge copies absorb boundary swipes. Start one page before
            // the trailing copy, on the actual current week.
            .defaultScrollAnchor(UnitPoint(x: CGFloat(weekStarts.count) / CGFloat(weekStarts.count + 1), y: 0))
            .scrollPosition(id: $scrolledWeek)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    userIsScrolling = true
                case .idle:
                    restoreBoundary()
                    if userIsScrolling { commitScrolledWeek() }
                    userIsScrolling = false
                default:
                    break
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("practice.week-days")
            .accessibilityLabel("练习日期")
            .accessibilityValue(PracticeDayKey.make(from: weekAnchor, calendar: .current))
            .accessibilityHint("左右滑动查看其他星期，点击日期查看当天练习")
            .accessibilityScrollAction { direction in
                if direction == .leading { moveWeek(by: 1) }
                if direction == .trailing { moveWeek(by: -1) }
            }
        }
        .frame(height: height)
        .onAppear { syncPager() }
        .onChange(of: scrolledWeek) { _, _ in
            restoreBoundary()
            // Layout and programmatic positioning must never select an old day.
            if userIsScrolling { commitScrolledWeek() }
        }
        .onChange(of: weekAnchor) { _, _ in syncPager() }
        .onChange(of: StatsAggregator.week(containing: now).start) { _, _ in syncPager() }
    }

    private func dates(in week: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(StatsAggregator.weekDays(checkedInDayKeys: checkedDays, containing: week, now: now)) { day in
                let selected = Calendar.current.isDate(day.date, inSameDayAs: selectedDay)
                Button { selectedDay = day.date } label: {
                    VStack(spacing: 2) {
                        Image(day.practiced ? "HomeWeekComplete" : day.isToday ? "HomeWeekToday" : "HomeWeekInactive")
                            .overlay {
                                if day.practiced {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(GitaTheme.brandOn)
                                }
                            }
                            .frame(width: 18, height: 18)
                        Text(day.weekdayLabel).font(GitaFont.caption())
                        Text("\(day.dayNumber)").font(GitaFont.micro(selected ? .semibold : .regular))
                    }
                    .foregroundStyle(day.isFuture ? GitaTheme.textTertiary : GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(selected ? GitaTheme.brand50 : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selected ? GitaTheme.brand500 : .clear, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted))，\(day.practiced ? "已练习" : "尚未练习")\(day.isToday ? "，今天" : "")")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("practice.day.\(PracticeDayKey.make(from: day.date, calendar: .current))")
            }
        }
    }

    private func commitScrolledWeek() {
        guard let next = scrolledWeek,
              weekStarts.contains(next),
              !Calendar.current.isDate(next, inSameDayAs: weekAnchor) else { return }
        weekAnchor = next
        selectedDay = StatsAggregator.clampedDay(selected: selectedDay, inWeekStarting: next, now: now)
    }

    private func moveWeek(by offset: Int) {
        guard let current = StatsAggregator.matchingWeekStart(weekAnchor, in: weekStarts),
              let index = weekStarts.firstIndex(of: current),
              weekStarts.indices.contains(index + offset) else { return }
        scrolledWeek = weekStarts[index + offset]
        commitScrolledWeek()
    }

    private func syncPager() {
        let latest = StatsAggregator.weekStarts(back: 26, from: now)
        if latest.last != weekStarts.last { weekStarts = latest }
        guard let match = StatsAggregator.matchingWeekStart(weekAnchor, in: weekStarts) else { return }
        if scrolledWeek != match { scrolledWeek = match }
    }

    private var pagingStarts: [Date] {
        guard let first = weekStarts.first, let last = weekStarts.last,
              let before = Calendar.current.date(byAdding: .day, value: -7, to: first),
              let after = Calendar.current.date(byAdding: .day, value: 7, to: last) else { return weekStarts }
        return [before] + weekStarts + [after]
    }

    private func boundedWeek(_ date: Date) -> Date {
        guard let first = weekStarts.first, let last = weekStarts.last else { return date }
        return min(last, max(first, date))
    }

    private func restoreBoundary() {
        guard let position = scrolledWeek else { return }
        let actual = boundedWeek(position)
        guard actual != position else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrolledWeek = actual }
    }
}
