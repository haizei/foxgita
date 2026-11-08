import XCTest

final class MetronomeBeatUnitUITests: XCTestCase {
    func testSpeedTabsAndTempoStayInSyncAfterTapAndManualAdjustment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("调速同步测试")
        app.buttons["practice.confirm-create"].tap()
        let speed = app.buttons["metronome.open-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        speed.tap()
        let adjustTab = app.buttons["metronome.speed.tab.adjust"]
        XCTAssertTrue(adjustTab.waitForExistence(timeout: 5))
        let current = app.staticTexts["metronome.speed.bpm"]
        XCTAssertEqual(current.label, "80")
        capture(app, name: "speed-adjust-figma")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(speed.isHittable, "The dimmed backdrop must dismiss the sheet without activating practice controls")
        speed.tap()
        for _ in 0..<4 { app.buttons["metronome.tap"].tap() }
        XCTAssertEqual(current.label, "80", "TAP preview must not replace the active BPM")
        let apply = app.buttons["metronome.tap.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        capture(app, name: "speed-tap-preview-synced")
        let measured = Int(apply.label.filter(\.isNumber))!
        apply.tap()
        XCTAssertEqual(current.label, String(measured))
        app.buttons["metronome.speed.increase"].tap()
        XCTAssertEqual(current.label, String(min(200, measured + 1)))
        app.buttons["metronome.speed.decrease"].tap()
        XCTAssertEqual(current.label, String(min(200, measured + 1) - 1))
        let ruler = app.otherElements["metronome.speed.ruler"]
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertEqual(current.label, "100")
        capture(app, name: "speed-adjust-synced")
        app.buttons["metronome.speed.tab.ramp"].tap()
        if app.alerts["变速训练"].waitForExistence(timeout: 1) {
            app.alerts["变速训练"].buttons["知道了"].tap()
        }
        XCTAssertTrue(app.buttons["metronome.ramp.start"].waitForExistence(timeout: 5))
        capture(app, name: "speed-ramp-figma")
        adjustTab.tap()
        XCTAssertEqual(current.label, "100")
        app.buttons["metronome.speed.handle"].swipeDown()
        XCTAssertTrue(current.waitForNonExistence(timeout: 5))
        XCTAssertTrue(speed.isHittable)
        XCTAssertEqual(speed.value as? String, "100 BPM")
        speed.tap()
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.label, "100")
        app.buttons["metronome.speed.tab.ramp"].tap()
        app.buttons["metronome.ramp.start"].tap()
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        speed.tap()
        XCTAssertTrue(adjustTab.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["practice.toggle-running"].isHittable, "Training must not trap users in the speed sheet")
    }

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
