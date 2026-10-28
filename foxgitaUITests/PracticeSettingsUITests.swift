import XCTest

final class PracticeSettingsUITests: XCTestCase {
    func testRecordingPauseOwnershipAndSavedTake() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("录音暂停联动测试")
        app.buttons["practice.confirm-create"].tap()
        let record = app.buttons["录音"]
        for _ in 0..<3 where !record.isHittable { app.swipeUp() }
        record.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            if permission.buttons["允许"].exists { permission.buttons["允许"].tap() }
            else if permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
        }
        let recordingPause = app.buttons["practice.recording.toggle-pause"]
        for _ in 0..<3 where !recordingPause.isHittable { app.swipeUp() }
        XCTAssertTrue(recordingPause.waitForExistence(timeout: 5))
        XCTAssertEqual(recordingPause.label, "暂停")
        for _ in 0..<2 where app.buttons["practice.recording.stop"].frame.maxY > app.frame.maxY - 20 { app.swipeUp() }
        capture(app, name: "PR02-recording")
        recordingPause.tap()
        let primary = app.buttons["practice.toggle-running"]
        for _ in 0..<4 where !primary.isHittable { app.swipeDown() }
        XCTAssertEqual(primary.label, "暂停")
        primary.tap()
        primary.tap()
        for _ in 0..<4 where !recordingPause.isHittable { app.swipeUp() }
        XCTAssertEqual(recordingPause.label, "继续", "Main resume must preserve a manually paused recording")
        app.buttons["practice.recording.stop"].tap()
        XCTAssertFalse(app.buttons["practice.recording.stop"].exists)
        capture(app, name: "PR03-saved-recording")
        app.buttons["返回"].firstMatch.tap()
    }

    func testLargeTextSettingsRemainReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("大字号设置测试")
        app.buttons["practice.confirm-create"].tap()
        app.buttons["metronome.open-sound-settings"].tap()
        XCTAssertTrue(app.buttons["metronome.sound.done"].waitForExistence(timeout: 5))
        let counter = app.buttons["metronome.visual.bar-counter"]
        for _ in 0..<8 where !counter.isHittable { app.swipeUp() }
        XCTAssertTrue(counter.isHittable)
        XCTAssertLessThanOrEqual(counter.frame.maxX, app.frame.maxX)
        capture(app, name: "AX-MT04-visual")
        app.buttons["metronome.sound.done"].tap()
        let countdown = app.buttons["countdown.open-settings"]
        for _ in 0..<4 where !countdown.isHittable { app.swipeUp() }
        countdown.tap()
        let start = app.buttons["countdown.start"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        capture(app, name: "AX-CD01")
    }

    func testTempoMeterFullscreenAndCountdownSharePracticeState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("共享工具状态测试")
        app.buttons["practice.confirm-create"].tap()
        app.buttons["metronome.open-speed"].tap()
        XCTAssertTrue(app.buttons["metronome.ramp.entry"].waitForExistence(timeout: 5))
        capture(app, name: "MT01-speed")
        app.buttons["metronome.ramp.entry"].tap()
        if app.alerts["变速训练"].waitForExistence(timeout: 1) {
            app.alerts["变速训练"].buttons["知道了"].tap()
        }
        XCTAssertTrue(app.buttons["metronome.ramp.start"].waitForExistence(timeout: 5))
        capture(app, name: "MT02-ramp")
        app.buttons["metronome.speed.done"].tap()
        app.buttons["拍号，打开节拍器设置"].tap()
        XCTAssertTrue(app.buttons["metronome.denominator.increase"].waitForExistence(timeout: 5))
        app.buttons["metronome.denominator.increase"].tap()
        XCTAssertTrue(app.staticTexts["4 / 8"].exists)
        capture(app, name: "MT03-meter")
        app.buttons["metronome.settings.done"].tap()
        app.buttons["metronome.open-sound-settings"].tap()
        app.buttons["展开节拍器"].tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4/8"].firstMatch.exists)
        capture(app, name: "MT-fullscreen")
        app.buttons["开始练习"].tap()
        XCTAssertTrue(app.buttons["暂停练习"].waitForExistence(timeout: 5))
        app.buttons["收起"].tap()
        XCTAssertEqual(app.buttons["practice.toggle-running"].label, "暂停")
        app.buttons["practice.toggle-running"].tap()
        app.buttons["countdown.open-settings"].tap()
        XCTAssertTrue(app.buttons["countdown.start"].waitForExistence(timeout: 5))
        app.buttons["countdown.start"].tap()
        let primary = app.buttons["practice.toggle-running"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertEqual(primary.label, "暂停")
        capture(app, name: "CD02-running")
        primary.tap()
        XCTAssertEqual(primary.label, "继续")
        capture(app, name: "CD03-paused")
        app.buttons["返回"].firstMatch.tap()
    }

    func testCountdownSaveDoesNotStartAndNoteSurvivesReturning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["practice.create-button"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("倒计时笔记测试")
        app.buttons["practice.confirm-create"].tap()
        app.buttons["countdown.open-settings"].tap()
        XCTAssertTrue(app.buttons["countdown.save-plan"].waitForExistence(timeout: 5))
        capture(app, name: "CD01-save-plan")
        app.buttons["countdown.save-plan"].tap()
        XCTAssertTrue(app.buttons["practice.toggle-running"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["practice.toggle-running"].label, "继续")
        var editor = app.descendants(matching: .any)["practice.note-editor"]
        for _ in 0..<3 where !editor.isHittable { app.swipeUp() }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Practice note retained")
        app.buttons["返回"].firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND (label ENDSWITH '分钟，开始' OR label ENDSWITH '分钟，继续')", "倒计时笔记测试")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        editor = app.descendants(matching: .any)["practice.note-editor"]
        for _ in 0..<3 where !editor.isHittable { app.swipeUp() }
        XCTAssertEqual(editor.value as? String, "Practice note retained")
        capture(app, name: "PR03-note-restored")
    }

    func testCompleteSoundAndVisualSettingsFromPractice() {
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
        field.typeText("设置流程测试")
        app.buttons["practice.confirm-create"].tap()
        let settings = app.buttons["metronome.open-sound-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        capture(app, name: "PR01-main")
        settings.tap()
        XCTAssertTrue(app.staticTexts["音色选择"].waitForExistence(timeout: 5))
        capture(app, name: "MT04-top")
        app.buttons["木鱼声"].tap()
        let number = app.descendants(matching: .any)["音色编号"]
        XCTAssertEqual(number.value as? String, "4，木鱼声")
        app.buttons["上一个音色"].tap()
        XCTAssertEqual(number.value as? String, "3，风铃声")
        let pendulum = app.buttons["metronome.visual.pendulum"]
        if !pendulum.isHittable { app.swipeUp() }
        XCTAssertTrue(pendulum.waitForExistence(timeout: 5))
        if pendulum.value as? String != "已选择" { pendulum.tap() }
        XCTAssertEqual(pendulum.value as? String, "已选择")
        let beat = app.buttons["metronome.visual.beat-module"]
        if beat.value as? String != "已选择" { beat.tap() }
        XCTAssertEqual(beat.value as? String, "已选择")
        capture(app, name: "MT04-visual")
        app.buttons["metronome.sound.done"].tap()
        settings.tap()
        if !pendulum.isHittable { app.swipeUp() }
        XCTAssertEqual(pendulum.value as? String, "已选择")
        XCTAssertEqual(beat.value as? String, "已选择")
        pendulum.tap()
        app.buttons["metronome.sound.done"].tap()
        app.buttons["返回"].firstMatch.tap()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
