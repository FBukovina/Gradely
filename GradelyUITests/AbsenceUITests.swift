import XCTest

final class AbsenceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAbsenceTabShowsDaySubjectAndMonthViews() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 2).tap()

        XCTAssertTrue(app.scrollViews["absenceList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["absenceSegmentedControl"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["absenceRow-total"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-day-2026-02-10T00:00:00+01:00").firstMatch.exists)

        let segment = app.segmentedControls["absenceSegmentedControl"]
        XCTAssertTrue(segment.waitForExistence(timeout: 3))

        segment.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-subject-0-matematika").firstMatch.waitForExistence(timeout: 3))

        segment.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-month-2026-02-01").firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAbsenceSubjectsFallbackDoesNotCrashWhenOfficialRowsAreMissing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingEmptySubjectAbsence"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.scrollViews["absenceList"].waitForExistence(timeout: 5))

        let segment = app.segmentedControls["absenceSegmentedControl"]
        XCTAssertTrue(segment.waitForExistence(timeout: 3))
        segment.buttons.element(boundBy: 0).tap()

        let descendants = app.descendants(matching: .any)
        let possibleStates = [
            descendants["absenceSubjectsCalculating"],
            descendants["absenceSubjectsEmpty"],
            descendants["absenceSubjectsError"],
            descendants["absenceSubjectsWarning"],
            descendants["absenceManualResolutionCallout"],
            descendants.matching(identifier: "absenceRow-subject-0-raw-math").firstMatch,
            descendants.matching(identifier: "absenceRow-subject-1-raw-czech").firstMatch,
            descendants.matching(identifier: "absenceRow-subject-2-raw-bio").firstMatch
        ]

        XCTAssertTrue(waitForAnyElement(possibleStates, timeout: 8))
    }

    @MainActor
    func testAbsenceManualSubjectLessonSelectionUpdatesRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingManualSubjectAbsence"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.scrollViews["absenceList"].waitForExistence(timeout: 5))

        let segment = app.segmentedControls["absenceSegmentedControl"]
        XCTAssertTrue(segment.waitForExistence(timeout: 3))
        segment.buttons.element(boundBy: 0).tap()

        let resolveButton = app.descendants(matching: .any)["absenceManualResolveButton"]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 8))
        resolveButton.tap()

        let lesson = app.descendants(matching: .any)["absenceManualLesson-lesson-2026-02-02-2-raw-tev"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()

        let saveButton = app.buttons["absenceManualSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-subject-1-raw-tev").firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testAbsencePredictorShowsProjectedSummaryAfterChoosingLesson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        // The predictor belongs with the other absence tools.
        app.tabBars.buttons.element(boundBy: 2).tap()
        let scrollView = app.scrollViews["absenceList"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        let openButton = app.descendants(matching: .any)["absencePredictorOpenButton"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))

        var scrollAttempts = 0
        while !openButton.isHittable && scrollAttempts < 8 {
            scrollView.swipeUp()
            scrollAttempts += 1
        }
        openButton.tap()

        let lesson = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "absencePredictorLesson-"))
            .firstMatch

        // The mock timetable only has lessons Monday-Friday; on weekends the
        // preselected "today" legitimately offers nothing to plan.
        let noLessons = app.descendants(matching: .any)["absencePredictorNoLessons"]
        if noLessons.waitForExistence(timeout: 3), !lesson.exists {
            throw XCTSkip("No countable lessons for today's date in the mock timetable (weekend).")
        }

        XCTAssertTrue(lesson.waitForExistence(timeout: 8))
        lesson.tap()

        let doneButton = app.buttons["absencePredictorDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["absencePredictionTotal"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAbsenceLargeSubjectsFallbackDoesNotCrashWhenTappedImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingLargeAbsenceSubjects"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.scrollViews["absenceList"].waitForExistence(timeout: 5))

        let segment = app.segmentedControls["absenceSegmentedControl"]
        XCTAssertTrue(segment.waitForExistence(timeout: 3))
        segment.buttons.element(boundBy: 0).tap()

        let descendants = app.descendants(matching: .any)
        let possibleStates = [
            descendants["absenceSubjectsCalculating"],
            descendants["absenceSubjectsEmpty"],
            descendants["absenceSubjectsError"],
            descendants["absenceSubjectsWarning"],
            descendants.matching(identifier: "absenceRow-subject-0-raw-ui-large-subject-0").firstMatch
        ]

        XCTAssertTrue(waitForAnyElement(possibleStates, timeout: 8))
    }

    @MainActor
    func testHiddenAbsencePersistsAcrossRelaunchAndRestores() throws {
        let app = XCUIApplication()
        let arguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingManualSubjectAbsence", "-uiTestingPersistentAbsenceOverrides"]
        app.launchArguments = arguments + ["-uiTestingResetAbsenceOverrides"]
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 2).tap()
        let day = app.buttons["absenceRow-day-2026-02-02T00:00:00+01:00"]
        XCTAssertTrue(day.waitForExistence(timeout: 8))
        day.tap()

        let original = app.buttons["absenceOverrideOriginal-lesson-2026-02-02-2-raw-tev"]
        XCTAssertTrue(original.waitForExistence(timeout: 8))
        original.tap()
        app.buttons["absenceOverrideConfirmOriginal"].tap()
        let hide = app.buttons["absenceOverrideHideDay"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        XCTAssertFalse(app.staticTexts["absence.category.ok"].exists)
        let preview = app.descendants(matching: .any)["absenceOverridePreview"]
        var previewScrolls = 0
        while !preview.isHittable && previewScrolls < 4 {
            app.swipeUp()
            previewScrolls += 1
        }
        XCTAssertTrue(preview.exists)
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "Absence editor before saving"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
        let save = app.buttons["absenceOverrideSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["absenceLocallyAdjusted"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any)["absenceLocallyAdjusted"].waitForExistence(timeout: 8))
        app.buttons["absenceHiddenButton"].tap()
        let restore = app.buttons["absenceHiddenRestore-2026-02-02"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        let managementScreenshot = XCTAttachment(screenshot: app.screenshot())
        managementScreenshot.name = "Hidden absences after relaunch"
        managementScreenshot.lifetime = .keepAlways
        add(managementScreenshot)
        restore.tap()
        XCTAssertTrue(app.descendants(matching: .any)["absenceHiddenEmpty"].waitForExistence(timeout: 5))
    }

    private func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return elements.contains(where: { $0.exists })
    }
}
