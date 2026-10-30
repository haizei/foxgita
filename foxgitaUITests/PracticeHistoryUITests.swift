import XCTest

final class PracticeHistoryUITests: XCTestCase {
    func testVerticalDragFromDateStripStillScrollsHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-PracticeHistoryFixture", "-PracticeHistoryLongList"]
        app.launch()
        let pager = app.descendants(matching: .any)["program.hero-pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        let region = app.descendants(matching: .any)["practice.week-days"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let originalTop = pager.frame.minY
        let week = region.value as? String
        region.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07))
        )
        XCTAssertLessThan(pager.frame.minY, originalTop - 20)
        XCTAssertEqual(region.value as? String, week)
        XCTAssertEqual(pager.value as? String, "练习日历")
    }

    func testHistoricalDayIncludesRoutineFactsAndKeepsSelectionAfterDetailAndTabReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-PracticeHistoryFixture"]
        app.launch()
        let pager = app.descendants(matching: .any)["program.hero-pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '今日日常计划，'")).firstMatch.exists)
        pager.swipeLeft()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let parts = calendar.dateComponents([.year, .month, .day], from: yesterday)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        let day = app.buttons["practice.day.\(key)"]
        if !day.isHittable { app.descendants(matching: .any)["practice.week-days"].firstMatch.swipeRight() }
        XCTAssertTrue(day.isHittable)
        day.tap()
        let routine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '昨天方案分段，方案练习，'")).firstMatch
        let daily = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '昨日日常练习，日常练习，'")).firstMatch
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        XCTAssertTrue(daily.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '昨天未开始计划'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["2 项 · 12 分钟"].exists)
        XCTAssertFalse(app.buttons["practice.create-button"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Home-history-routine-and-daily"
        image.lifetime = .keepAlways
        add(image)
        routine.tap()
        XCTAssertTrue(app.buttons["返回"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["practice.toggle-running"].isEnabled)
        if app.buttons["录音"].exists { XCTAssertFalse(app.buttons["录音"].isEnabled) }
        let note = app.descendants(matching: .any)["practice.note-editor"].firstMatch
        for _ in 0..<3 where !note.isHittable { app.swipeUp() }
        XCTAssertEqual(note.value as? String, "方案历史笔记")
        app.buttons["返回"].firstMatch.tap()
        let selectedDate = app.staticTexts["practice.selected-date"]
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedDate.value as? String, key)
        app.tabBars.buttons["记录"].tap()
        app.tabBars.buttons["练习"].tap()
        XCTAssertEqual(selectedDate.value as? String, key)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '昨天方案分段，'")).count, 1)
        app.buttons["practice.return-today"].tap()
        XCTAssertTrue(app.staticTexts["今日练习"].exists)
        XCTAssertTrue(app.buttons["practice.create-button"].exists)
    }
}
