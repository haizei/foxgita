import XCTest

final class MetronomeBeatUnitUITests: XCTestCase {
    func testBeatUnitUpdatesNotationAndMainMeter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("计拍单位联动测试")
        app.buttons["practice.confirm-create"].tap()
        let meter = app.buttons["拍号，打开节拍器设置"]
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        meter.tap()
        let increase = app.buttons["metronome.denominator.increase"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        let beat = app.buttons["metronome.settings.accent.0"]
        let single = app.buttons["metronome.settings.subdivision.0"]
        XCTAssertEqual(beat.value as? String, "四分音符")
        XCTAssertEqual(single.value as? String, "四分音符")
        for (denominator, name, dividedName) in [(8, "八分音符", "十六分音符"), (16, "十六分音符", "三十二分音符")] {
            increase.tap()
            XCTAssertTrue(app.staticTexts["4 / \(denominator)"].exists)
            XCTAssertEqual(beat.value as? String, name)
            XCTAssertEqual(single.value as? String, name)
            XCTAssertEqual(app.buttons["metronome.settings.subdivision.1"].value as? String, dividedName)
            capture(app, name: "beat-unit-\(denominator)")
        }
        XCTAssertFalse(increase.isEnabled)
        for name in ["八分音符", "四分音符", "二分音符"] {
            app.buttons["metronome.denominator.decrease"].tap()
            XCTAssertEqual(beat.value as? String, name)
            XCTAssertEqual(single.value as? String, name)
        }
        capture(app, name: "beat-unit-2")
        XCTAssertFalse(app.buttons["metronome.denominator.decrease"].isEnabled)
        app.buttons["metronome.settings.done"].tap()
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        XCTAssertEqual(meter.value as? String, "4/2")
        XCTAssertFalse(app.buttons["细分，打开节拍器设置"].exists)
        capture(app, name: "meter-without-note")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
