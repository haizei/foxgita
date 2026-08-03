//
//  SeedData.swift
//  foxgita
//

import Foundation
import SwiftData

enum SeedData {
    private static let key = "gita.seeded.v2"

    static func seedIfNeeded(context: ModelContext) {
        // Reset if migrating from v1 teal app
        if UserDefaults.standard.bool(forKey: "gita.seeded.v1") && !UserDefaults.standard.bool(forKey: key) {
            try? context.delete(model: RecordingRef.self)
            try? context.delete(model: PracticeSession.self)
            try? context.delete(model: TaskItem.self)
            UserDefaults.standard.removeObject(forKey: "gita.seeded.v1")
        }
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        for t in todayTasks() { context.insert(t) }
        for t in templates() { context.insert(t) }
        for s in demoSessions() { context.insert(s) }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    static func todayTasks() -> [TaskItem] {
        [
            TaskItem(
                id: "warm", title: "指尖热身", subtitle: "开放弦与爬格子",
                category: .left, targetMin: 5,
                steps: ["开放弦拨弦", "一二三四指上行", "下行回位"],
                sortOrder: 0
            ),
            TaskItem(
                id: "chord", title: "和弦转换", subtitle: "C · G · Am · F",
                category: .chord, targetMin: 8, defaultBpm: 80,
                steps: ["慢速分解转换", "四拍完整循环", "跟节拍器连贯练习"],
                sortOrder: 1
            ),
            TaskItem(
                id: "rhythm", title: "节奏训练", subtitle: "八分音符扫弦",
                category: .rhythm, targetMin: 7, defaultBpm: 70,
                steps: ["熟悉下下上上下上", "跟 60 BPM 慢扫", "跟 80 BPM 加速"],
                sortOrder: 2
            ),
            TaskItem(
                id: "song", title: "歌曲练习", subtitle: "《小星星》分句练习",
                category: .song, targetMin: 10, defaultBpm: 80,
                steps: ["熟悉和弦序", "跟唱主歌", "整曲过一遍"],
                sortOrder: 3
            ),
            TaskItem(
                id: "four-done", title: "入门四和弦", subtitle: "已完成 · 共练 8 次",
                category: .chord, targetMin: 15,
                steps: ["C", "G", "Am", "Em"],
                status: .done,
                startedOn: Calendar.current.date(byAdding: .day, value: -20, to: Date()),
                sortOrder: 99
            ),
        ]
    }

    static func templates() -> [TaskItem] {
        let items: [(String, String, String, PracticeCategory, Int)] = [
            ("tpl-span", "跨度练习", "8 分钟 · 轻量开始", .left, 8),
            ("tpl-finger", "无名指强化", "6 分钟 · 轻量开始", .left, 6),
            ("tpl-strum", "扫弦基础", "6 分钟 · 轻量开始", .right, 6),
            ("tpl-mute", "闷音练习", "5 分钟 · 轻量开始", .right, 5),
            ("tpl-coord", "手脚协调", "8 分钟 · 轻量开始", .both, 8),
            ("tpl-scale", "C 大调音阶", "10 分钟 · 轻量开始", .scale, 10),
            ("tpl-eighth", "八分音符", "8 分钟 · 轻量开始", .rhythm, 8),
            ("tpl-twinkle", "小星星整曲", "12 分钟 · 轻量开始", .song, 12),
        ]
        return items.enumerated().map { idx, item in
            TaskItem(
                id: item.0, title: item.1, subtitle: item.2,
                category: item.3, targetMin: item.4,
                steps: ["热身", "主练习", "收尾巩固"],
                startedOn: nil, sortOrder: 100 + idx, isTemplate: true
            )
        }
    }

    private static func demoSessions() -> [PracticeSession] {
        let cal = Calendar.current
        let now = Date()
        var list: [PracticeSession] = []
        let specs: [(String, String, PracticeCategory, Int, Int)] = [
            ("chord", "和弦转换", .chord, 0, 12 * 60),
            ("rhythm", "节奏训练", .rhythm, 0, 10 * 60),
            ("warm", "指尖热身", .left, 0, 8 * 60),
            ("chord", "和弦转换", .chord, 1, 8 * 60),
            ("song", "歌曲练习", .song, 2, 10 * 60),
            ("rhythm", "节奏训练", .rhythm, 3, 12 * 60),
            ("chord", "和弦转换", .chord, 4, 14 * 60),
            ("warm", "指尖热身", .left, 5, 5 * 60),
            ("four-done", "入门四和弦", .chord, 10, 20 * 60),
        ]
        for (id, title, cat, daysAgo, sec) in specs {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let start = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
            list.append(PracticeSession(
                taskId: id, taskTitle: title, category: cat,
                startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(sec)),
                durationSec: sec, bpm: 80, timeSig: "4/4",
                steps: [], noteText: daysAgo == 0 ? "今天的 F 和弦按得更稳了" : ""
            ))
        }
        return list
    }

    static func ensureActive(from template: TaskItem, context: ModelContext) -> TaskItem {
        if !template.isTemplate { return template }
        let eid = "active-\(template.id)"
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == eid })
        if let existing = try? context.fetch(d).first { return existing }
        let copy = TaskItem(
            id: eid, title: template.title, subtitle: template.subtitle,
            category: template.category, targetMin: template.targetMin,
            defaultBpm: template.defaultBpm, timeSig: template.timeSig,
            steps: template.steps, status: .active, startedOn: Date(),
            sortOrder: template.sortOrder, isTemplate: false
        )
        context.insert(copy)
        try? context.save()
        return copy
    }

    static func createCustom(name: String, minutes: Int, context: ModelContext) -> TaskItem {
        let task = TaskItem(
            id: "custom-\(UUID().uuidString)",
            title: name.isEmpty ? "未命名练习" : name,
            subtitle: "自定义 · \(minutes) 分钟",
            category: .chord, targetMin: minutes,
            steps: ["新步骤"],
            startedOn: Date(), sortOrder: 50
        )
        context.insert(task)
        try? context.save()
        return task
    }
}
