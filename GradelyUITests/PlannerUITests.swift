import XCTest

final class PlannerUITests: XCTestCase {
    @MainActor
    func testLessonItemPrefillsContextFindsNextLessonAndShowsIndicator() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-settings.appLanguage", "english"]
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.buttons["dayChip-1"].waitForExistence(timeout: 5))
        app.buttons["dayChip-1"].tap()
        let lesson = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lessonRow-")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()
        let addButton = app.buttons["lessonAddPlannerButton"]
        for _ in 0..<3 where !addButton.isHittable { app.swipeUp() }
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let title = app.textFields["plannerTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Matematika"].exists)
        title.tap()
        title.typeText("Prepare equations")
        let next = app.buttons["plannerNextLessonButton"]
        // SwiftUI can report offscreen Form buttons as hittable under the software keyboard.
        // Scroll within the visible form area instead of relying on that flag.
        for _ in 0..<6 {
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 44 : app.frame.maxY
            if next.exists, next.frame.maxY < keyboardTop - 20, next.frame.minY > 150 { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: keyboardTop - 40))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: 200))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let includeTime = app.switches["Include time"]
        XCTAssertTrue(includeTime.waitForExistence(timeout: 5))
        XCTAssertEqual(includeTime.value as? String, "1")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Planner lesson due date"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["plannerSaveButton"].tap()
        // Calendar sync is on by default and the mock build has no Calendar service,
        // so the editor reports the item was kept locally before dismissing.
        let savedLocally = app.alerts.buttons["Done"].firstMatch
        XCTAssertTrue(savedLocally.waitForExistence(timeout: 5))
        savedLocally.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modalDismissButton"].waitForExistence(timeout: 5))
        app.buttons["modalDismissButton"].tap()
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(lesson.label.contains("Homework"))
    }

    @MainActor
    func testDayItemCanBeCreatedEditedCompletedAndDeleted() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-settings.appLanguage", "english"]
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 3).tap()
        // The timetable no longer plans a day itself; the planner owns undated items.
        XCTAssertTrue(app.buttons["timetablePlannerButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["timetableAddDayPlannerButton"].exists)
        app.buttons["timetablePlannerButton"].tap()

        let add = app.buttons["plannerAddButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let title = app.textFields["plannerTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Planner smoke task")
        app.buttons["plannerSaveButton"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plannerItem-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" edited")
        app.buttons["plannerSaveButton"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Planner smoke task edited"].exists)

        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plannerComplete-")).firstMatch.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.buttons["plannerFilterCompleted"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Deleting now lives in the editor, so the list stays a plain Gradely card stack.
        row.tap()
        let delete = app.buttons["plannerDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        // The editor's own button is also labelled "Delete"; confirm on the dialog's.
        let confirmDelete = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Delete", "plannerDeleteButton")
        ).firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }
}
