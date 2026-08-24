//
//  PracticeActiveTaskMergeTests.swift
//  foxgitaTests
//

import Foundation
import Testing

@testable import foxgita

@MainActor
struct PracticeActiveTaskMergeTests {
    private func makeStore(seeded: Bool = true) -> (PracticeStore, InMemoryPracticeRepository, UserDefaults) {
        let repo = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: "foxgita.tests.merge.\(UUID().uuidString)")!
        defaults.set(seeded, forKey: SeedData.seededKey)
        return (PracticeStore(repository: repo, defaults: defaults), repo, defaults)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Pure planner

    @Test func plansFoldsMultipleDailiesOntoStable() {
        let older = date(2026, 8, 18)
        let newer = date(2026, 8, 19)
        let tasks: [(id: String, deletedAt: Date?, updatedAt: Date)] = [
            ("active-tpl-chord-2026-08-18", nil, older),
            ("active-tpl-chord-2026-08-19", nil, newer),
        ]
        let plans = PracticeActiveTaskMerge.plans(
            tasks: tasks,
            effectiveSessionCount: [
                "active-tpl-chord-2026-08-18": 1,
                "active-tpl-chord-2026-08-19": 3,
            ]
        )
        #expect(plans.count == 1)
        let plan = plans[0]
        #expect(plan.canonicalId == "active-tpl-chord")
        #expect(plan.sourceTaskIds == [
            "active-tpl-chord-2026-08-18",
            "active-tpl-chord-2026-08-19",
        ])
        #expect(plan.softDeleteTaskIds == [
            "active-tpl-chord-2026-08-18",
            "active-tpl-chord-2026-08-19",
        ])
        #expect(plan.reassignSessionTaskIds == plan.sourceTaskIds)
    }

    @Test func plansPrefersExistingLiveStable() {
        let day = date(2026, 8, 19)
        let tasks: [(id: String, deletedAt: Date?, updatedAt: Date)] = [
            ("active-tpl-chord", nil, day),
            ("active-tpl-chord-2026-08-18", nil, day),
            ("active-tpl-chord-2026-08-19", nil, day),
        ]
        let plans = PracticeActiveTaskMerge.plans(
            tasks: tasks,
            effectiveSessionCount: ["active-tpl-chord-2026-08-19": 5]
        )
        #expect(plans.count == 1)
        #expect(plans[0].canonicalId == "active-tpl-chord")
        #expect(plans[0].softDeleteTaskIds == [
            "active-tpl-chord-2026-08-18",
            "active-tpl-chord-2026-08-19",
        ])
    }

    @Test func plansTombstoneOnlyDailiesDoNotCreate() {
        let day = date(2026, 8, 19)
        let tasks: [(id: String, deletedAt: Date?, updatedAt: Date)] = [
            ("active-tpl-chord-2026-08-18", day, day),
            ("active-tpl-chord-2026-08-19", day, day),
        ]
        let plans = PracticeActiveTaskMerge.plans(
            tasks: tasks,
            effectiveSessionCount: [
                "active-tpl-chord-2026-08-18": 2,
                "active-tpl-chord-2026-08-19": 4,
            ]
        )
        #expect(plans.isEmpty)
    }

    @Test func plansSkipsWhenStableIsAlreadyTombstoned() {
        let day = date(2026, 8, 19)
        let tasks: [(id: String, deletedAt: Date?, updatedAt: Date)] = [
            ("active-tpl-chord", day, day),
            ("active-tpl-chord-2026-08-19", nil, day),
        ]
        let plans = PracticeActiveTaskMerge.plans(
            tasks: tasks,
            effectiveSessionCount: ["active-tpl-chord-2026-08-19": 1]
        )
        #expect(plans.isEmpty)
    }

    @Test func applyCreatesStableFromNewerWhenSessionCountsTie() throws {
        let repo = InMemoryPracticeRepository()
        let older = date(2026, 8, 18)
        let newer = date(2026, 8, 20)
        let a = TaskItem(
            id: "active-tpl-chord-2026-08-18",
            title: "旧",
            subtitle: "",
            category: .chord,
            targetMin: 5,
            startedOn: older,
            now: older
        )
        a.updatedAt = older
        let b = TaskItem(
            id: "active-tpl-chord-2026-08-20",
            title: "新",
            subtitle: "",
            category: .chord,
            targetMin: 9,
            startedOn: newer,
            now: newer
        )
        b.updatedAt = newer
        try repo.add(a)
        try repo.add(b)
        try repo.save()
        // Equal session counts: one each.
        try repo.add(PracticeSession(
            id: "s1", taskId: a.id, taskTitle: a.title, category: .chord,
            startedAt: older, endedAt: older.addingTimeInterval(60),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.add(PracticeSession(
            id: "s2", taskId: b.id, taskTitle: b.title, category: .chord,
            startedAt: newer, endedAt: newer.addingTimeInterval(60),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.save()

        let plan = PracticeActiveTaskMerge.Plan(
            canonicalId: "active-tpl-chord",
            sourceTaskIds: [a.id, b.id].sorted(),
            softDeleteTaskIds: [a.id, b.id].sorted(),
            reassignSessionTaskIds: [a.id, b.id].sorted()
        )
        try PracticeActiveTaskMerge.apply([plan], repository: repo)

        let stable = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(stable.title == "新")
        #expect(stable.targetMin == 9)
        #expect(try repo.sessions().allSatisfy { $0.taskId == "active-tpl-chord" })
    }

    @Test func applyCreatesStableWithMaxStartedOnFromLiveSources() throws {
        let repo = InMemoryPracticeRepository()
        let past = date(2026, 8, 18)
        let today = date(2026, 8, 25)
        let pastDaily = TaskItem(
            id: "active-tpl-chord-2026-08-18",
            title: "过去赢家",
            subtitle: "past",
            category: .chord,
            targetMin: 12,
            startedOn: past,
            now: past
        )
        pastDaily.updatedAt = past
        let todayDaily = TaskItem(
            id: "active-tpl-chord-2026-08-25",
            title: "今天",
            subtitle: "today",
            category: .chord,
            targetMin: 5,
            startedOn: today,
            now: today
        )
        todayDaily.updatedAt = today
        try repo.add(pastDaily)
        try repo.add(todayDaily)
        try repo.save()

        // Past has more effective sessions; today has one.
        try repo.add(PracticeSession(
            id: "s-past-1", taskId: pastDaily.id, taskTitle: pastDaily.title, category: .chord,
            startedAt: past, endedAt: past.addingTimeInterval(60),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.add(PracticeSession(
            id: "s-past-2", taskId: pastDaily.id, taskTitle: pastDaily.title, category: .chord,
            startedAt: past.addingTimeInterval(100), endedAt: past.addingTimeInterval(160),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.add(PracticeSession(
            id: "s-today", taskId: todayDaily.id, taskTitle: todayDaily.title, category: .chord,
            startedAt: today, endedAt: today.addingTimeInterval(60),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.save()

        let plan = PracticeActiveTaskMerge.Plan(
            canonicalId: "active-tpl-chord",
            sourceTaskIds: [pastDaily.id, todayDaily.id].sorted(),
            softDeleteTaskIds: [pastDaily.id, todayDaily.id].sorted(),
            reassignSessionTaskIds: [pastDaily.id, todayDaily.id].sorted()
        )
        try PracticeActiveTaskMerge.apply([plan], repository: repo)

        let stable = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(stable.title == "过去赢家")
        #expect(stable.targetMin == 12)
        #expect(stable.startedOn == today)
    }

    @Test func applyBumpsExistingStableStartedOnFromLaterDaily() throws {
        let repo = InMemoryPracticeRepository()
        let yesterday = date(2026, 8, 24)
        let today = date(2026, 8, 25)
        let stable = TaskItem(
            id: "active-tpl-chord",
            title: "稳定",
            subtitle: "",
            category: .chord,
            targetMin: 8,
            startedOn: yesterday,
            now: yesterday
        )
        let todayDaily = TaskItem(
            id: "active-tpl-chord-2026-08-25",
            title: "今日日更",
            subtitle: "",
            category: .chord,
            targetMin: 8,
            startedOn: today,
            now: today
        )
        try repo.add(stable)
        try repo.add(todayDaily)
        try repo.save()

        let plan = PracticeActiveTaskMerge.Plan(
            canonicalId: "active-tpl-chord",
            sourceTaskIds: [todayDaily.id],
            softDeleteTaskIds: [todayDaily.id],
            reassignSessionTaskIds: [todayDaily.id]
        )
        try PracticeActiveTaskMerge.apply([plan], repository: repo)

        let updated = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(updated.startedOn == today)
        #expect(try repo.task(id: todayDaily.id) == nil)
        #expect(try repo.taskIncludingDeleted(id: todayDaily.id)?.deletedAt != nil)
    }

    @Test func applyWinnerIgnoresIneffectiveSessions() throws {
        let repo = InMemoryPracticeRepository()
        let dayA = date(2026, 8, 18)
        let dayB = date(2026, 8, 19)
        let manyIneffective = TaskItem(
            id: "active-tpl-chord-2026-08-18",
            title: "无效多",
            subtitle: "",
            category: .chord,
            targetMin: 3,
            startedOn: dayA,
            now: dayA
        )
        manyIneffective.updatedAt = dayA
        let oneEffective = TaskItem(
            id: "active-tpl-chord-2026-08-19",
            title: "有效一",
            subtitle: "",
            category: .chord,
            targetMin: 11,
            startedOn: dayB,
            now: dayB
        )
        oneEffective.updatedAt = dayB
        try repo.add(manyIneffective)
        try repo.add(oneEffective)
        try repo.save()

        // Three ineffective sessions on A (duration 0, empty note).
        for i in 1...3 {
            try repo.add(PracticeSession(
                id: "ineff-\(i)", taskId: manyIneffective.id, taskTitle: manyIneffective.title,
                category: .chord, startedAt: dayA, endedAt: dayA,
                durationSec: 0, bpm: 80, timeSig: "4/4", steps: [], noteText: ""
            ))
        }
        try repo.add(PracticeSession(
            id: "eff-1", taskId: oneEffective.id, taskTitle: oneEffective.title,
            category: .chord, startedAt: dayB, endedAt: dayB.addingTimeInterval(60),
            durationSec: 60, bpm: 80, timeSig: "4/4", steps: []
        ))
        try repo.save()

        let plan = PracticeActiveTaskMerge.Plan(
            canonicalId: "active-tpl-chord",
            sourceTaskIds: [manyIneffective.id, oneEffective.id].sorted(),
            softDeleteTaskIds: [manyIneffective.id, oneEffective.id].sorted(),
            reassignSessionTaskIds: [manyIneffective.id, oneEffective.id].sorted()
        )
        try PracticeActiveTaskMerge.apply([plan], repository: repo)

        let stable = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(stable.title == "有效一")
        #expect(stable.targetMin == 11)
    }

    // MARK: - Integration via prepare()

    @Test func prepareMergesTwoDailyActivesAndRetargetsSessions() throws {
        let (store, repo, defaults) = makeStore(seeded: true)
        #expect(defaults.bool(forKey: PracticeActiveTaskMerge.defaultsKey) == false)

        let day1 = date(2026, 8, 18)
        let day2 = date(2026, 8, 19)
        let older = TaskItem(
            id: "active-tpl-chord-2026-08-18",
            title: "和弦旧",
            subtitle: "day1",
            category: .chord,
            targetMin: 8,
            startedOn: day1,
            sortOrder: 10,
            now: day1
        )
        older.updatedAt = day1
        let newer = TaskItem(
            id: "active-tpl-chord-2026-08-19",
            title: "和弦新",
            subtitle: "day2",
            category: .chord,
            targetMin: 10,
            startedOn: day2,
            sortOrder: 10,
            now: day2
        )
        newer.updatedAt = day2
        try repo.add(older)
        try repo.add(newer)
        try repo.save()

        let s1 = PracticeSession(
            id: "s-old",
            taskId: older.id,
            taskTitle: older.title,
            category: .chord,
            startedAt: day1,
            endedAt: day1.addingTimeInterval(300),
            durationSec: 300,
            bpm: 80,
            timeSig: "4/4",
            steps: []
        )
        let s2 = PracticeSession(
            id: "s-new-a",
            taskId: newer.id,
            taskTitle: newer.title,
            category: .chord,
            startedAt: day2,
            endedAt: day2.addingTimeInterval(300),
            durationSec: 300,
            bpm: 80,
            timeSig: "4/4",
            steps: []
        )
        let s3 = PracticeSession(
            id: "s-new-b",
            taskId: newer.id,
            taskTitle: newer.title,
            category: .chord,
            startedAt: day2.addingTimeInterval(400),
            endedAt: day2.addingTimeInterval(700),
            durationSec: 300,
            bpm: 80,
            timeSig: "4/4",
            steps: []
        )
        try repo.add(s1)
        try repo.add(s2)
        try repo.add(s3)
        try repo.save()

        store.prepare()

        #expect(defaults.bool(forKey: PracticeActiveTaskMerge.defaultsKey))
        let stable = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(stable.title == "和弦新")
        #expect(stable.targetMin == 10)
        #expect(try repo.task(id: older.id) == nil)
        #expect(try repo.task(id: newer.id) == nil)
        #expect(try repo.taskIncludingDeleted(id: older.id)?.deletedAt != nil)
        #expect(try repo.taskIncludingDeleted(id: newer.id)?.deletedAt != nil)

        let sessions = try repo.sessions()
        #expect(sessions.count == 3)
        #expect(sessions.allSatisfy { $0.taskId == "active-tpl-chord" })

        // Once-gate: second prepare does not revive soft-deleted dailies.
        store.prepare()
        #expect(try repo.task(id: older.id) == nil)
        #expect(try repo.tasks().filter { PracticeTaskOrigin.parseDailyActiveId($0.id) != nil }.isEmpty)
    }

    @Test func prepareDoesNotReviveTombstoneOnlyDailies() throws {
        let (store, repo, defaults) = makeStore(seeded: true)
        let day = date(2026, 8, 19)
        let tomb = TaskItem(
            id: "active-tpl-chord-2026-08-19",
            title: "已删",
            subtitle: "",
            category: .chord,
            targetMin: 8,
            startedOn: day,
            sortOrder: 10
        )
        tomb.deletedAt = day
        try repo.add(tomb)
        try repo.save()

        store.prepare()

        #expect(defaults.bool(forKey: PracticeActiveTaskMerge.defaultsKey))
        #expect(try repo.task(id: "active-tpl-chord") == nil)
        #expect(try repo.taskIncludingDeleted(id: tomb.id)?.deletedAt != nil)
    }
}
