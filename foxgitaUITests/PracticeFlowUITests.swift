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
    }

    func testStartFirstTaskOpensDetail() {
        // Seeded first card CTA.
        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开始")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["节拍器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists || app.staticTexts["完成本次练习"].exists)
    }

    func testRecommendSheetCanBeOpenedAndDismissed() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts["今日练习"].waitForExistence(timeout: 5))
    }

    func testRecommendSheetShowsImageGenerateEntry() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从图片生成练习"].waitForExistence(timeout: 5)
            || app.staticTexts["从图片生成练习"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }

    func testSettingsAppearanceSegmentExists() {
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["主题外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["跟随系统"].exists || app.staticTexts["跟随系统"].exists)
    }
}
