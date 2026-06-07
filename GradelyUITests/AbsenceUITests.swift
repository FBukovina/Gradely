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
            descendants.matching(identifier: "absenceRow-subject-0-matematika").firstMatch,
            descendants.matching(identifier: "absenceRow-subject-1-cesky-jazyk").firstMatch
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
