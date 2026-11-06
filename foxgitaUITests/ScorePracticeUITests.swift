import XCTest

final class ScorePracticeUITests: XCTestCase {
    func testQingTianCanRefreshRecognitionWithoutLosingItsDraft() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["GITA_QINGTIAN_PAGE"] ?? env["TEST_RUNNER_GITA_QINGTIAN_PAGE"] else {
            throw XCTSkip("Requires the supplied QingTian source page")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting","-ScoreRecoveryFixture","-AppleLanguages","(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATH"] = path
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15)); tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.buttons["score.import"].waitForExistence(timeout: 8))
        app.buttons["score.import"].tap(); app.buttons["导入 PDF 或图片"].tap()
        let local = app.buttons["score.local-tab"]
        XCTAssertTrue(local.waitForExistence(timeout: 10)); local.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["已识别，16个小节，点击筛选"].exists)
        XCTAssertFalse(app.buttons["score.review.group.strumRange"].exists)
        XCTAssertFalse(app.buttons["score.review.group.hammerOn"].exists)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "qing-tian-auto-recognized-ranges"; initial.lifetime = .keepAlways; add(initial)
        let refresh = app.buttons["score.review.refresh"]
        for _ in 0..<8 where !refresh.isHittable { app.swipeUp() }
        XCTAssertTrue(refresh.isHittable); refresh.tap()
        let message = app.staticTexts["没有发现可自动更新的内容，已保留当前校正结果。"]
        XCTAssertTrue(message.waitForExistence(timeout: 20),app.debugDescription)
        XCTAssertTrue(refresh.isEnabled)
        let allRecognized = app.buttons["已识别，16个小节，点击筛选"]
        for _ in 0..<12 where !allRecognized.isHittable { app.swipeDown() }
        XCTAssertTrue(allRecognized.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "qing-tian-refreshed-draft"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testReviewStatesGuideCorrectionAndPersistAcknowledgement() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-ScoreReviewFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15)); tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 10))
        let recognized = app.buttons["已识别，1个小节，点击筛选"]
        XCTAssertTrue(recognized.exists)
        XCTAssertTrue(app.buttons["待校正，2个小节，点击筛选"].exists)
        XCTAssertTrue(app.buttons["未识别，1个小节，点击筛选"].exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "score-review-overview"; overview.lifetime = .keepAlways; add(overview)
        app.buttons["score.review.next"].tap()
        XCTAssertTrue(app.navigationBars["第1小节"].waitForExistence(timeout: 5))
        let confirm = app.buttons["score.review.confirm-bar"]
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.exists); XCTAssertFalse(confirm.isEnabled)
        app.navigationBars["第1小节"].buttons.firstMatch.tap()
        for _ in 0..<12 where !app.buttons["待校正，2个小节，点击筛选"].isHittable { app.swipeDown() }
        app.buttons["待校正，2个小节，点击筛选"].tap()
        let fourth = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '第4小节 ·'")).firstMatch
        for _ in 0..<12 where !fourth.isHittable { app.swipeUp() }
        XCTAssertTrue(fourth.isHittable); fourth.tap()
        XCTAssertTrue(app.navigationBars["第4小节"].waitForExistence(timeout: 5))
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 5))
        for _ in 0..<12 where !app.buttons["已识别，2个小节，点击筛选"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["已识别，2个小节，点击筛选"].exists)
        XCTAssertTrue(app.buttons["待校正，1个小节，点击筛选"].exists)
        app.buttons["关闭"].firstMatch.tap()
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'score.pending.'")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 8)); pending.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["已识别，2个小节，点击筛选"].exists)
    }

    /// Seed the simulator with `simctl addmedia` before running this integration test.
    func testAlbumPhotoOpensImportPreviewAndCanBeSelectedAgain() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITA_ALBUM_FIXTURE"] == "1" || environment["TEST_RUNNER_GITA_ALBUM_FIXTURE"] == "1" else {
            throw XCTSkip("Requires a simulator photo seeded with simctl addmedia")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15)); tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        let importButton = app.buttons["score.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        for _ in 0..<2 {
            importButton.tap()
            app.buttons["score.import.photos"].tap()
            let photo = app.images["PXGGridLayout-Info"].firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 8), app.debugDescription)
            // Photos exposes grid thumbnails as images rather than tappable cells.
            photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
            let add = app.buttons["完成"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 8), app.debugDescription)
            add.tap()
            XCTAssertTrue(app.staticTexts["导入谱页"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(app.staticTexts["共1页 · 印刷六线谱或五线谱"].exists)
            app.buttons["关闭"].firstMatch.tap()
            XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        }
    }

    func testAlbumPickerCanCancelAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable)
        link.tap()
        let importButton = app.buttons["score.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        for _ in 0..<2 {
            importButton.tap()
            app.buttons["score.import.photos"].tap()
            let cancel = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
            cancel.tap()
            XCTAssertTrue(importButton.waitForExistence(timeout: 8))
            XCTAssertTrue(importButton.isEnabled)
            XCTAssertFalse(app.staticTexts["正在读取谱页…"].exists)
            XCTAssertFalse(app.staticTexts["导入谱页"].exists)
        }
    }

    func testLiveDevicePendingLocalRecognitionReturns() throws {
        let env = ProcessInfo.processInfo.environment
        guard let source = env["GITA_LIVE_PENDING_SOURCE"] ?? env["TEST_RUNNER_GITA_LIVE_PENDING_SOURCE"] else {
            throw XCTSkip("Requires the explicitly selected pending source on the connected device")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15)); tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        let pending = app.buttons["score.pending.\(source)"]
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
        for _ in 0..<12 where !pending.isHittable { app.swipeUp() }
        XCTAssertTrue(pending.isHittable); pending.tap()
        let local = app.buttons["score.local-tab"]
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        for _ in 0..<12 where !local.isHittable { app.swipeUp() }
        XCTAssertTrue(local.isHittable); local.tap()
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '未读到可靠的六线谱符号' ")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(local.exists && local.isEnabled)
        XCTAssertFalse(app.staticTexts["正在本机读取六线谱…"].exists)
    }

    func testQingTianThreePageImportRestoresSixtiethMeasure() throws {
        let env=ProcessInfo.processInfo.environment
        guard let dir=env["GITA_FULL_SCORE_DIR"] ?? env["TEST_RUNNER_GITA_FULL_SCORE_DIR"] else {
            throw XCTSkip("Requires the authorized three-page local score")
        }
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-UITesting","-ScoreRecoveryFixture","-AppleLanguages","(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"]=UUID().uuidString
        let paths=(1...3).map { URL(fileURLWithPath:dir).appendingPathComponent("晴天-谱子\($0).jpg").path }
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATHS"]=String(decoding:try JSONEncoder().encode(paths),as:UTF8.self)
        func visible(_ item:XCUIElement) {
            for _ in 0..<24 where !item.isHittable { app.swipeUp() }
            XCTAssertTrue(item.isHittable,app.debugDescription)
        }
        app.launch()
        let tools=app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout:15));tools.tap()
        let link=app.buttons["tools.item.playAlong"];visible(link);link.tap()
        XCTAssertTrue(app.buttons["score.import"].waitForExistence(timeout:8))
        app.buttons["score.import"].tap();app.buttons["导入 PDF 或图片"].tap()
        let local=app.buttons["score.local-tab"]
        XCTAssertTrue(local.waitForExistence(timeout:10));visible(local);local.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout:30),app.debugDescription)
        XCTAssertTrue(app.buttons["查看原谱第3页"].exists)
        let final=app.buttons.matching(NSPredicate(format:"label BEGINSWITH '第60小节 ·'")).firstMatch
        visible(final);final.tap()
        XCTAssertTrue(app.navigationBars["第60小节"].waitForExistence(timeout:8))
        let source=app.buttons["对照原谱第3页 · 已标出位置"].firstMatch
        visible(source);source.tap()
        XCTAssertTrue(app.navigationBars["原谱第3页"].waitForExistence(timeout:8))
        let picture=XCTAttachment(screenshot:app.screenshot())
        picture.name="QingTian-restored-final-measure-source"
        picture.lifetime = .keepAlways;add(picture)
        app.navigationBars["原谱第3页"].buttons.firstMatch.tap()
        app.navigationBars["第60小节"].buttons.firstMatch.tap()
        let confirm=app.switches["我已对照原谱核对音符、节奏、调弦和速度"]
        visible(confirm);confirm.coordinate(withNormalizedOffset:.init(dx:0.92,dy:0.5)).tap()
        XCTAssertEqual(confirm.value as? String,"1")
        let publish=app.buttons["score.publish"];visible(publish)
        XCTAssertFalse(publish.isEnabled,"Restoring the missing measures does not resolve all missing music.")
    }

    func testTwoPageZhizuDraftCannotPublishAsCompleteMusic() throws {
        let env=ProcessInfo.processInfo.environment
        guard let dir=env["GITA_FULL_SCORE_DIR"] ?? env["TEST_RUNNER_GITA_FULL_SCORE_DIR"] else {
            throw XCTSkip("Requires the authorized two-page local score")
        }
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-UITesting","-ScoreRecoveryFixture","-AppleLanguages","(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"]=UUID().uuidString
        let paths=["知足-知足1.jpg","知足-知足2.jpg"].map {URL(fileURLWithPath:dir).appendingPathComponent($0).path}
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATHS"]=String(decoding:try JSONEncoder().encode(paths),as:UTF8.self)
        func visible(_ item:XCUIElement) {
            for _ in 0..<24 where !item.isHittable {app.swipeUp()}
            XCTAssertTrue(item.isHittable,app.debugDescription)
        }
        app.launch()
        let tools=app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout:15));tools.tap()
        let link=app.buttons["tools.item.playAlong"];visible(link);link.tap()
        XCTAssertTrue(app.buttons["score.import"].waitForExistence(timeout:8))
        app.buttons["score.import"].tap();app.buttons["导入 PDF 或图片"].tap()
        let local=app.buttons["score.local-tab"]
        XCTAssertTrue(local.waitForExistence(timeout:10));visible(local);local.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout:30),app.debugDescription)
        XCTAssertTrue(app.buttons["查看原谱第2页"].exists)
        let chordBar=app.buttons.matching(NSPredicate(format:"label BEGINSWITH '第9小节 ·'")).firstMatch
        visible(chordBar);chordBar.tap()
        XCTAssertTrue(app.navigationBars["第9小节"].waitForExistence(timeout:8))
        let binding=app.staticTexts["按指法图推导：5:3"]
        visible(binding)
        let boundScreenshot=XCTAttachment(screenshot:app.screenshot())
        boundScreenshot.name="Zhizu-C-to-G-printed-diagram-binding"
        boundScreenshot.lifetime = .keepAlways
        add(boundScreenshot)
        app.navigationBars["第9小节"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout:8))
        let confirm=app.switches["我已对照原谱核对音符、节奏、调弦和速度"]
        visible(confirm)
        confirm.coordinate(withNormalizedOffset:.init(dx:0.92,dy:0.5)).tap()
        XCTAssertEqual(confirm.value as? String,"1")
        let publish=app.buttons["score.publish"];visible(publish)
        XCTAssertFalse(publish.isEnabled,"An incomplete recognition draft must not publish despite the confirmation toggle.")
        let warning=app.staticTexts.matching(NSPredicate(format:"label CONTAINS '个小节需要处理'")).firstMatch
        XCTAssertTrue(warning.exists,app.debugDescription)
        let screenshot=XCTAttachment(screenshot:app.screenshot())
        screenshot.name="Zhizu-two-page-draft-blocked-from-publishing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLocalTabFailureStopsLoadingAndAllowsRetry() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["GITA_LOCAL_FAILURE_PAGE"] ?? env["TEST_RUNNER_GITA_LOCAL_FAILURE_PAGE"] else {
            throw XCTSkip("Requires the local unsupported photographed score")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATH"] = path
        app.launch()
        let tools = app.tabBars.buttons["工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15)); tools.tap()
        let link = app.buttons["tools.item.playAlong"]
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.buttons["score.import"].waitForExistence(timeout: 8))
        app.buttons["score.import"].tap(); app.buttons["导入 PDF 或图片"].tap()
        let local = app.buttons["score.local-tab"]
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '未读到可靠的六线谱符号' ")).firstMatch
        for _ in 0..<2 {
            XCTAssertTrue(local.waitForExistence(timeout: 8))
            for _ in 0..<12 where !local.isHittable { app.swipeUp() }
            XCTAssertTrue(local.isHittable); local.tap()
            XCTAssertTrue(failure.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(local.exists && local.isEnabled)
            XCTAssertFalse(app.staticTexts["正在本机读取六线谱…"].exists)
        }
    }

    func testLocalTabImportRestoresLiteralDraft() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["GITA_LOCAL_UI_PAGE"] ?? env["TEST_RUNNER_GITA_LOCAL_UI_PAGE"] else {
            throw XCTSkip("Requires a local printed TAB page")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATH"] = path
        func visible(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        func library() {
            let tools = app.tabBars.buttons["工具"]
            XCTAssertTrue(tools.waitForExistence(timeout: 15))
            tools.tap()
            let link = app.buttons["tools.item.playAlong"]
            visible(link); link.tap()
        }
        app.launch(); library()
        app.buttons["score.import"].tap()
        app.buttons["导入 PDF 或图片"].tap()
        let local = app.buttons["score.local-tab"]
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        visible(local); local.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); library()
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'score.pending.'")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 8)); pending.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 8))
        let first = app.buttons.matching(NSPredicate(format:"label BEGINSWITH '第1小节 ·'")).firstMatch
        visible(first); first.tap()
        let chord = app.buttons["按和弦指法补录多拍"]
        XCTAssertTrue(chord.waitForExistence(timeout: 8))
        visible(chord); chord.tap()
        XCTAssertTrue(app.navigationBars["按指法补录"].waitForExistence(timeout: 5))
    }

    func testInterruptedRecognitionRestoresCorrectedScoreAndSavesLoopPractice() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let imagePath = environment["GITA_RECOVERY_IMAGE"] ?? environment["TEST_RUNNER_GITA_RECOVERY_IMAGE"] else {
            throw XCTSkip("Run the local fixture server and set TEST_RUNNER_GITA_RECOVERY_IMAGE to a simulator-readable page.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ScoreRecoveryFixture", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["GITA_RECOVERY_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["GITA_RECOVERY_PAGE_PATH"] = imagePath

        func scrollTo(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        func openLibrary() {
            let tools = app.tabBars.buttons["工具"]
            XCTAssertTrue(tools.waitForExistence(timeout: 10))
            tools.tap()
            let playAlong = app.buttons["tools.item.playAlong"]
            scrollTo(playAlong)
            playAlong.tap()
            XCTAssertTrue(app.buttons["score.import"].waitForExistence(timeout: 8))
        }
        func assertSavedLoop() {
            XCTAssertTrue(app.navigationBars["跟谱记录"].waitForExistence(timeout: 8))
            let rows = app.descendants(matching: .any)
            XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS 'Fixture Score'")).firstMatch.exists, app.debugDescription)
            XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS '练习 · 第1–2小节 · 75%速度'")).firstMatch.exists, app.debugDescription)
            let synced = rows.matching(
                NSPredicate(format: "label MATCHES %@", "(?s).*已同步到当天练习 · 完整循环[1-9][0-9]*次.*")
            ).firstMatch
            XCTAssertTrue(synced.exists, app.debugDescription)
        }

        app.launch()
        openLibrary()
        app.buttons["score.import"].tap()
        app.buttons["导入 PDF 或图片"].tap()
        let upload = app.buttons["score.recognize"]
        XCTAssertTrue(upload.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(upload)
        upload.tap()
        let accepted = app.descendants(matching: .any)["score.job-running"].firstMatch
        XCTAssertTrue(accepted.waitForExistence(timeout: 8), app.debugDescription)
        app.terminate()

        app.launch()
        openLibrary()
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'score.pending.'")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(pending.label.contains(URL(fileURLWithPath: imagePath).lastPathComponent))
        pending.tap()
        XCTAssertTrue(app.navigationBars["识谱校正"].waitForExistence(timeout: 45), app.debugDescription)
        let tempo = app.textFields["速度"]
        XCTAssertEqual(tempo.value as? String, "68")
        tempo.doubleTap()
        tempo.typeText("80")
        app.buttons["查看原谱第1页"].tap()
        let original = app.navigationBars["原谱第1页"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.buttons.firstMatch.tap()
        XCTAssertEqual(tempo.value as? String, "80")
        let confirm = app.switches["我已对照原谱核对音符、节奏、调弦和速度"]
        scrollTo(confirm)
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(confirm.value as? String, "1")
        let publish = app.buttons["score.publish"]
        scrollTo(publish)
        XCTAssertTrue(publish.isEnabled)
        publish.tap()

        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'score.library.' AND label CONTAINS 'Fixture Score'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8), app.debugDescription)
        saved.tap()
        let start = app.buttons["score.start"]
        scrollTo(start)
        start.tap()
        app.buttons["新建今日练习"].tap()
        XCTAssertTrue(app.staticTexts["60 BPM · 4分音符"].waitForExistence(timeout: 8), "Corrected 80 BPM at 75% speed")
        let looped = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1/5次循环'")).firstMatch
        XCTAssertTrue(looped.waitForExistence(timeout: 25), app.debugDescription)
        app.buttons["暂停并返回"].tap()
        app.buttons["保存并结束"].tap()
        assertSavedLoop()

        app.terminate()
        app.launch()
        openLibrary()
        let history = app.buttons["跟谱练习记录"]
        scrollTo(history)
        history.tap()
        assertSavedLoop()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Restored-score-saved-loop-practice"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testToolChooserCanCancelThenStartAndSaveTwice() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]; app.launch()
        app.tabBars.buttons["工具"].tap()
        let tool = app.buttons["tools.item.playAlong"]
        for _ in 0..<3 where !tool.isHittable { app.swipeUp() }; tool.tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000001"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.navigationBars["保存到哪个练习？"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["暂停并返回"].exists)
        for _ in 0..<2 {
            for _ in 0..<3 where !start.isHittable { app.swipeUp() }
            start.tap()
            let choose = app.buttons["新建今日练习"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5)); choose.tap()
            XCTAssertTrue(app.buttons["暂停并返回"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["00:02"].waitForExistence(timeout: 12))
            app.buttons["暂停并返回"].tap(); app.buttons["保存并结束"].tap()
            XCTAssertTrue(app.navigationBars["跟谱记录"].waitForExistence(timeout: 6))
            app.buttons["完成"].tap()
            XCTAssertTrue(start.waitForExistence(timeout: 5))
        }
    }
    func testExistingPracticeCanSaveScoreAndReturnToWorkingNoteTools() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]; app.launch()
        app.buttons["practice.create-button"].tap()
        let title = app.textFields["practice.create-name"]; title.tap(); title.typeText("跟谱返回工具栏回归")
        app.buttons["确认并创建练习"].tap()
        let material = app.buttons["practice.score-material"]
        XCTAssertTrue(material.waitForExistence(timeout: 5))
        for _ in 0..<4 where !material.isHittable { app.swipeUp() }; material.tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000001"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }; start.tap()
        XCTAssertTrue(app.staticTexts["00:02"].waitForExistence(timeout: 12))
        app.buttons["暂停并返回"].tap(); app.buttons["保存并结束"].tap()
        XCTAssertTrue(app.navigationBars["跟谱记录"].waitForExistence(timeout: 6))
        app.buttons["完成"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        if !app.buttons["关闭"].exists { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 5)); app.buttons["关闭"].tap()
        XCTAssertTrue(material.waitForExistence(timeout: 5))
        let voice = app.descendants(matching: .any)["practice.dictation.start"].firstMatch
        for _ in 0..<6 where !voice.isHittable { app.swipeUp() }
        XCTAssertTrue(voice.exists,"The previously crashing note tools must render after score exit.")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 3),"The returned detail must handle touches.")
    }
    func testSavingPlayedScoreReturnsToResponsivePreparation() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]; app.launch()
        app.buttons["practice.create-button"].tap()
        app.segmentedControls["practice.create-mode"].buttons["跟谱练习"].tap()
        app.buttons["practice.confirm-create"].tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000001"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }; start.tap()
        XCTAssertTrue(app.buttons["暂停并返回"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["00:02"].waitForExistence(timeout: 12),"Must save after actual practice, beyond count-in.")
        app.buttons["暂停并返回"].tap()
        app.buttons["保存并结束"].tap()
        XCTAssertTrue(app.navigationBars["跟谱记录"].waitForExistence(timeout: 6),"Save must finish the player dismissal and present its saved record.")
        app.buttons["完成"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["暂停并返回"].waitForExistence(timeout: 5),"The screen must remain responsive for another attempt.")
        app.buttons["暂停并返回"].tap(); app.buttons["保存并结束"].tap()
    }
    func testDarkCombinedScorePausesInBackgroundAndRequiresManualResume() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)","-gita.appearance","dark"]; app.launch()
        app.tabBars.buttons["工具"].tap()
        let tool = app.buttons["tools.item.playAlong"]
        for _ in 0..<3 where !tool.isHittable { app.swipeUp() }; tool.tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000003"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }; start.tap()
        app.buttons["新建今日练习"].tap()
        XCTAssertTrue(app.buttons["跟谱设置"].waitForExistence(timeout: 5)); app.buttons["跟谱设置"].tap()
        XCTAssertTrue(app.navigationBars["跟谱设置"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '谱面' ")).firstMatch.tap()
        app.buttons["双谱"].tap(); app.buttons["完成"].tap()
        app.buttons["开始"].tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Gita-follow-score-dark-combined-background-paused"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCreatePracticeEntryStartsScoreWithoutCreatingAnExtraPlainTask() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]; app.launch()
        app.buttons["practice.create-button"].tap()
        app.segmentedControls["practice.create-mode"].buttons["跟谱练习"].tap()
        app.buttons["practice.confirm-create"].tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000001"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["暂停并返回"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["新建今日练习"].exists)
        app.buttons["暂停并返回"].tap()
        app.buttons["保存并结束"].tap()
    }
    func testExistingPracticeCanAssociateScoreWithoutStartingPlayback() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]; app.launch()
        app.buttons["practice.create-button"].tap()
        let title = app.textFields["practice.create-name"]; title.tap(); title.typeText("跟谱材料关联测试")
        app.buttons["确认并创建练习"].tap()
        let material = app.buttons["practice.score-material"]
        XCTAssertTrue(material.waitForExistence(timeout: 5))
        for _ in 0..<4 where !material.isHittable { app.swipeUp() }
        material.tap()
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000002"]
        XCTAssertTrue(score.waitForExistence(timeout: 5)); score.tap()
        app.buttons["score.associate"].tap()
        XCTAssertTrue(app.buttons["已关联到练习"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["暂停并返回"].exists)
    }
    func testToolEntryCreatesRealPracticeAndCanSaveAReusablePassage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting","-AppleLanguages","(zh-Hans)"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] '允许' OR label == 'Allow' OR label == 'OK' ")).firstMatch
            if allow.exists { allow.tap(); return true }; return false
        }
        app.tabBars.buttons["工具"].tap()
        let tool = app.buttons["tools.item.playAlong"]
        for _ in 0..<3 where !tool.isHittable { app.swipeUp() }
        tool.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.library"].firstMatch.waitForExistence(timeout: 6),app.debugDescription)
        let score = app.buttons["score.library.B17A0000-0000-4000-8000-000000000003"]
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        score.tap()
        let start = app.buttons["score.start"]
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        start.tap()
        app.buttons["新建今日练习"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.player"].firstMatch.waitForExistence(timeout: 5),app.debugDescription)
        if app.alerts.firstMatch.exists { app.tap() }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let window = app.windows.firstMatch
        expectation(for: NSPredicate { _,_ in window.frame.width > window.frame.height },evaluatedWith: window)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["75 BPM · 4分音符"].exists)
        let playerImage = XCTAttachment(screenshot: window.screenshot())
        playerImage.name = "Gita-follow-score-landscape-TAB"
        playerImage.lifetime = .keepAlways
        add(playerImage)
        app.buttons["跟谱设置"].tap()
        XCTAssertTrue(app.navigationBars["跟谱设置"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '谱面' ")).firstMatch.tap()
        app.buttons["五线谱"].tap()
        app.buttons["完成"].tap()
        let staffImage = XCTAttachment(screenshot: window.screenshot())
        staffImage.name = "Gita-follow-score-landscape-staff"
        staffImage.lifetime = .keepAlways
        add(staffImage)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["标记难点"].tap()
        XCTAssertTrue(app.navigationBars["保存难点"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        app.buttons["我的难点"].tap()
        XCTAssertTrue(app.buttons["开始专项练习"].firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gita-follow-score-saved-passage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
