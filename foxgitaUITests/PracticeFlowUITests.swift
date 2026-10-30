//
//  PracticeFlowUITests.swift
//  foxgitaUITests
//

import XCTest

/// Smoke coverage for the main practice loop. These are intentionally thin —
/// they guard against "app won't launch / can't reach a task" regressions that
/// unit tests cannot see.
final class PracticeFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    func testLaunchShowsTodayPractice() {
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["自己安排，按顺序练习"].exists)
        XCTAssertFalse(app.staticTexts["今天只练一点点"].exists)
        let startPractice = app.buttons["practice.create-button"]
        XCTAssertTrue(startPractice.exists)
        XCTAssertGreaterThan(startPractice.frame.width, app.frame.width * 0.75)
        XCTAssertFalse(app.staticTexts["指尖热身"].exists)
        XCTAssertFalse(app.staticTexts["和弦转换"].exists)
        XCTAssertTrue(app.buttons["program.details"].exists)
        XCTAssertEqual(app.buttons["program.details"].value as? String, "通用方案")
        XCTAssertEqual(app.buttons.matching(identifier: "practice.create-button").count, 1)
        let emptyToday = app.staticTexts["今天还没加练习"].exists
        // Today's cards read "N 分钟" (target); "已练 N 分钟" only appears on past days.
        let hasPracticedRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ENDSWITH '分钟，开始' OR label ENDSWITH '分钟，继续'")
        ).firstMatch.exists
        XCTAssertTrue(
            emptyToday || hasPracticedRow,
            "Home should show the empty-today copy or a daily item row, not templates"
        )
        XCTAssertFalse(app.staticTexts["还没有练习"].exists)
        XCTAssertFalse(app.staticTexts["本周节奏"].exists)
        XCTAssertFalse(app.staticTexts["当周节奏"].exists)
        XCTAssertFalse(app.staticTexts["本周次数"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '次本周'")).firstMatch.exists)
    }

    func testCompactHeroSwipesToWeekWithoutChangingTodayOrCreation() {
        let pager = app.descendants(matching: .any)["program.hero-pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let initialHeight = pager.frame.height
        XCTAssertLessThanOrEqual(initialHeight, 150)
        let play = app.buttons["program.start-routine"]
        XCTAssertTrue(play.isHittable)
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        XCTAssertEqual(play.frame.midY, pager.frame.midY, accuracy: 2)
        let homeImage = XCTAttachment(screenshot: app.screenshot())
        homeImage.name = "Home-compact-routine"
        homeImage.lifetime = .keepAlways
        add(homeImage)
        pager.swipeLeft()
        let week = app.staticTexts["program.week-heading"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(week.isHittable)
        let weekImage = XCTAttachment(screenshot: app.screenshot())
        weekImage.name = "Home-compact-week"
        weekImage.lifetime = .keepAlways
        add(weekImage)
        XCTAssertEqual(pager.frame.height, initialHeight, accuracy: 1)
        XCTAssertTrue(app.staticTexts["今日练习"].exists)
        XCTAssertTrue(app.buttons["practice.create-button"].exists)
        app.descendants(matching: .any)["practice.week-header"].firstMatch.swipeRight()
        XCTAssertTrue(app.buttons["program.details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["program.start-routine"].isHittable)
        app.buttons["practice.create-button"].tap()
        XCTAssertTrue(app.textFields["practice.create-name"].waitForExistence(timeout: 5))
    }

    func testCalendarSelectionReturnsToHistoryWithoutReplacingCompactCard() {
        let pager = app.descendants(matching: .any)["program.hero-pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let region = app.descendants(matching: .any)["practice.week-days"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let key = historyDayKey(yesterday)
        let day = app.buttons["practice.day.\(key)"]
        if !day.isHittable { region.swipeRight() }
        XCTAssertTrue(day.isHittable)
        day.tap()
        XCTAssertTrue(app.staticTexts["当天练习"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practice.selected-date"].value as? String, key)
        XCTAssertFalse(app.buttons["practice.create-button"].exists)
        XCTAssertTrue(pager.exists)
        app.buttons["practice.return-today"].tap()
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.create-button"].exists)
    }

    func testCalendarWeekSwipeDoesNotMoveOuterCarousel() {
        let pager = app.descendants(matching: .any)["program.hero-pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        let region = app.descendants(matching: .any)["practice.week-days"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let currentWeek = region.value as? String
        region.swipeRight()
        XCTAssertEqual(pager.value as? String, "练习日历")
        XCTAssertNotEqual(region.value as? String, currentWeek)
        XCTAssertTrue(app.staticTexts["当天练习"].exists)
        let previousWeek = region.value as? String
        XCTAssertEqual(app.staticTexts["practice.selected-date"].value as? String, previousWeek)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Home-history-week"
        image.lifetime = .keepAlways
        add(image)
        region.swipeLeft()
        XCTAssertEqual(region.value as? String, currentWeek)
        XCTAssertTrue(app.staticTexts["今日练习"].exists)
        region.swipeLeft()
        XCTAssertEqual(region.value as? String, currentWeek, "Cannot page into a future week")
        XCTAssertEqual(pager.value as? String, "练习日历")
        for _ in 0..<26 { region.swipeRight() }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let monday = calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: today) + 5) % 7), to: today)!
        let oldest = calendar.date(byAdding: .day, value: -26 * 7, to: monday)!
        XCTAssertEqual(region.value as? String, historyDayKey(oldest))
        region.swipeRight()
        XCTAssertEqual(region.value as? String, historyDayKey(oldest), "Cannot page earlier than the historical range")
        XCTAssertEqual(pager.value as? String, "练习日历")
        app.descendants(matching: .any)["practice.week-header"].firstMatch.swipeRight()
        XCTAssertTrue(app.buttons["program.start-routine"].isHittable)
    }

    private func historyDayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func testCreateCustomTaskOpensDetail() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "知足前奏")
        }
        let add = app.buttons["practice.create-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "创建练习")
        add.tap()
        XCTAssertTrue(app.staticTexts["创建练习"].waitForExistence(timeout: 5))

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("知足前奏")

        app.buttons["确认并创建练习"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["metronome.display-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists || app.staticTexts["完成本次练习"].exists)
    }

    func testNoteComposerShowsVoiceAndPhotoCameraStates() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "笔记输入测试")
        }
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 5))
        app.buttons["practice.create-button"].tap()
        let field = app.textFields["practice.create-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        field.typeText("笔记输入测试")
        app.buttons["确认并创建练习"].tap()

        let addImage = app.buttons["添加笔记图片"]
        if !addImage.isHittable { app.swipeUp() }
        XCTAssertTrue(addImage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["语音转文字"].exists)
        addImage.tap()
        XCTAssertTrue(app.buttons["照片"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["拍摄"].exists)
    }

    func testDictationHoldReleaseKeepsPracticeDetailResponsive() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "语音响应测试")
        }
        app.buttons["practice.create-button"].tap()
        let field = app.textFields["practice.create-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText("语音响应测试")
        app.buttons["确认并创建练习"].tap()

        let voice = app.descendants(matching: .any)["语音转文字"]
        if !voice.isHittable { app.swipeUp() }
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        voice.press(forDuration: 2)

        let addImage = app.buttons["添加笔记图片"]
        XCTAssertTrue(addImage.waitForExistence(timeout: 5))
        addImage.tap()
        XCTAssertTrue(app.buttons["照片"].waitForExistence(timeout: 5))
    }

    func testPracticeDetailSustainedPlaybackStaysResponsive() {
        let taskName = "节拍器连续播放测试"
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: taskName)
        }
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 5))
        app.buttons["practice.create-button"].tap()
        XCTAssertTrue(app.staticTexts["创建练习"].waitForExistence(timeout: 10))
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText(taskName)
        app.buttons["确认并创建练习"].tap()
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 5))
        app.buttons["开始"].tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 5))

        let exited = XCTNSPredicateExpectation(
            predicate: NSPredicate { [app] _, _ in app?.state != .runningForeground },
            object: nil
        )
        exited.isInverted = true
        // The reported exit occurs after 3–10 minutes of otherwise idle playback.
        XCTAssertEqual(XCTWaiter.wait(for: [exited], timeout: 600), .completed)
        XCTAssertTrue(app.buttons["暂停"].exists)
        let clock = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[0-9]+:[0-5][0-9]$'")
        ).firstMatch
        let parts = clock.label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        if parts.count == 2 {
            XCTAssertGreaterThanOrEqual(parts[0] * 60 + parts[1], 590)
        }
        app.buttons["暂停"].tap()
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 5))
    }

    func testMetronomeSpeedSheetMatchesCompactAndSegmentedFlows() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "节拍器速度测试")
        }
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 5))
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("节拍器速度测试")
        app.buttons["确认并创建练习"].tap()

        let speed = app.buttons["metronome.open-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        speed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["metronome.speed-sheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["TAP"].exists)
        let rampEntry = app.staticTexts["进入设置"]
        XCTAssertTrue(rampEntry.exists)
        XCTContext.runActivity(named: "Metronome Speed A Compact") { activity in
            activity.add(XCTAttachment(screenshot: app.screenshot()))
        }

        rampEntry.tap()
        if app.alerts["变速训练"].waitForExistence(timeout: 1) {
            app.alerts["变速训练"].buttons["知道了"].tap()
        }
        XCTAssertTrue(app.buttons["调速"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["测速"].exists)
        XCTAssertTrue(app.buttons["变速"].exists)
        XCTAssertTrue(app.buttons["开始变速训练"].exists)
        XCTContext.runActivity(named: "Metronome Speed B Segmented") { activity in
            activity.add(XCTAttachment(screenshot: app.screenshot()))
        }
    }

    func testMetronomeDisplayCardMatchesFigmaFrame() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "节拍器视觉测试")
        }
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 5))
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("节拍器视觉测试")
        app.buttons["确认并创建练习"].tap()

        app.buttons["拍号，打开节拍器设置"].tap()
        app.buttons["第 1 拍，强拍。轻点切换为次强拍"].tap()
        app.buttons["第 1 拍，次强拍。轻点切换为普通拍"].tap()
        app.buttons["第 2 拍，普通拍。轻点切换为静音拍"].tap()
        app.buttons["第 2 拍，静音拍。轻点切换为强拍"].tap()
        app.buttons["第 2 拍，强拍。轻点切换为次强拍"].tap()
        app.buttons["第 3 拍，普通拍。轻点切换为静音拍"].tap()
        app.buttons["第 4 拍，普通拍。轻点切换为静音拍"].tap()
        app.buttons["第 4 拍，静音拍。轻点切换为强拍"].tap()
        XCTAssertTrue(app.buttons["第 1 拍，普通拍。轻点切换为静音拍"].exists)
        XCTAssertTrue(app.buttons["第 2 拍，次强拍。轻点切换为普通拍"].exists)
        XCTAssertTrue(app.buttons["第 3 拍，静音拍。轻点切换为强拍"].exists)
        XCTAssertTrue(app.buttons["第 4 拍，强拍。轻点切换为次强拍"].exists)
        app.buttons["metronome.settings.done"].tap()

        let card = app.descendants(matching: .any)["metronome.display-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        let firstAccentBar = app.buttons["metronome.accent-beat.1"]
        XCTAssertTrue(firstAccentBar.exists)
        XCTAssertEqual(firstAccentBar.label, "第 1 拍，普通拍")
        firstAccentBar.tap()
        XCTAssertEqual(firstAccentBar.label, "第 1 拍，静音拍")

        app.buttons["metronome.open-sound-settings"].tap()
        let pendulum = app.buttons["metronome.visual.pendulum"]
        if !pendulum.isHittable { app.swipeUp() }
        XCTAssertTrue(pendulum.waitForExistence(timeout: 3))
        if pendulum.value as? String != "已选择" { pendulum.tap() }
        XCTAssertEqual(pendulum.value as? String, "已选择")
        app.buttons["metronome.sound.done"].tap()

        XCTContext.runActivity(named: "Metronome Display Card — Figma 841:140") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        XCTAssertEqual(card.frame.width, 370, accuracy: 1.5)
        XCTAssertEqual(card.frame.height, 243, accuracy: 1.5)
    }

    func testEmptyCompleteStaysOnPracticeTab() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "空完成")
        }
        let add = app.buttons["practice.create-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("空完成")
        app.buttons["确认并创建练习"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["练习记录"].exists)
    }

    func testRecommendSheetCanBeOpenedAndDismissed() {
        let add = app.buttons["practice.create-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        XCTAssertTrue(app.staticTexts["创建练习"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
    }

    func testRecommendSheetShowsImageGenerateEntry() {
        let add = app.buttons["practice.create-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["创建练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.camera"].exists)
        XCTAssertTrue(app.buttons["practice.album"].exists)
        XCTAssertTrue(app.buttons["practice.select-project"].exists)
        app.buttons["关闭"].tap()
    }

    func testCreateSheetOpensProjectSelectionWithoutCreatingPractice() {
        app.buttons["practice.create-button"].tap()
        app.buttons["practice.select-project"].tap()
        XCTAssertTrue(app.staticTexts["选择项目"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["不归项目"].exists)
        XCTAssertTrue(app.textFields["practice.project-name"].exists)
        XCTAssertFalse(app.buttons["创建并选择项目"].isEnabled)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["创建练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未选择项目"].exists)
    }

    func testSettingsAppearanceSegmentExists() {
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["主题外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["跟随系统"].exists || app.staticTexts["跟随系统"].exists)
    }

    func testRecordTabOpensFromTabBar() {
        let recordTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordTab.waitForExistence(timeout: 5))
        recordTab.tap()
        XCTAssertTrue(app.buttons["数据统计"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["项目"].exists)
    }

    func testNewProjectDetailShowsHonestEmptyStateAndStartsNewPractice() {
        let projectName = "界面验收项目\(UUID().uuidString.prefix(6))"
        app.tabBars.buttons["记录"].tap()
        app.buttons["项目"].tap()
        XCTAssertTrue(app.buttons["新建项目"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["新建项目"].firstMatch.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(projectName)
        app.buttons["创建项目"].tap()

        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[projectName].exists)
        XCTAssertTrue(app.tabBars.buttons["记录"].exists)
        XCTAssertTrue(app.staticTexts["完成第一次练习后，这里会留下练习轨迹"].exists)
        XCTAssertTrue(app.staticTexts["尚未设置当前重点"].exists)
        XCTAssertFalse(app.staticTexts["两次均为用户确认的同一片段"].exists)
        XCTContext.runActivity(named: "Project Detail Empty — Figma 1983:3") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        app.buttons["开始这项练习"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        let note = app.descendants(matching: .any)["practice.note-editor"]
        for _ in 0..<3 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("今天把节奏放慢后更稳定")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天把节奏放慢后更稳定"].exists)
        app.buttons["查看全部 ›"].tap()
        let notesHeader = app.staticTexts["我的笔记"]
        XCTAssertTrue(notesHeader.waitForExistence(timeout: 5))
        let notesSettled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in notesHeader.frame.minY < 150 },
            object: nil
        )
        let notesPosition = XCTWaiter.wait(for: [notesSettled], timeout: 5)
        XCTContext.runActivity(named: "Notes Position Diagnostic") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTAssertEqual(notesPosition, .completed, "Notes header frame: \(notesHeader.frame)")
        XCTAssertTrue(app.staticTexts["共 1 条练习笔记"].exists)
        XCTAssertTrue(app.buttons["查看练习记录 ›"].exists)
        XCTContext.runActivity(named: "Project Notes — Figma 1983:5") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
    }

    func testProjectDetailComparisonAndNotesUseConcreteRecordings() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-ProjectDetailUITestFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["练习轨迹"].exists)
        XCTAssertTrue(app.staticTexts["副歌更连贯"].exists)
        app.buttons["录音对比 ›"].tap()

        XCTAssertTrue(app.staticTexts["录音对比"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["片段未确认 · 可先交替听"].exists)
        XCTAssertTrue(app.buttons["⇄ 交替听 A / B"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '查看原练习'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AI 基于两段录音'")).firstMatch.exists)
        XCTContext.runActivity(named: "Audio Comparison — Figma 1983:4") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        app.buttons["确认片段"].tap()
        let fragment = app.textFields["例如：副歌片段"]
        XCTAssertTrue(fragment.waitForExistence(timeout: 3))
        fragment.tap()
        fragment.typeText("副歌")
        app.buttons["确认"].tap()
        XCTAssertTrue(app.staticTexts["两次均为用户确认的同一片段 · 副歌"].waitForExistence(timeout: 3))

        app.buttons["更换录音"].tap()
        app.buttons["comparison.option.a.1"].tap()
        XCTAssertTrue(app.staticTexts["片段未确认 · 可先交替听"].waitForExistence(timeout: 3))

        app.buttons["查看全部历史 ›"].tap()
        XCTAssertTrue(app.staticTexts["project-notes.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["共 2 条练习笔记"].exists)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["录音对比"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
        app.buttons["更多"].tap()
        app.buttons["完成"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["项目已完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重新开启项目"].exists)
        XCTAssertFalse(app.buttons["开始这项练习"].exists)
    }

    private func deleteCreatedTask(named name: String) {
        if app.buttons["返回"].waitForExistence(timeout: 1) {
            app.buttons["返回"].tap()
        }
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND (label ENDSWITH '分钟，开始' OR label ENDSWITH '分钟，继续')", name)
        ).firstMatch
        guard row.waitForExistence(timeout: 2) else { return }
        row.swipeLeft()
        let swipeDelete = app.buttons["删除"].firstMatch
        guard swipeDelete.waitForExistence(timeout: 2) else { return }
        swipeDelete.tap()
        let confirmDelete = app.sheets["删除练习"].buttons["删除"].firstMatch
        guard confirmDelete.waitForExistence(timeout: 2) else { return }
        confirmDelete.tap()
    }
}
