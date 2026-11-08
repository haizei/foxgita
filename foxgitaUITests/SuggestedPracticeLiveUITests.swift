import XCTest

/// Uses the normal app client and existing Keychain credentials, only when explicitly enabled.
final class SuggestedPracticeLiveUITests: XCTestCase {
    func testCompleteGenerateConfirmAndShowSuggestedPracticeWithLiveAI() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITA_NEXT_FOCUS_LIVE_TEST"] == "1"
            || environment["TEST_RUNNER_GITA_NEXT_FOCUS_LIVE_TEST"] == "1" else {
            throw XCTSkip("Requires explicit authorization for a real AI request.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let timingRunID = UUID().uuidString
        app.launchEnvironment["GITA_NEXT_FOCUS_TIMING_RUN_ID"] = timingRunID
        // Practice facts are isolated, while the configured endpoint/model/Keychain remain available.
        app.launchArguments = ["-UITesting", "-NextFocusPageTiming", "-gita.nextFocus.autoGenerate", "YES", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let create = app.buttons["practice.create-button"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["suggested-practice.card"].exists)
        create.tap()
        let name = app.textFields["practice.create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("C to G chord transition")
        app.buttons["确认并创建练习"].tap()
        let timer = app.buttons["practice.toggle-running"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        timer.tap()
        Thread.sleep(forTimeInterval: 2)
        timer.tap()
        let finish = app.buttons["practice.finish"]
        reveal(finish, in: app)
        XCTAssertTrue(finish.isEnabled)
        let started = Date()
        finish.tap()
        XCTAssertTrue(app.staticTexts["本次练习完成"].waitForExistence(timeout: 10))
        // This badge requires a parsed generated result; manual fallback cannot satisfy the assertion.
        XCTAssertTrue(app.staticTexts["AI 建议"].waitForExistence(timeout: 150), app.debugDescription)
        let generationSeconds = Date().timeIntervalSince(started)
        let input = app.textViews["next-focus.input"]
        let focus = (input.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(focus.isEmpty)
        XCTAssertTrue(app.staticTexts["本次总结"].exists)
        let save = app.buttons["next-focus.save"]
        XCTAssertEqual(save.label, "保存下次重点")
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.buttons["suggested-practice.card"].exists)
        attach(app, name: "Live-AI-generated-summary-and-focus")
        save.tap()
        let card = app.buttons["suggested-practice.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        reveal(card, in: app, towardTop: true)
        XCTAssertTrue(card.label.contains(focus) || app.staticTexts[focus].exists)
        attach(app, name: "Live-AI-confirmed-home-suggestion")
        let report: [String: Any] = [
            "liveRequestEnabled": true, "deterministicFixtureEnabled": false,
            "timingRunID": timingRunID,
            "practice": "C to G chord transition", "focus": focus,
            "completionToGeneratedSeconds": generationSeconds,
            "measurementEndsAt": "first XCTest observation of generated badge",
            "includesXCTestOverhead": true, "excludesScreenshotTime": true,
            "explicitlyConfirmed": true, "homeShowsGeneratedFocus": true
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "live-ai-flow-report.json"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<10 {
            if element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
