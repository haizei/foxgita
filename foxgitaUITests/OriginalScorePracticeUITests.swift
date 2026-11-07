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

    func testUploadAutomaticallyReadPrepareCancelPlayAndReopenMaterial() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-OriginalScoreFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        if let path = ProcessInfo.processInfo.environment["GITA_ORIGINAL_SCORE_PAGE"] {
            app.launchEnvironment["GITA_ORIGINAL_SCORE_PAGE"] = path
        }
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
        let prepare = app.buttons["original.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.navigationBars["标记谱行"].exists)
        XCTAssertFalse(app.buttons["original.publish"].exists)
        XCTAssertTrue(app.staticTexts["original.read-summary"].label.contains("4 行、16 小节"))
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
