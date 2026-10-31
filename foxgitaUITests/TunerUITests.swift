import XCTest

final class TunerUITests: XCTestCase {
    func testStablePitchConfirmsOnlyAfterListeningAndSettingsKeepReferenceControl() {
        let app = launch("stable")
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "已调准"), object: app.staticTexts["tuner.cents"])
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 5), .completed)
        capture(app, "Tuner-confirmed")
        app.buttons["tuner.settings"].tap()
        let reference = app.buttons["tuner.settings.reference"]
        for _ in 0..<3 where !reference.isHittable { app.swipeUp() }
        XCTAssertTrue(reference.isHittable)
    }

    func testTailLabelsThePreviousReadingThenRequestsANewPluck() {
        let app = launch("tail")
        waitForFeedback("声音变弱，显示上一读数", in: app)
        XCTAssertTrue((app.staticTexts["tuner.cents"].value as? String)?.contains("上一读数") == true)
        XCTAssertFalse((app.staticTexts["tuner.cents"].value as? String)?.contains("已调准") == true)
        waitForFeedback("声音不够清晰，请重新拨弦", in: app)
        XCTAssertEqual(app.staticTexts["tuner.cents"].label, "— cent")
        capture(app, "Tuner-tail-expired")
    }

    func testCompactTargetsAlignWithPegRowsAndHaveNoFooter() {
        let app = launch()
        let topLeft = app.buttons["tuner.string.4"]
        XCTAssertEqual(topLeft.frame.width, 52, accuracy: 1)
        XCTAssertEqual(topLeft.frame.width, topLeft.frame.height, accuracy: 1)
        XCTAssertFalse(app.staticTexts["tuner.target-frequency"].exists)
        XCTAssertFalse(app.staticTexts["tuner.feedback"].exists)
        XCTAssertFalse(app.buttons["tuner.reference"].exists)
        XCTAssertFalse(app.buttons["tuner.calibration"].exists)
        XCTAssertFalse(app.staticTexts["轻拨一根琴弦，让声音自然延长"].exists)
        let headstock = app.otherElements["tuner.headstock"]
        XCTAssertTrue(headstock.exists)
        // Accessibility containers report the union of their accessible children;
        // measure the design canvas from the viewport instead of that union.
        let canvasWidth = min(450, app.frame.width)
        let canvasMinX = app.frame.midX - canvasWidth / 2
        // The design's 300 pt image has 282 pt of content between the buttons;
        // its transparent margins scale with it on smaller screens.
        let imageWidth = min(300, max(0, canvasWidth - 120) * 300 / 282)
        XCTAssertEqual(topLeft.frame.minX, canvasMinX + 8, accuracy: 1)
        XCTAssertEqual(app.buttons["tuner.string.3"].frame.maxX, canvasMinX + canvasWidth - 8, accuracy: 1)
        // Centers measured from the original 971 × 1619 Figma image, not
        // equally spaced rows: the lower pair used to drift far below the pegs.
        for (left, right, pixelY) in [(4, 3, 368.0), (5, 2, 663.0), (6, 1, 951.0)] {
            let expected = topLeft.frame.midY + (pixelY - 368) * imageWidth / 971
            XCTAssertEqual(app.buttons["tuner.string.\(left)"].frame.midY, expected, accuracy: 1)
            XCTAssertEqual(app.buttons["tuner.string.\(right)"].frame.midY, expected, accuracy: 1)
        }
        capture(app, "Tuner-aligned-compact")
    }

    private func launch(_ fixture: String = "signal", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(zh-Hans)", "-TunerFixture", fixture] + extra
        app.launch()
        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.staticTexts["8 款工具"].waitForExistence(timeout: 5))
        let tuner = app.buttons["tools.item.tuner"]
        XCTAssertTrue(tuner.waitForExistence(timeout: 5))
        tuner.tap()
        return app
    }

    func testLiveSignalShowsRealCentsAndSixTargets() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["tuner.cents"].waitForExistence(timeout: 5))
        let liveCents = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '8'"), object: app.staticTexts["tuner.cents"])
        XCTAssertEqual(XCTWaiter.wait(for: [liveCents], timeout: 3), .completed)
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E")
        XCTAssertTrue((app.staticTexts["tuner.note"].value as? String)?.contains("E₂") == true)
        XCTAssertFalse(app.staticTexts["tuner.feedback"].exists)
        for number in 1...6 { XCTAssertTrue(app.buttons["tuner.string.\(number)"].isHittable) }
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture(app, "Tuner-live-low-E")
        app.buttons["tuner.back"].tap()
        XCTAssertTrue(app.buttons["tools.item.tuner"].waitForExistence(timeout: 5))
    }

    func testManualTargetAutoSwitchAndCalibration() {
        let app = launch()
        app.buttons["tuner.string.1"].tap()
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E")
        XCTAssertTrue((app.staticTexts["tuner.note"].value as? String)?.contains("E₄") == true)
        waitForFeedback("偏离较大，请确认琴弦", in: app, timeout: 3)
        XCTAssertEqual(app.switches["tuner.auto"].value as? String, "0")
        app.switches["tuner.auto"].tap()
        let note = app.staticTexts["tuner.note"]
        let automaticNote = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "6 弦"), object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [automaticNote], timeout: 3), .completed)
        app.buttons["tuner.settings"].tap()
        XCTAssertTrue(app.buttons["tuner.calibration.increase"].waitForExistence(timeout: 5))
        app.buttons["tuner.calibration.increase"].tap()
        XCTAssertEqual(app.staticTexts["tuner.calibration.value"].label, "441 Hz")
        app.buttons["tuner.calibration.reset"].tap()
        XCTAssertEqual(app.staticTexts["tuner.calibration.value"].label, "440 Hz")
        app.buttons["tuner.settings.done"].tap()
        app.buttons["tuner.tuning"].tap()
        app.buttons["Drop D"].tap()
        XCTAssertTrue(app.staticTexts["tuner.tuning-summary"].label.contains("Drop D"))
        app.buttons["tuner.tuning"].tap()
        app.buttons["DADGAD"].tap()
        XCTAssertTrue(app.staticTexts["tuner.tuning-summary"].label.contains("DADGAD"))
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "D")
        app.buttons["tuner.tuning"].tap()
        app.buttons["整体降半音"].tap()
        XCTAssertTrue(app.staticTexts["tuner.tuning-summary"].label.contains("E♭ A♭ D♭ G♭ B♭ E♭"))
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E♭")
        XCTAssertTrue((app.staticTexts["tuner.note"].value as? String)?.contains("E♭₂") == true)
        capture(app, "Tuner-half-step-down")
    }

    func testPermissionDenialAndSilenceNeverPretendToBeInTune() {
        let denied = launch("denied")
        XCTAssertTrue(denied.buttons["tuner.permission-settings"].waitForExistence(timeout: 5))
        XCTAssertFalse((denied.staticTexts["tuner.cents"].value as? String)?.contains("已调准") == true)
        denied.terminate()
        let silent = launch("silence")
        waitForFeedback("等待琴弦声音", in: silent)
        XCTAssertEqual(silent.staticTexts["tuner.cents"].label, "— cent")
        XCTAssertFalse((silent.staticTexts["tuner.cents"].value as? String)?.contains("已调准") == true)
        capture(silent, "Tuner-no-signal")
    }

    func testLargeTextAndDarkLayoutKeepControlsReachable() {
        let app = launch(extra: ["-gita.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let lowestTarget = app.buttons["tuner.string.1"]
        for _ in 0..<8 where !lowestTarget.isHittable { app.swipeUp() }
        XCTAssertTrue(lowestTarget.isHittable)
        for number in 1...6 {
            let target = app.buttons["tuner.string.\(number)"]
            XCTAssertGreaterThanOrEqual(target.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(target.frame.maxX, app.frame.maxX)
        }
        for column in [[4, 5, 6], [3, 2, 1]] {
            for index in 0..<2 {
                let upper = app.buttons["tuner.string.\(column[index])"].frame
                let lower = app.buttons["tuner.string.\(column[index + 1])"].frame
                XCTAssertLessThanOrEqual(upper.maxY, lower.minY)
            }
        }
        XCTAssertFalse(app.buttons["tuner.reference"].exists)
        capture(app, "Tuner-accessibility-dark")
    }

    private func waitForFeedback(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let message = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["tuner.feedback"])
        XCTAssertEqual(XCTWaiter.wait(for: [message], timeout: timeout), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
