import XCTest

final class ToolsTabUITests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(zh-Hans)"] + arguments
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        return app
    }

    func testToolsTabShowsGroupedCatalog() {
        let app = launch()
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertTrue(app.staticTexts["节奏与和弦"].exists)
        XCTAssertTrue(app.staticTexts["调音"].exists)
        XCTAssertTrue(app.staticTexts["听觉与演奏"].exists)
        XCTAssertTrue(app.staticTexts["8 款工具"].exists)
        let ids = ["metronome", "chords", "tuner", "alternateTuning", "chromaticTuner", "playAlong", "playChords", "chordMemory"]
        for id in ids {
            let row = app.buttons["tools.item.\(id)"]
            for _ in 0..<3 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, id)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        }
        capture(app, name: "Tools-A-grouped")
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.staticTexts["记录"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["主题外观"].waitForExistence(timeout: 5))
        app.tabBars.buttons["练习"].tap()
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 5))
    }

    func testUnavailableToolExplainsItsStatusAndReturnsToCatalog() {
        let app = launch()
        app.buttons["tools.item.chords"].tap()
        XCTAssertTrue(app.alerts["和弦库"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["这项工具尚未开放，敬请期待。"].exists)
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["tools.item.metronome"].isHittable)
    }

    func testStandaloneMetronomeCanPlayConfigureAndReturn() {
        let app = launch()
        app.buttons["tools.item.metronome"].tap()
        let toggle = app.buttons["tools.metronome.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "开始播放")
        toggle.tap()
        XCTAssertEqual(toggle.label, "暂停播放")
        toggle.tap()
        XCTAssertEqual(toggle.label, "开始播放")
        app.buttons["metronome.open-speed"].tap()
        XCTAssertTrue(app.buttons["metronome.speed.handle"].waitForExistence(timeout: 5))
        app.buttons["metronome.speed.handle"].tap()
        app.buttons["metronome.open-sound-settings"].tap()
        XCTAssertTrue(app.buttons["metronome.sound.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["录音"].exists)
        app.buttons["metronome.sound.done"].tap()
        toggle.tap()
        app.tabBars.buttons["设置"].tap()
        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "开始播放", "Leaving tools must stop its audio")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["tools.item.metronome"].waitForExistence(timeout: 5))
    }

    func testLargeTextCatalogCanScrollToLastTool() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let last = app.buttons["tools.item.chordMemory"]
        for _ in 0..<10 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxX, app.frame.maxX)
        last.tap()
        XCTAssertTrue(app.alerts["和弦记忆"].waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        capture(app, name: "Tools-A-large-text")
    }

    func testDarkAppearanceKeepsToolsAndNavigationAccessible() {
        let app = launch(["-gita.appearance", "dark"])
        XCTAssertTrue(app.buttons["tools.item.metronome"].isHittable)
        let last = app.buttons["tools.item.chordMemory"]
        for _ in 0..<4 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(app.tabBars.buttons["工具"].isSelected)
        capture(app, name: "Tools-A-dark")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
