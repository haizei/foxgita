import XCTest

final class DNAProgramsJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-DNAProgramsUITesting"]
        app.launch()
    }

    func testQuestionnaireDraftAndExplicitRoutineSave() {
        XCTAssertTrue(app.staticTexts["通用方案"].waitForExistence(timeout: 10))
        tap("program.preferences")
        tap("dna.choice.story")
        tap("dna.next")
        tap("dna.exit")
        tap("program.preferences")
        XCTAssertTrue(app.staticTexts["02 / 08"].waitForExistence(timeout: 5))
        for _ in 0..<2 { tap("dna.next") }
        tap("dna.choice.20")
        tap("dna.next")
        tap("dna.choice.connect")
        tap("dna.next")
        tap("dna.choice.improv")
        tap("dna.next")
        tap("dna.next")
        tap("dna.choice.improv")
        tap("dna.next")
        tap("dna.submit")
        XCTAssertTrue(app.staticTexts["方案预览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["20 分钟 · 4 个分段"].exists)
        tap("program.close")
        XCTAssertTrue(app.staticTexts["通用方案"].waitForExistence(timeout: 5))
        tap("program.draft")
        XCTAssertTrue(app.staticTexts["方案预览"].waitForExistence(timeout: 5))
        tap("program.save")
        XCTAssertTrue(app.staticTexts["已保存方案"].waitForExistence(timeout: 5))
    }

    func testCandidatesDeduplicateAndChecklistKeepsActualPartialProgress() {
        launchWithPreferences()
        tap("program.add.dna.improv")
        XCTAssertTrue(app.staticTexts["1 项 · 9 分钟"].exists)
        tap("program.add.dna.improv")
        XCTAssertTrue(app.staticTexts["1 项 · 9 分钟"].exists)
        tap("program.add.dna.expression")
        tap("program.start-checklist")
        XCTAssertTrue(app.staticTexts["今日清单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第 1 / 2 段"].exists)
        tap("program.test-minute")
        tap("program.complete-stage")
        tap("program.skip-stage")
        XCTAssertTrue(app.staticTexts["部分完成"].exists)
        XCTAssertEqual(app.staticTexts["program.summary-completed"].label, "完成 1 / 2 段")
        XCTAssertTrue(app.staticTexts["program.summary-seconds"].label.contains("60 秒"))
        tap("program.records")
        XCTAssertTrue(app.staticTexts["方案与清单训练"].waitForExistence(timeout: 5))
    }

    func testRoutineAggregatesFourFactsWithoutDuplicatingDuration() {
        tap("program.start-routine")
        XCTAssertTrue(app.staticTexts["方案练习"].waitForExistence(timeout: 5))
        for _ in 0..<4 {
            tap("program.test-stage-duration")
            tap("program.complete-stage")
        }
        XCTAssertEqual(app.staticTexts["program.summary-completed"].label, "完成 4 / 4 段")
        XCTAssertEqual(app.staticTexts["program.summary-seconds"].label.replacingOccurrences(of: ",", with: ""), "实练 1800 秒 · 明细聚合，不重复累计")
        tap("program.records")
        XCTAssertTrue(app.staticTexts["方案与清单训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30 分钟"].exists)
        XCTAssertFalse(app.staticTexts["60 分钟"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPauseSwitchAndNextDayResumeKeepIndependentFacts() {
        launchWithPreferences()
        tap("program.add.dna.improv")
        tap("program.start-routine")
        tap("program.test-minute")
        tap("program.pause-resume")
        tap("program.test-five-minutes")
        XCTAssertEqual(app.staticTexts["program.elapsed"].label, "01:00")
        tap("program.training-home")
        tap("program.start-checklist")
        XCTAssertTrue(app.staticTexts["第 1 / 1 段"].exists)
        tap("program.test-half-minute")
        tap("program.end")
        XCTAssertTrue(app.staticTexts["program.summary-seconds"].label.contains("30 秒"))
        tap("program.training-home")
        tap("program.start-checklist")
        tap("program.test-minute")
        tap("program.end")
        XCTAssertTrue(app.staticTexts["program.summary-seconds"].label.contains("60 秒"))
        tap("program.training-home")
        tap("program.start-routine")
        XCTAssertEqual(app.staticTexts["program.elapsed"].label, "01:00")
        tap("program.pause-resume")
        tap("program.test-next-day")
        tap("program.pause-resume")
        tap("program.test-minute")
        tap("program.end")
        XCTAssertEqual(app.staticTexts["program.summary-completed"].label, "完成 0 / 4 段")
        XCTAssertTrue(app.staticTexts["program.summary-seconds"].label.contains("120 秒"))
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS '查看实际练习明细'"))
        XCTAssertGreaterThanOrEqual(details.count, 2)
        XCTAssertEqual(Set(details.allElementsBoundByIndex.map(\.label)).count, 2)
        tap("program.records")
        XCTAssertTrue(app.staticTexts["方案与清单训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["部分完成 · 30 秒"].exists)
        XCTAssertTrue(app.staticTexts["部分完成 · 60 秒"].exists)
        XCTAssertTrue(app.staticTexts["部分完成 · 120 秒"].exists)
    }

    func testSaveFailureRetryAndPreferenceUpdatesProtectArrangements() {
        launchWithPreferences()
        tap("program.add.dna.improv")
        tap("program.add.dna.vocabulary")
        tap("program.start-routine")
        tap("program.test-minute")
        tap("program.training-home")
        tap("program.details")
        tap("program.edit")
        let name = app.textFields["program.name"]
        name.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { name.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "我的保存方案")
        tap("program.dismiss-keyboard")
        tap("program.test-draft-save-failure")
        tap("program.save")
        XCTAssertTrue(app.staticTexts["草稿暂时没能保存，当前修改仍在此页，请重试"].waitForExistence(timeout: 5))
        tap("program.test-save-failure")
        tap("program.save")
        XCTAssertTrue(app.staticTexts["暂时没能保存方案，草稿已保留，请重试"].exists)
        tap("program.close")
        XCTAssertFalse(app.buttons["program.details"].label.contains("我的保存方案"))
        tap("program.draft")
        XCTAssertEqual(app.textFields["program.name"].value as? String, "我的保存方案")
        tap("program.save")
        XCTAssertTrue(app.buttons["program.details"].label.contains("我的保存方案"))
        tap("program.preferences")
        tap("dna.edit.priority")
        tap("dna.choice.chord")
        tap("dna.next")
        tap("dna.choice.blues")
        tap("dna.next")
        tap("dna.next")
        tap("dna.submit")
        tap("program.close")
        XCTAssertTrue(app.buttons["program.details"].label.contains("我的保存方案"))
        XCTAssertTrue(app.staticTexts["2 项 · 16 分钟"].exists)
        tap("program.add.dna.vocabulary")
        XCTAssertTrue(app.staticTexts["3 项 · 23 分钟"].exists)
        tap("program.add.dna.vocabulary")
        XCTAssertTrue(app.staticTexts["3 项 · 23 分钟"].exists)
        tap("program.add.dna.chord")
        XCTAssertTrue(app.staticTexts["4 项 · 32 分钟"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["超出建议预算 2 分钟，仍可开始"].waitForExistence(timeout: 5))
        tap("program.start-routine")
        XCTAssertTrue(app.staticTexts["即兴演奏"].exists)
        XCTAssertEqual(app.staticTexts["program.elapsed"].label, "01:00")
    }

    private func launchWithPreferences() {
        app.terminate()
        app.launchArguments += ["-DNAProgramsPreferencesFixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["已保存方案"].waitForExistence(timeout: 10))
    }

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        let scroller = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : (app.scrollViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch)
        for _ in 0..<7 {
            let footer = app.buttons["program.start-checklist"]
            let homeControl = identifier.hasPrefix("program.add.") || ["program.preferences", "program.draft", "program.details", "program.start-routine"].contains(identifier)
            let coveredByFooter = homeControl && footer.exists && element.exists && element.frame.maxY >= footer.frame.minY - 16
            if element.exists && element.isHittable && !coveredByFooter { break }
            scroller.swipeUp()
        }
        if !element.exists || !element.isHittable {
            for _ in 0..<5 where !element.exists || !element.isHittable { scroller.swipeDown() }
        }
        if !element.exists {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), identifier)
        element.tap()
    }
}
