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

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 1).tap()

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

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 1).tap()
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

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 1).tap()
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

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.scrollViews["absenceList"].waitForExistence(timeout: 5))

        let openButton = app.descendants(matching: .any)["absencePredictorOpenButton"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        openButton.tap()

        let lesson = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "absencePredictorLesson-"))
            .firstMatch
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

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 1).tap()
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
