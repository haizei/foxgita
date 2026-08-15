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
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "连续练习"))
                .firstMatch.exists
        )
        XCTAssertFalse(app.staticTexts["指尖热身"].exists)
        XCTAssertFalse(app.staticTexts["和弦转换"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["week-pager"].exists)
    }

    func testCreateCustomTaskOpensDetail() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("知足前奏")

        app.buttons["创建练习"].tap()
        XCTAssertTrue(app.staticTexts["节拍器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists || app.staticTexts["完成本次练习"].exists)
    }

    func testEmptyCompleteStaysOnPracticeTab() {
        let add = app.buttons["添加练习"]
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
        XCTAssertTrue(app.buttons["拍摄/照片"].waitForExistence(timeout: 5)
            || app.staticTexts["拍摄/照片"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }

    func testSettingsAppearanceSegmentExists() {
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["主题外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["跟随系统"].exists || app.staticTexts["跟随系统"].exists)
    }
}
