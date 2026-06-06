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
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-subject-Matematika").firstMatch.waitForExistence(timeout: 3))

        segment.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "absenceRow-month-2026-02-01").firstMatch.waitForExistence(timeout: 3))
    }
}
