import XCTest

final class PracticeLifecycleUITests: XCTestCase {
    func testBackgroundRoundTripKeepsPracticeClockAndNoteDraft() throws {
        let title = "Background note acceptance"
        let app = createPractice(title: title)
        defer { app.terminate() }
        app.buttons["practice.toggle-running"].tap()
        let before = try displayedSeconds(app)
        let startedAt = ProcessInfo.processInfo.systemUptime
        var editor = app.descendants(matching: .any)["practice.note-editor"]
        for _ in 0..<4 where !editor.isHittable { app.swipeUp() }
        XCTAssertTrue(editor.isHittable)
        editor.tap()
        editor.typeText("Immediate background flush")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Immediate background flush")
        let primary = app.buttons["practice.toggle-running"]
        for _ in 0..<5 where !primary.isHittable { app.swipeDown() }
        XCTAssertEqual(primary.label, "暂停")
        let after = try displayedSeconds(app)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        XCTAssertGreaterThanOrEqual(after - before, 5)
        XCTAssertEqual(Double(after - before), elapsed, accuracy: 3)
        primary.tap()
        app.buttons["返回"].firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND (label ENDSWITH '分钟，开始' OR label ENDSWITH '分钟，继续')", title
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        editor = app.descendants(matching: .any)["practice.note-editor"]
        for _ in 0..<4 where !editor.isHittable { app.swipeUp() }
        XCTAssertEqual(editor.value as? String, "Immediate background flush")
        capture(app, name: "Background-note-restored")
    }

    func testSilentPracticeClockCatchesUpAfterBackground() throws {
        let app = createPractice(title: "Silent background acceptance")
        defer { app.terminate() }
        app.buttons["metronome.open-sound-settings"].tap()
        app.buttons["更多声音设置"].tap()
        let enabled = app.switches["practice.metronome-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        if enabled.value as? String == "1" {
            // SwiftUI Form may expose the full labeled row as the switch element.
            enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: enabled)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 2), .completed)
        let advanced = app.navigationBars["更多声音设置"]
        advanced.buttons["完成"].tap()
        let advancedClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: advanced)
        XCTAssertEqual(XCTWaiter.wait(for: [advancedClosed], timeout: 5), .completed)
        let soundDone = app.buttons["metronome.sound.done"]
        let soundReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: soundDone)
        XCTAssertEqual(XCTWaiter.wait(for: [soundReady], timeout: 5), .completed)
        soundDone.tap()
        let primary = app.buttons["practice.toggle-running"]
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: primary)
        let ready = XCTWaiter.wait(for: [hittable], timeout: 5)
        if ready != .completed {
            capture(app, name: "Silent-clock-start-not-hittable")
            print(app.debugDescription)
        }
        XCTAssertEqual(ready, .completed)
        primary.tap()
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停"), object: primary)
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 5), .completed)
        capture(app, name: "Silent-clock-running-before-background")
        let before = try displayedSeconds(app)
        let startedAt = ProcessInfo.processInfo.systemUptime
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        capture(app, name: "Silent-clock-after-background")
        XCTAssertEqual(primary.label, "暂停")
        let after = try displayedSeconds(app)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        XCTAssertGreaterThanOrEqual(after - before, 5)
        XCTAssertEqual(Double(after - before), elapsed, accuracy: 3)
        primary.tap()
        capture(app, name: "Silent-background-clock")
    }

    private func createPractice(title: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let create = app.buttons["practice.create-button"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["practice.confirm-create"].tap()
        XCTAssertTrue(app.buttons["practice.toggle-running"].waitForExistence(timeout: 5))
        return app
    }

    private func displayedSeconds(_ app: XCUIApplication) throws -> Int {
        let clock = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{2}:[0-9]{2}$")).firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        let parts = clock.label.split(separator: ":").compactMap { Int($0) }
        _ = try XCTUnwrap(parts.count == 2 ? true : nil, "Practice clock is missing or malformed")
        return parts[0] * 60 + parts[1]
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
