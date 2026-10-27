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
        XCTAssertTrue(app.staticTexts["今天只练一点点"].exists)
        let startPractice = app.buttons["practice.create-button"]
        XCTAssertTrue(startPractice.exists)
        XCTAssertGreaterThan(startPractice.frame.width, app.frame.width * 0.75)
        XCTAssertFalse(app.staticTexts["指尖热身"].exists)
        XCTAssertFalse(app.staticTexts["和弦转换"].exists)
        XCTAssertTrue(app.staticTexts["通用方案"].exists)
        XCTAssertTrue(app.buttons["practice.start-button"].exists)
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

    func testCreateCustomTaskOpensDetail() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "知足前奏")
        }
        let add = app.buttons["practice.create-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "创建练习")
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("知足前奏")

        app.buttons["创建练习"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["metronome.display-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists || app.staticTexts["完成本次练习"].exists)
    }

    func testMetronomeSpeedSheetMatchesCompactAndSegmentedFlows() {
        addTeardownBlock { [weak self] in
            self?.deleteCreatedTask(named: "节拍器速度测试")
        }
        XCTAssertTrue(app.buttons["practice.start-button"].waitForExistence(timeout: 5))
        app.buttons["practice.start-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("节拍器速度测试")
        app.buttons["创建练习"].tap()

        let speed = app.buttons["速度 (BPM)，打开节拍器设置"]
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
        XCTAssertTrue(app.buttons["practice.start-button"].waitForExistence(timeout: 5))
        app.buttons["practice.start-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("节拍器视觉测试")
        app.buttons["创建练习"].tap()

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

        let allBeatsTrack = app.buttons["节拍反馈：所有节拍"]
        XCTAssertTrue(allBeatsTrack.exists)
        allBeatsTrack.tap()
        XCTAssertTrue(app.buttons["节拍反馈：重音节拍"].exists)
        app.buttons["节拍反馈：重音节拍"].tap()
        XCTAssertTrue(app.buttons["节拍反馈：单摆模式"].exists)
        app.buttons["节拍反馈：单摆模式"].tap()
        XCTAssertTrue(app.buttons["节拍反馈：重音及次节拍"].exists)

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
        let add = app.buttons["practice.start-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("空完成")
        app.buttons["创建练习"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["练习记录"].exists)
    }

    func testRecommendSheetCanBeOpenedAndDismissed() {
        let add = app.buttons["practice.start-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
    }

    func testRecommendSheetShowsImageGenerateEntry() {
        let add = app.buttons["practice.start-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["拍摄/照片"].waitForExistence(timeout: 5)
            || app.staticTexts["拍摄/照片"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
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
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["项目详情"].waitForExistence(timeout: 5))
    }

    private func deleteCreatedTask(named name: String) {
        if app.buttons["返回"].waitForExistence(timeout: 1) {
            app.buttons["返回"].tap()
        }
        let row = app.descendants(matching: .any)["\(name)，10 分钟，开始"].firstMatch
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
