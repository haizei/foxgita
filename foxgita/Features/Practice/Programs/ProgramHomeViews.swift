import SwiftUI

private enum ProgramScreen: String, Identifiable {
    case preferences, editor, details, training
    var id: String { rawValue }
}

struct ProgramHero: View {
    private enum Page: Hashable, CaseIterable {
        case routine, week, routinePreview
    }

    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let checkedDays: Set<String>
    @Binding var selectedDay: Date
    @Binding var weekAnchor: Date
    @State private var screen: ProgramScreen?
    @State private var page: Page? = .routine
    @ScaledMetric(relativeTo: .body) private var cardHeight = 132.0

    private var routine: PracticeRoutine { programs.savedRoutine ?? DNARecommendations.routine(for: nil) }
    private var paused: ProgramTraining? { programs.trainings.last { !$0.ended && $0.entry == .routine } }

    private func streak(through now: Date) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        if !checkedDays.contains(PracticeDayKey.make(from: day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var result = 0
        while checkedDays.contains(PracticeDayKey.make(from: day, calendar: calendar)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return result
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let days = StatsAggregator.weekDays(checkedInDayKeys: checkedDays, containing: context.date, now: context.date)
            GeometryReader { geometry in
                let summaryWidth = min(100, geometry.size.width * 0.28)
                let pageWidth = geometry.size.width - summaryWidth - 20
                HStack(spacing: 0) {
                    streakSummary(now: context.date, weekCount: days.filter(\.practiced).count)
                        .frame(width: summaryWidth, height: cardHeight)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Page.allCases, id: \.self) { item in
                                Group {
                                    if item == .week {
                                        weekCard(now: context.date)
                                    } else {
                                        routineCard
                                    }
                                }
                                .frame(width: pageWidth, height: cardHeight)
                                .background(GitaTheme.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(GitaTheme.borderSubtle, lineWidth: 0.7)
                                }
                                .id(item)
                                .accessibilityHidden(item == .routinePreview)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollPosition(id: $page, anchor: .leading)
                    .defaultScrollAnchor(.leading)
                    .frame(width: geometry.size.width - summaryWidth + 19, height: cardHeight)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("program.hero-pager")
                    .accessibilityLabel("练习方案与练习日历")
                    .accessibilityValue(page == .week ? "练习日历" : "练习方案")
                    .accessibilityScrollAction { direction in
                        withAnimation(.easeOut(duration: 0.22)) {
                            if direction == .leading { page = .week }
                            if direction == .trailing { page = .routine }
                        }
                    }
                }
            }
            .frame(height: cardHeight)
        }
        .onChange(of: page) { _, next in
            if next == .routinePreview {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { page = .routine }
            }
        }
        .sheet(item: $screen) { route in ProgramSheet(screen: route, close: { screen = nil }, change: { screen = $0 }) }
    }

    private func streakSummary(now: Date, weekCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("连续练习")
                .font(GitaFont.body(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak(through: now))")
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(GitaTheme.brand500)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("天").font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Text("本周 \(weekCount)/7")
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GitaTheme.bgSurface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                .strokeBorder(GitaTheme.borderSubtle, lineWidth: 0.7)
        }
    }

    private var routineCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Button { screen = .details } label: {
                    Text(routine.name)
                        .font(GitaFont.headline())
                        .foregroundStyle(GitaTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("program.details")
                .accessibilityValue(programs.savedRoutine == nil ? "通用方案" : "已保存方案")
                Text("\(routine.minutes) 分钟 · \(routine.exercises.count) 个分段")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exercise in
                            segmentColor(at: index)
                                .frame(width: geometry.size.width * CGFloat(exercise.minutes) / CGFloat(max(1, routine.minutes)))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if programs.beginRoutine(store: store) { screen = .training }
            } label: {
                Image("HomeRoutinePlay")
                    .frame(width: 19, height: 19)
                    .frame(width: 36, height: 36)
                    .background(GitaTheme.bgSubtle, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused == nil ? "开始方案练习" : "继续方案练习")
            .accessibilityIdentifier("program.start-routine")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func weekCard(now: Date) -> some View {
        let calendar = Calendar.current
        let isCurrentWeek = calendar.isDate(weekAnchor, inSameDayAs: StatsAggregator.week(containing: now).start)
        let days = StatsAggregator.weekDays(checkedInDayKeys: checkedDays, containing: weekAnchor, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentWeek ? "本周练习" : "历史练习")
                        .font(GitaFont.headline())
                        .accessibilityIdentifier("program.week-heading")
                    Text(isCurrentWeek ? "已练习 \(days.filter(\.practiced).count) 天，继续加油" : weekRange(now: now))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if !calendar.isDate(selectedDay, inSameDayAs: now) {
                    Button {
                        selectedDay = calendar.startOfDay(for: now)
                        weekAnchor = StatsAggregator.week(containing: now).start
                    } label: {
                        Text("今天").font(GitaFont.caption(.semibold))
                            .foregroundStyle(GitaTheme.brand500)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回到今天")
                    .accessibilityIdentifier("practice.return-today")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("practice.week-header")
            PracticeWeekPicker(
                checkedDays: checkedDays,
                selectedDay: $selectedDay,
                weekAnchor: $weekAnchor,
                now: now
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func weekRange(now: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: weekAnchor) ?? weekAnchor
        let showYear = calendar.component(.year, from: weekAnchor) != calendar.component(.year, from: now)
            || calendar.component(.year, from: end) != calendar.component(.year, from: now)
        func label(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return (showYear ? "\(parts.year ?? 0)." : "") + "\(parts.month ?? 0).\(parts.day ?? 0)"
        }
        return "\(label(weekAnchor))–\(label(end))"
    }

    private func segmentColor(at index: Int) -> Color {
        let names = ["HomeSegmentImprovisation", "HomeSegmentExpression", "HomeSegmentVocabulary", "HomeSegmentListening"]
        return Color(names[index % names.count])
    }
}

struct ProgramRecommendationsView: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let snapshots: [PracticeItemSnapshot]
    @State private var screen: ProgramScreen?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if programs.preferences == nil {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("根据偏好，找到适合你的练习").font(GitaFont.callout(.bold))
                        Text("补充信息，获取个性化推荐").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    Button { screen = .preferences } label: {
                        Text("补充信息")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.brand500)
                            .frame(width: 72, height: 34)
                            .background(GitaTheme.bgSurface, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("program.preferences")
                }
            } else {
                HStack {
                    HStack(spacing: 8) {
                        Image("HomeRecommendationSparkles").resizable().scaledToFit().frame(width: 22, height: 22)
                        Text("为你推荐").font(GitaFont.body(.bold))
                    }
                    Spacer()
                    Button("调整偏好") { screen = .preferences }.accessibilityIdentifier("program.preferences")
                }
                Text("根据你的偏好 · 每次 \(programs.preferences?.minutes ?? 30) 分钟")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(programs.candidates) { exercise in
                    let existing = programs.candidateItem(exercise, snapshots: snapshots)
                    HStack {
                        Image(exercise.category == .chord ? "HomeRecommendationChord" : "HomeRecommendationNotes")
                            .resizable().scaledToFit().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.title).font(.subheadline.bold())
                            Text("\(exercise.minutes) 分钟 · \(exercise.subtitle)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(existing == nil ? "添加" : "已添加") {
                            if let existing {
                                programs.focusedChecklistItemID = existing.id
                            } else {
                                _ = programs.addCandidate(exercise, store: store)
                            }
                        }.accessibilityIdentifier("program.add.\(exercise.id)")
                    }
                    if exercise.id != programs.candidates.last?.id { Divider() }
                }
            }
            if programs.routineDraft != nil {
                Button("查看待确认的新方案") { screen = .editor }.accessibilityIdentifier("program.draft")
                Text("当前首页方案保持原样，保存新方案后才替换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = programs.message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .background(GitaTheme.brand50, in: RoundedRectangle(cornerRadius: 20))
        .sheet(item: $screen) { route in ProgramSheet(screen: route, close: { screen = nil }, change: { screen = $0 }) }
    }
}

private struct ProgramSheet: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let screen: ProgramScreen
    let close: () -> Void
    let change: (ProgramScreen) -> Void

    var body: some View {
        NavigationStack {
            switch screen {
            case .preferences:
                DNAPreferencesView(onSubmitted: { change(.editor) }, onClose: close)
            case .editor:
                if let draft = programs.routineDraft {
                    PracticeRoutineEditor(routine: draft, onSaved: close, onClose: close)
                }
            case .details:
                Form {
                    let routine = programs.savedRoutine ?? DNARecommendations.routine(for: nil)
                    Section(routine.name) {
                        Text("\(routine.minutes) 分钟 · \(routine.exercises.count) 个分段")
                        Text(programs.savedRoutine == nil ? "通用方案 · 尚未根据你的偏好生成" : "当前已保存方案")
                    }
                    ForEach(routine.exercises) { exercise in
                        Section(exercise.title) {
                            Text(exercise.subtitle)
                            Text("\(exercise.minutes) 分钟")
                            Text(exercise.reason).font(.footnote)
                        }
                    }
                    Button("按此方案开始训练") {
                        if programs.beginRoutine(store: store) { change(.training) }
                    }
                    if programs.savedRoutine != nil {
                        Button("编辑此方案") {
                            if programs.editDraft(routine) { change(.editor) }
                        }.accessibilityIdentifier("program.edit")
                    }
                    if let message = programs.message { Text(message).foregroundStyle(.red) }
                }
                .navigationTitle("方案详情")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭", action: close) } }
            case .training:
                ProgramTrainingView(onClose: close)
            }
        }
    }
}
