import XCTest

final class OriginalScorePracticeUITests: XCTestCase {
    func testCreatePracticeOriginalMethodOpensUploadSourceDirectly() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let create = app.buttons["practice.create-button"]
        XCTAssertTrue(create.waitForExistence(timeout: 15)); create.tap()
        app.segmentedControls["practice.create-mode"].buttons["跟谱练习"].tap()
        app.segmentedControls["practice.score-method"].buttons["原谱跟弹"].tap()
        let confirm = app.buttons["practice.confirm-create"]
        XCTAssertEqual(confirm.label, "上传谱子"); confirm.tap()
        XCTAssertTrue(app.buttons["导入 PDF 或图片"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["从相册选择"].exists)
    }

    func testUploadMarkPrepareCancelPlayAndReopenMaterial() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-OriginalScoreFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 20)); tools.tap()
        let playAlong = app.buttons["tools.item.playAlong"]
        for _ in 0..<10 where !playAlong.isHittable { app.swipeUp() }
        XCTAssertTrue(playAlong.isHittable); playAlong.tap()
        let original = app.segmentedControls.buttons["原谱跟弹"]
        XCTAssertTrue(original.waitForExistence(timeout: 10)); original.tap()
        app.buttons["original.upload"].tap()
        app.buttons["导入 PDF 或图片"].tap()
        XCTAssertTrue(app.navigationBars["标记谱行"].waitForExistence(timeout: 10))
        let canvas = app.descendants(matching: .any).matching(identifier: "original.mark-canvas").firstMatch
        for _ in 0..<5 where !canvas.isHittable { app.swipeUp() }
        XCTAssertTrue(canvas.exists)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.14))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.32))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.43)))
        let publish = app.buttons["original.publish"]
        for _ in 0..<8 where !publish.isHittable { app.swipeUp() }
        XCTAssertTrue(app.textFields["original.beats.1"].exists, "新增第二行不能覆盖第一行")
        XCTAssertTrue(publish.isEnabled, app.debugDescription); publish.tap()
        let prepare = app.buttons["original.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["待机"].exists)
        XCTAssertEqual(app.switches["original.loop"].value as? String, "0")
        prepare.tap()
        let cancel = app.buttons["original.cancel-prepare"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3)); cancel.tap()
        XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["original.position"].label.contains("0 秒"))
        prepare.tap()
        XCTAssertTrue(app.staticTexts["跟线弹奏中"].waitForExistence(timeout: 6))
        app.buttons["original.play"].tap()
        app.buttons["original.play"].tap()
        XCTAssertTrue(app.staticTexts["跟线弹奏中"].waitForExistence(timeout: 3))
        app.buttons["original.play"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "original-score-line-following"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["original.player-close"].tap()
        XCTAssertTrue(app.buttons["original.upload"].waitForExistence(timeout: 8))
        let material = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'original.material.'")).firstMatch
        XCTAssertTrue(material.waitForExistence(timeout: 5)); material.tap()
        XCTAssertTrue(app.buttons["original.prepare"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["待机"].exists)
    }
}
