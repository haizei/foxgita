import XCTest

final class SuggestedPracticeUITests: XCTestCase {
    func testGeneratedFocusRequiresConfirmation() throws {
        let app = completeFixture(needsInput: false)
        let save = app.buttons["next-focus.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertEqual(save.label, "保存下次重点")
        XCTAssertTrue(app.staticTexts["本次总结"].exists)
        XCTAssertTrue(app.staticTexts["AI 建议"].exists)
        attach(app, name: "Next-focus-ready")
        app.buttons["next-focus.return"].tap()
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["suggested-practice.card"].exists)
    }

    func testInsufficientInputGeneratesBeforeConfirmation() throws {
        let app = completeFixture(needsInput: true)
        let primary = app.buttons["next-focus.save"]
        XCTAssertTrue(primary.waitForExistence(timeout: 8))
        XCTAssertEqual(primary.label, "生成下次重点")
        XCTAssertFalse(primary.isEnabled)
        XCTAssertTrue(app.staticTexts["下次最想继续哪部分？"].exists)
        attach(app, name: "Next-focus-needs-input")
        let input = app.textViews["next-focus.input"]
        input.tap()
        input.typeText("Continue C to G and listen to the transition.")
        reveal(primary, in: app)
        XCTAssertTrue(primary.isEnabled)
        primary.tap()
        let ready = NSPredicate(format: "label == %@", "保存下次重点")
        expectation(for: ready, evaluatedWith: primary)
        waitForExpectations(timeout: 8)
        primary.tap()
        XCTAssertTrue(app.buttons["suggested-practice.card"].waitForExistence(timeout: 8))
    }

    private func completeFixture(needsInput: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-gita.nextFocus.autoGenerate", "NO", "-gita.llm.baseURL", "", "-NextFocusFixture"]
        if needsInput { app.launchArguments.append("-NextFocusNeedsInput") }
        app.launch()
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 8))
        app.buttons["practice.create-button"].tap()
        let name = app.textFields["practice.create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("C to G practice")
        app.buttons["确认并创建练习"].tap()
        let timer = app.buttons["practice.toggle-running"]
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        timer.tap()
        Thread.sleep(forTimeInterval: 2)
        timer.tap()
        let finish = app.buttons["practice.finish"]
        reveal(finish, in: app)
        finish.tap()
        return app
    }

    func testCompleteConfirmAndResumeSuggestedPractice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-gita.nextFocus.autoGenerate", "NO", "-gita.llm.baseURL", ""]
        app.launch()
        XCTAssertTrue(app.buttons["practice.create-button"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["suggested-practice.card"].exists)
        app.buttons["practice.create-button"].tap()
        let name = app.textFields["practice.create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("C to G practice")
        app.buttons["确认并创建练习"].tap()
        let timer = app.buttons["practice.toggle-running"]
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        timer.tap()
        // This is a real elapsed-time boundary, not an arbitrary rendering wait.
        Thread.sleep(forTimeInterval: 2)
        timer.tap()
        let finish = app.buttons["practice.finish"]
        reveal(finish, in: app)
        XCTAssertTrue(finish.isEnabled)
        finish.tap()
        let input = app.textViews["next-focus.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["next-focus.save"].isEnabled)
        attach(app, name: "Next-focus-completion-manual")
        input.tap()
        input.typeText("Continue C to G and listen for the pause.")
        let save = app.buttons["next-focus.save"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let card = app.buttons["suggested-practice.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        reveal(card, in: app, towardTop: true)
        attach(app, name: "Suggested-practice-ready")
        card.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        XCTAssertEqual(timer.label, "开始")
        timer.tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["返回"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        reveal(card, in: app, towardTop: true)
        XCTAssertTrue(app.staticTexts["已暂停"].exists)
        attach(app, name: "Suggested-practice-paused")
        card.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        XCTAssertEqual(timer.label, "继续")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
