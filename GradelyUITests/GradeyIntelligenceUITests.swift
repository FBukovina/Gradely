import XCTest

final class GradeyIntelligenceUITests: XCTestCase {
    @MainActor func testEnglishChronicallyOnlineTodayHasReadableCopy() throws {
        let app = try verifyDialectToday(language: "englishChronicallyOnline", studyTitle: "study priorities", weekTitle: "week summary")
        app.buttons["marks"].firstMatch.tap()
        let subject = app.descendants(matching: .any)["subjectRow-math"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        subject.tap()
        let simulator = app.buttons["openGradeSimulatorButton"]
        for _ in 0..<6 where !simulator.isHittable { app.swipeUp() }
        XCTAssertTrue(simulator.isHittable)
        simulator.tap()
        XCTAssertTrue(app.textFields["gradeTargetAverageField"].waitForExistence(timeout: 5))
        for text in app.staticTexts.allElementsBoundByIndex {
            XCTAssertFalse(text.label.lowercased().hasPrefix("detail."), "Unresolved simulator localization: \(text.label)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "English CO localized grade simulator"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testCzechChronicallyOnlineTodayHasReadableCopyAtLargeText() throws {
        _ = try verifyDialectToday(language: "czechChronicallyOnline", studyTitle: "na co se zaměřit", weekTitle: "přehled týdne", largeText: true)
    }

    @MainActor private func verifyDialectToday(language: String, studyTitle: String, weekTitle: String, largeText: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingCachedMarks", "-settings.appLanguage", language,
            "-UIPreferredContentSizeCategoryName", largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let scroll = app.scrollViews["todayScrollView"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let study = app.buttons["todayStudyPrioritiesButton"].firstMatch
        let week = app.buttons["todayWeekSummaryButton"].firstMatch
        for _ in 0..<8 where !study.isHittable { scroll.swipeUp() }
        XCTAssertTrue(study.isHittable)
        XCTAssertEqual(study.label, studyTitle)
        for _ in 0..<4 where !week.isHittable { scroll.swipeUp() }
        XCTAssertTrue(week.isHittable)
        XCTAssertEqual(week.label, weekTitle)
        for button in [study, week] {
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        if largeText {
            XCTAssertGreaterThanOrEqual(week.frame.minY, study.frame.maxY, "Large-text actions must stack without overlap")
        }
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label) + app.buttons.allElementsBoundByIndex.map(\.label)
        for label in labels {
            XCTAssertFalse(["today.", "gradey.ai.", "action."].contains { label.lowercased().hasPrefix($0) }, "Unresolved localization: \(label)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Today \(language) localized actions"
        shot.lifetime = .keepAlways
        add(shot)
        return app
    }

    @MainActor func testTodayAndOfflineGradeSimulator() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingCachedMarks", "-settings.appLanguage", "english"]
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["todayAttentionCard"].exists)
        app.buttons["Marks"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["subjectRow-math"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["subjectRow-math"].tap()
        let open = app.buttons["openGradeSimulatorButton"]
        for _ in 0..<5 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.textFields["gradeTargetAverageField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gradeTargetResults"].exists)
        app.segmentedControls["gradeSimulatorMode"].buttons.element(boundBy: 1).tap()
        let addGrade = app.buttons["addHypotheticalGradeButton"]
        for _ in 0..<4 where !addGrade.isHittable { app.swipeUp() }
        XCTAssertTrue(addGrade.exists)
        addGrade.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hypotheticalGrade-0"].exists)
        for _ in 0..<4 where !addGrade.isHittable { app.swipeUp() }
        addGrade.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hypotheticalGrade-1"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Gradey 2.2 multi-grade simulator"
        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testCzechLargeTextDarkToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingCachedMarks",
            "-settings.appLanguage", "czech",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["todayRefreshButton"].exists)
        XCTAssertTrue(app.staticTexts["Dnes"].firstMatch.exists || app.buttons["Dnes"].firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Gradey 2.2 Czech dark large text Today"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
