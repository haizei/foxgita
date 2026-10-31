import XCTest

final class TunerUITests: XCTestCase {
    func testStablePitchConfirmsOnlyAfterListeningAndSettingsKeepReferenceControl() {
        let app = launch("stable")
        XCTAssertTrue(app.staticTexts["已调准"].waitForExistence(timeout: 5))
        capture(app, "Tuner-confirmed")
        app.buttons["tuner.settings"].tap()
        let reference = app.buttons["tuner.settings.reference"]
        for _ in 0..<3 where !reference.isHittable { app.swipeUp() }
        XCTAssertTrue(reference.isHittable)
    }

    func testTailLabelsThePreviousReadingThenRequestsANewPluck() {
        let app = launch("tail")
        XCTAssertTrue(app.staticTexts["声音变弱，显示上一读数"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已调准"].exists)
        XCTAssertTrue(app.staticTexts["声音不够清晰，请重新拨弦"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tuner.cents"].label, "— cent")
        capture(app, "Tuner-tail-expired")
    }

    func testCompactTargetsAlignWithPegRowsAndHaveNoFooter() {
        let app = launch()
        let topLeft = app.buttons["tuner.string.4"]
        XCTAssertEqual(topLeft.frame.width, topLeft.frame.height, accuracy: 1)
        XCTAssertFalse(app.buttons["tuner.reference"].exists)
        XCTAssertFalse(app.buttons["tuner.calibration"].exists)
        XCTAssertFalse(app.staticTexts["轻拨一根琴弦，让声音自然延长"].exists)
        let headstock = app.otherElements["tuner.headstock"]
        XCTAssertTrue(headstock.exists)
        // Accessibility containers report the union of their accessible children;
        // measure the design canvas from the viewport instead of that union.
        let canvasWidth = min(450, app.frame.width)
        let canvasMinX = app.frame.midX - canvasWidth / 2
        let imageWidth = min(290, canvasWidth - 112)
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
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E₂")
        for number in 1...6 { XCTAssertTrue(app.buttons["tuner.string.\(number)"].isHittable) }
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture(app, "Tuner-live-low-E")
        app.buttons["tuner.back"].tap()
        XCTAssertTrue(app.buttons["tools.item.tuner"].waitForExistence(timeout: 5))
    }

    func testManualTargetAutoSwitchAndCalibration() {
        let app = launch()
        app.buttons["tuner.string.1"].tap()
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E₄")
        XCTAssertEqual(app.switches["tuner.auto"].value as? String, "0")
        app.switches["tuner.auto"].tap()
        let note = app.staticTexts["tuner.note"]
        let automaticNote = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'E₂'"), object: note)
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
        app.buttons["整体降半音"].tap()
        XCTAssertTrue(app.staticTexts["tuner.tuning-summary"].label.contains("E♭ A♭ D♭ G♭ B♭ E♭"))
        XCTAssertEqual(app.staticTexts["tuner.note"].label, "E♭₂")
    }

    func testPermissionDenialAndSilenceNeverPretendToBeInTune() {
        let denied = launch("denied")
        XCTAssertTrue(denied.buttons["tuner.permission-settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(denied.staticTexts["已调准"].exists)
        denied.terminate()
        let silent = launch("silence")
        XCTAssertTrue(silent.staticTexts["等待琴弦声音"].waitForExistence(timeout: 5))
        XCTAssertEqual(silent.staticTexts["tuner.cents"].label, "— cent")
        XCTAssertFalse(silent.staticTexts["已调准"].exists)
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

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
