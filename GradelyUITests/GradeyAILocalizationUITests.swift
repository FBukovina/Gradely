import XCTest

final class GradeyAILocalizationUITests: XCTestCase {
    @MainActor
    func testEnglishConsentContextAndComputeAreReadable() throws {
        try verifyAI(language: "english", czech: false, largeText: false)
    }

    @MainActor
    func testCzechConsentContextAndComputeAreReadable() throws {
        try verifyAI(language: "czech", czech: true, largeText: false)
    }

    @MainActor
    func testEnglishChronicallyOnlineAIAtLargeText() throws {
        try verifyAI(language: "englishChronicallyOnline", czech: false, largeText: true)
    }

    @MainActor
    func testCzechChronicallyOnlineAIAtLargeText() throws {
        try verifyAI(language: "czechChronicallyOnline", czech: true, largeText: true)
    }

    @MainActor
    private func verifyAI(language: String, czech: Bool, largeText: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // This selects MockGradeyAIClient and mock school/context repositories.
        // The test accepts mock consent and opens a draft, but never sends it.
        app.launchArguments = [
            "-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingCachedMarks",
            "-uiTestingResetGuestMode", "-uiTestingGradeyAIConsentRequired", "-uiTestingGradeyAIQuota",
            "-settings.appLanguage", language,
            "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        let entry = app.buttons["gradeyAIButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let consent = app.descendants(matching: .any)["gradeyAIConsentView"].firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIAIActDisclosure"].exists)
        let accept = app.buttons["gradeyAIConsentButton"].firstMatch
        var consentLabels = readableLabels(in: consent)
        for _ in 0..<14 {
            assertReadableLabels(consentLabels)
            assertVisibleTextFits(in: consent, app: app)
            if isVisibleAndHittable(accept, app: app) { break }
            consent.swipeUp()
            consentLabels += readableLabels(in: consent)
        }
        XCTAssertTrue(isVisibleAndHittable(accept, app: app), "Consent must remain reachable at the selected text size")
        assertFitsScreen(accept, app: app)
        XCTAssertGreaterThanOrEqual(accept.frame.height, 44)

        // These are the disclosed processors and privacy concepts, rather than
        // exact sentences or dialect capitalization that editors may change.
        let disclosure = consentLabels.joined(separator: " ").lowercased()
        XCTAssertTrue(disclosure.contains("firebase"))
        XCTAssertTrue(disclosure.contains("azure"))
        XCTAssertTrue(containsAny(disclosure, czech ? ["poznám"] : ["notes"]))
        XCTAssertTrue(containsAny(disclosure, czech ? ["vybran", "zvolen"] : ["select", "chosen"]))
        XCTAssertTrue(containsAny(disclosure, czech ? ["hesl", "přihlaš"] : ["password", "credential"]))
        if largeText { attachScreenshot(app, name: "AI consent \(language) large text") }
        accept.tap()

        let newChat = app.buttons["gradeyAINewChatButton"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 8))
        for _ in 0..<12 where !isVisibleAndHittable(newChat, app: app) {
            if newChat.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        if !isVisibleAndHittable(newChat, app: app) { attachScreenshot(app, name: "Unreachable new chat \(language)") }
        XCTAssertTrue(isVisibleAndHittable(newChat, app: app), "New chat frame: \(newChat.frame), app: \(app.frame), hittable: \(newChat.isHittable)")
        assertFitsScreen(newChat, app: app)
        newChat.tap()

        let composer = app.descendants(matching: .any)["gradeyAIComposer"].firstMatch
        let context = app.descendants(matching: .any)["gradeyAIContextStatus"].firstMatch
        let quota = app.descendants(matching: .any)["gradeyAIRemainingMessages"].firstMatch
        // SwiftUI exposes Menu as a button or pop-up button depending on the
        // current layout; the stable identifier is the cross-layout contract.
        var menu = app.descendants(matching: .any)["gradeyAIContextSelectionMenu"].firstMatch
        let send = app.buttons["gradeyAISendButton"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        for element in [context, quota, menu, send] { XCTAssertTrue(element.exists) }
        if largeText {
            let content = app.scrollViews["gradeyAIAccessibleContent"].firstMatch
            XCTAssertTrue(content.exists)
            var revealedMenu: XCUIElement?
            for _ in 0..<20 {
                let candidates = app.descendants(matching: .any)
                    .matching(identifier: "gradeyAIContextSelectionMenu").allElementsBoundByIndex
                if let visible = candidates.first(where: { $0.isHittable && content.frame.contains($0.frame) }) {
                    revealedMenu = visible
                    break
                }
                // A fast swipe can fling past a short control and recycle its
                // lazy container. Use short, slow drags toward its latest frame.
                let upward = candidates.first.map { $0.frame.midY >= content.frame.midY } ?? true
                let start = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.75 : 0.25))
                let end = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.35 : 0.65))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            if revealedMenu == nil { attachScreenshot(app, name: "Unreachable context selection \(language)") }
            menu = try XCTUnwrap(revealedMenu, "Context selection must remain reachable while content scrolls")
            XCTAssertTrue(content.frame.contains(menu.frame), "Context selection must be visible above the composer")
            XCTAssertLessThanOrEqual(content.frame.maxY, composer.frame.minY + 2, "Scrolling content must leave the composer accessible")
        }
        XCTAssertTrue(composer.isHittable, "The composer must be usable at large text sizes")
        XCTAssertFalse(send.isEnabled, "An empty draft must not start a generation")

        let contextCopy = readableLabels(in: context).joined(separator: " ").lowercased()
        XCTAssertTrue(containsAny(contextCopy, czech ? ["škol"] : ["school"]))
        XCTAssertTrue(containsAny(contextCopy, czech ? ["automaticky nepřikl"] : ["not attached automatically"]))
        XCTAssertTrue(contextCopy.contains("compute"), "The selected action must show its Compute cost")
        XCTAssertTrue(quota.label.lowercased().contains("compute"))
        XCTAssertNotNil(quota.label.range(of: #"\b3\b"#, options: .regularExpression))
        XCTAssertNotNil(quota.label.range(of: #"\b5\b"#, options: .regularExpression))
        XCTAssertTrue(containsAny(quota.label.lowercased(), czech ? ["zbýv"] : ["remain"]))

        let placeholder = composer.placeholderValue ?? composer.label
        XCTAssertFalse(placeholder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        assertReadableLabels([placeholder, menu.label, quota.label, send.label])
        for element in [composer, menu, quota, send] { assertFitsScreen(element, app: app) }
        XCTAssertLessThanOrEqual(composer.frame.maxX, send.frame.minX + 2, "Composer and send control must not overlap")
        if !largeText {
            XCTAssertLessThanOrEqual(context.frame.maxY, composer.frame.minY + 2, "Context must not cover the composer")
        }

        let ai = app.descendants(matching: .any)["gradeyAIView"].firstMatch
        assertReadableLabels(readableLabels(in: ai))
        assertVisibleTextFits(in: ai, app: app)
        attachScreenshot(app, name: "AI composer and Compute \(language)")

        // Opening this menu only inspects action labels; it does not send a
        // prompt or select data. The application is terminated by the defer.
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        assertReadableLabels(readableLabels(in: app))
    }

    private func containsAny(_ text: String, _ fragments: [String]) -> Bool {
        fragments.contains { text.contains($0) }
    }

    @MainActor
    private func readableLabels(in element: XCUIElement) -> [String] {
        let controls = element.staticTexts.allElementsBoundByIndex
            + element.buttons.allElementsBoundByIndex
            + element.textFields.allElementsBoundByIndex
            + element.textViews.allElementsBoundByIndex
        return controls.flatMap { control in
            [control.label, control.placeholderValue ?? ""]
        }.filter { !$0.isEmpty }
    }

    private func assertReadableLabels(_ labels: [String], file: StaticString = #filePath, line: UInt = #line) {
        for label in labels {
            XCTAssertNil(label.range(
                of: #"(?:^|\W)(?:gradey\.ai|detail\.simulator|detail\.intelligence|planner|action)\.[A-Za-z][A-Za-z0-9_.]*"#,
                options: .regularExpression
            ), "Unresolved localization: \(label)", file: file, line: line)
            XCTAssertNil(label.range(of: #"%(?:\d+\$)?(?:lld|ld|d|@|(?:\.\d+)?f)"#, options: .regularExpression),
                         "Unformatted localized value: \(label)", file: file, line: line)
        }
    }

    @MainActor
    private func isVisibleAndHittable(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        element.exists && element.isHittable && app.frame.insetBy(dx: -1, dy: -1).contains(element.frame)
    }

    @MainActor
    private func assertFitsScreen(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let frame = element.frame
        XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }, file: file, line: line)
        XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 2, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 2, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, app.frame.minY - 2, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, app.frame.maxY + 2, file: file, line: line)
    }

    @MainActor
    private func assertVisibleTextFits(in container: XCUIElement, app: XCUIApplication) {
        for text in container.staticTexts.allElementsBoundByIndex where text.frame.intersects(app.frame) {
            let frame = text.frame
            XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite })
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            // Vertical clipping is normal while scrolling a long disclosure.
            XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 2)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 2)
        }
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
