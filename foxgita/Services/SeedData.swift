//
//  SeedData.swift
//  foxgita
//
//  Starter content only. Persisting it is `PracticeStore`'s job.
//

import Foundation

enum SeedData {
    static let seededKey = "gita.seeded.v2"

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
        return items.enumerated().map { index, item in
            TaskItem(
                id: item.0, title: item.1, subtitle: item.2,
                category: item.3, targetMin: item.4,
                steps: ["热身", "主练习", "收尾巩固"],
                startedOn: nil, sortOrder: 100 + index, isTemplate: true
            )
        }
    }
}
