import XCTest

final class GradelyUITests: XCTestCase {
    private struct SettingsDestinationSpec {
        let rowIdentifier: String
        let detailIdentifier: String
    }

    private let settingsDestinations = [
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-account",
            detailIdentifier: "settingsDetail-account"
        ),
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-connectedServices",
            detailIdentifier: "settingsDetail-connectedServices"
        ),
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-notifications",
            detailIdentifier: "settingsDetail-notifications"
        ),
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-privacyData",
            detailIdentifier: "settingsDetail-privacyData"
        ),
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-appPreferences",
            detailIdentifier: "settingsDetail-appPreferences"
        ),
        SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-supportAbout",
            detailIdentifier: "settingsDetail-supportAbout"
        )
    ]

    private var signedInLaunchArguments: [String] {
        [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode"
        ]
    }

    private var upgradeGuestLaunchArguments: [String] {
        [
            "-uiTestingMockAPI",
            "-uiTestingShowUpgradeOnboarding",
            "-uiTestingLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut",
            "-uiTestingResetGuestMode"
        ]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewUserOnboardingRequiresGradeyIDAndPersistsCompletion() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingResetOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["onboardingProgressLabel"].exists)
        app.buttons["onboardingPrimaryButton"].tap()

        let appleButton = app.buttons["gradeyIDAppleButton"]
        XCTAssertTrue(appleButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onboardingProgressLabel"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "gradeyIDAppleButton").count, 1)
        XCTAssertFalse(app.buttons["gradeyIDBypassButton"].exists)
        XCTAssertFalse(app.buttons["gradeyIDMockSignInButton"].exists)
        appleButton.tap()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingBackButton"].exists)
        app.buttons["onboardingBackButton"].tap()
        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 5))
        app.buttons["gradeyIDAppleButton"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingRequiresGradeyID"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingPrimaryButton"].exists)
        app.buttons["demoAccountButton"].tap()
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.buttons["onboardingNotificationsNotNowButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingMealsNotNowButton"].exists)
        app.buttons["onboardingNotificationsNotNowButton"].tap()

        XCTAssertTrue(app.buttons["onboardingFinishButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingFinishButton"].tap()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        // The UI-test API uses an in-memory school session, so a process relaunch
        // returns to sign-in. The persisted contract under test is that onboarding
        // stays completed and does not appear again.
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingPrimaryButton"].exists)
    }

    @MainActor
    func testUpgradeOnboardingAllowsGuestAndShowsSupportOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowUpgradeOnboarding",
            "-uiTestingLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingLoginButton"].exists)
        app.buttons["onboardingPrimaryButton"].tap()

        XCTAssertTrue(app.buttons["gradeyIDBypassButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["schoolURLField"].exists)
        app.buttons["gradeyIDBypassButton"].tap()

        XCTAssertTrue(app.otherElements["onboardingSupportOptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingUpgradeFinishButton"].exists)
        app.buttons["onboardingUpgradeFinishButton"].tap()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = signedInLaunchArguments
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingUpgradeFinishButton"].exists)
    }

    @MainActor
    func testOnboardingVisualReferenceCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingResetOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        let continueButton = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "gradeyIDAppleButton").count, 1)
        XCTAssertFalse(app.buttons["gradeyIDMockSignInButton"].exists)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))

        let accountAttachment = XCTAttachment(screenshot: app.screenshot())
        accountAttachment.name = "onboarding-account"
        accountAttachment.lifetime = .keepAlways
        add(accountAttachment)

        app.buttons["gradeyIDAppleButton"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schoolContinueButton"].exists)
        XCTAssertFalse(app.textFields["usernameField"].exists)
        XCTAssertFalse(app.secureTextFields["passwordField"].exists)

        app.buttons["demoAccountButton"].tap()
        XCTAssertTrue(app.textFields["usernameField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["loginButton"].exists)
        XCTAssertFalse(app.textFields["schoolURLField"].exists)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))

        let credentialsAttachment = XCTAttachment(screenshot: app.screenshot())
        credentialsAttachment.name = "onboarding-school-credentials"
        credentialsAttachment.lifetime = .keepAlways
        add(credentialsAttachment)

        app.buttons["onboardingBackButton"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["usernameField"].exists)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

        let schoolAttachment = XCTAttachment(screenshot: app.screenshot())
        schoolAttachment.name = "onboarding-school-selection"
        schoolAttachment.lifetime = .keepAlways
        add(schoolAttachment)
    }

    @MainActor
    func testGuidedOnboardingCloudFailureKeepsLocalSchoolAndOffersRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingResetOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode",
            "-uiTestingSchoolCloudLinkFailure"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingPrimaryButton"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        app.buttons["demoAccountButton"].tap()
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.buttons["onboardingRetry-schoolCloudLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingFinishButton"].exists)
    }

    @MainActor
    func testGuidedOnboardingNotificationDenialDisablesNotifications() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingResetOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode",
            "-uiTestingNotificationsDenied"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingPrimaryButton"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        app.buttons["demoAccountButton"].tap()
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.buttons["onboardingNotificationsEnableButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingNotificationsEnableButton"].tap()

        XCTAssertTrue(app.buttons["onboardingFinishButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingOpenNotificationSettingsButton"].exists)
    }

    @MainActor
    func testUpgradeMigrationFailureKeepsLocalMealsSessionAndOffersRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowUpgradeOnboarding",
            "-uiTestingLoggedIn",
            "-uiTestingStravaCZLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode",
            "-uiTestingMealsCloudLinkFailure"
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["onboardingSupportOptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingRetry-mealsCloudLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingUpgradeFinishButton"].exists)
    }

    @MainActor
    func testGuidedOnboardingEduPageTwoFactorAndChildSelectionHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowOnboarding",
            "-uiTestingResetOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode",
            "-uiTestingEduPageTwoFactor",
            "-uiTestingEduPageChildSelection"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingPrimaryButton"].tap()

        let eduPageProvider = app.buttons["provider-eduPage"]
        XCTAssertTrue(eduPageProvider.waitForExistence(timeout: 5))
        eduPageProvider.tap()

        app.textFields["schoolURLField"].tap()
        app.textFields["schoolURLField"].typeText("demo")
        app.swipeUp()
        app.buttons["schoolContinueButton"].tap()
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usernameField.typeText("parent")
        app.swipeUp()
        let passwordField = app.secureTextFields["passwordField"].exists
            ? app.secureTextFields["passwordField"]
            : app.textFields["passwordField"]
        passwordField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        passwordField.typeText("secret")
        app.buttons["loginButton"].tap()

        let twoFactorCode = app.secureTextFields["eduPageTwoFactorCode"]
        XCTAssertTrue(twoFactorCode.waitForExistence(timeout: 5))
        twoFactorCode.tap()
        twoFactorCode.typeText("123456")
        app.buttons["eduPageTwoFactorSubmit"].tap()

        let student = app.buttons["eduPageStudent-Student1"]
        XCTAssertTrue(student.waitForExistence(timeout: 5))
        student.tap()

        XCTAssertTrue(app.buttons["onboardingNotificationsEnableButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProductionSchoolConnectionIsTwoDistinctScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI"]
        app.launch()

        XCTAssertTrue(app.textFields["schoolSearchField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["schoolURLField"].exists)
        XCTAssertTrue(app.buttons["schoolContinueButton"].exists)
        XCTAssertFalse(app.textFields["usernameField"].exists)
        XCTAssertFalse(app.secureTextFields["passwordField"].exists)

        let schoolAttachment = XCTAttachment(screenshot: app.screenshot())
        schoolAttachment.name = "Production school selection"
        schoolAttachment.lifetime = .keepAlways
        add(schoolAttachment)

        app.buttons["demoAccountButton"].tap()
        XCTAssertTrue(app.textFields["usernameField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["loginButton"].exists)
        XCTAssertTrue(app.buttons["loginBackButton"].exists)
        XCTAssertFalse(app.textFields["schoolSearchField"].exists)
        XCTAssertFalse(app.textFields["schoolURLField"].exists)

        let credentialsAttachment = XCTAttachment(screenshot: app.screenshot())
        credentialsAttachment.name = "Production school credentials"
        credentialsAttachment.lifetime = .keepAlways
        add(credentialsAttachment)

        app.buttons["loginBackButton"].tap()
        XCTAssertTrue(app.textFields["schoolSearchField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["usernameField"].exists)
    }

    @MainActor
    func testMockLoginCanSelectSchoolFromDirectory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI"]
        app.launch()

        XCTAssertTrue(app.textFields["schoolSearchField"].waitForExistence(timeout: 5))
        app.textFields["schoolSearchField"].tap()
        app.textFields["schoolSearchField"].typeText("demo")

        let schoolResult = app.buttons["schoolResult-demo"]
        XCTAssertTrue(schoolResult.waitForExistence(timeout: 5))
        schoolResult.tap()

        if app.textFields["usernameField"].waitForExistence(timeout: 2) {
            XCTAssertTrue(app.descendants(matching: .any)["selectedSchoolSummary"].exists)
            XCTAssertFalse(app.textFields["schoolURLField"].exists)
        } else {
            let schoolURLField = app.textFields["schoolURLField"]
            XCTAssertTrue(schoolURLField.exists)
            XCTAssertEqual(schoolURLField.value as? String, "https://demo.bakalari.cz")
        }
    }

    @MainActor
    func testBroadSchoolSearchShowsTheFullResultSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingBroadSchoolSearch"]
        app.launch()

        let searchField = app.textFields["schoolSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("soukroma")
        searchField.typeText("\n")

        let resultButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "schoolResult-")
        )
        XCTAssertEqual(resultButtons.count, 8)

        let resultsScroll = app.scrollViews["schoolSearchResults"]
        XCTAssertTrue(resultsScroll.exists)
        XCTAssertTrue(app.buttons["schoolResult-private-opava-business"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Broad school search results"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMockLoginSubjectsDetailAndCalculatorFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI"]
        app.launch()

        XCTAssertTrue(app.buttons["demoAccountButton"].waitForExistence(timeout: 5))
        app.buttons["demoAccountButton"].tap()
        XCTAssertTrue(app.buttons["loginButton"].waitForExistence(timeout: 2))
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.scrollViews["subjectsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["subjectRow-math"].exists)

        app.descendants(matching: .any)["subjectRow-math"].tap()

        XCTAssertTrue(app.textFields["theoreticalMarkField"].waitForExistence(timeout: 5))
        app.textFields["theoreticalMarkField"].tap()
        app.textFields["theoreticalMarkField"].typeText("3")

        XCTAssertTrue(app.descendants(matching: .any)["theoreticalResultPanel"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMockLaunchWithSavedSessionShowsSubjects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.scrollViews["subjectsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["subjectRow-math"].exists)
    }

    @MainActor
    func testTimetableTabShowsWeekAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        // Starts on the Today tab.
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))

        // Switch to the Timetable tab (fourth tab).
        app.tabBars.buttons.element(boundBy: 3).tap()

        XCTAssertTrue(app.scrollViews["timetableList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weekNext"].exists)
        XCTAssertTrue(app.buttons["dayChip-1"].exists)

        // Moving off the current week reveals the "Today" shortcut; tapping it returns.
        app.buttons["weekNext"].tap()
        XCTAssertTrue(app.buttons["weekToday"].waitForExistence(timeout: 5))
        app.buttons["weekToday"].tap()
        XCTAssertTrue(app.scrollViews["timetableList"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSupportTipFlowUsesMockPurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-supportAbout",
                detailIdentifier: "settingsDetail-supportAbout"
            ),
            in: app
        )

        let settingsScroll = settingsDetailScrollView(in: app)
        let chatButton = app.buttons["supportChatButton"]
        scroll(settingsScroll, untilExists: chatButton)
        XCTAssertTrue(chatButton.waitForExistence(timeout: 3))

        let supportButton = waitForAny([
            app.buttons["supportGradelyButton"],
            app.buttons["Support Gradey"],
            app.buttons["Podpořit Gradey"]
        ])
        scroll(settingsScroll, untilExists: supportButton)
        XCTAssertTrue(supportButton.waitForExistence(timeout: 3))
        supportButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["supportPlan-standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["supportPlan-plus"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["supportPlanIntervalPicker"].exists)

        let supportScroll = app.scrollViews["supportTipsScreen"]
        let smallTip = app.buttons["supportTip-tip_small"]
        let mediumTip = app.buttons["supportTip-tip_medium"]
        let largeTip = app.buttons["supportTip-tip_large"]
        scroll(supportScroll, untilExists: smallTip)

        XCTAssertTrue(smallTip.waitForExistence(timeout: 5))
        XCTAssertTrue(mediumTip.exists)
        XCTAssertTrue(largeTip.exists)

        smallTip.tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsThankYou"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSupportSubscriptionFlowUsesMockPurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-supportAbout",
                detailIdentifier: "settingsDetail-supportAbout"
            ),
            in: app
        )

        let settingsScroll = settingsDetailScrollView(in: app)
        let supportButton = waitForAny([
            app.buttons["supportGradelyButton"],
            app.buttons["Support Gradey"],
            app.buttons["Podpořit Gradey"]
        ])
        scroll(settingsScroll, untilExists: supportButton)
        XCTAssertTrue(supportButton.waitForExistence(timeout: 3))
        supportButton.tap()

        XCTAssertTrue(app.buttons["supportPlan-standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["supportRestorePurchasesButton"].exists)
        app.buttons["supportPlan-standard"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsThankYou"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDebugModeShowsIdentityAndRestartsNewUserOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + ["-gradeyDebugMode"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-supportAbout",
                detailIdentifier: "settingsDetail-supportAbout"
            ),
            in: app
        )

        let settingsScroll = settingsDetailScrollView(in: app)
        let supabaseRow = app.descendants(matching: .any)["debugSupabaseID"]
        let revenueCatRow = app.descendants(matching: .any)["debugRevenueCatID"]
        scroll(settingsScroll, untilExists: supabaseRow)
        XCTAssertTrue(supabaseRow.waitForExistence(timeout: 5))
        XCTAssertTrue(revenueCatRow.exists)

        let restartButton = app.buttons["debugRestartNewUserButton"]
        scroll(settingsScroll, untilHittable: restartButton)
        XCTAssertTrue(restartButton.waitForExistence(timeout: 3))
        restartButton.tap()

        let confirm = waitForAny([
            app.buttons["debugRestartConfirmButton"],
            app.buttons["Restart"],
            app.buttons["Restartovat"]
        ])
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["onboardingStep-welcome"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSupportAndCreditsVisualReferenceCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-supportAbout",
                detailIdentifier: "settingsDetail-supportAbout"
            ),
            in: app
        )

        let settingsScroll = settingsDetailScrollView(in: app)
        let chatButton = app.buttons["supportChatButton"]
        scroll(settingsScroll, untilHittable: chatButton)
        XCTAssertTrue(chatButton.waitForExistence(timeout: 3))
        XCTAssertTrue(chatButton.isHittable)

        let supportButton = app.buttons["supportGradelyButton"]
        scroll(settingsScroll, untilHittable: supportButton)
        XCTAssertTrue(supportButton.isHittable)
        supportButton.tap()

        XCTAssertTrue(app.scrollViews["supportTipsScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["supportTipsHeader"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["supportTipsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modalDismissButton"].isHittable)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        let supportAttachment = XCTAttachment(screenshot: app.screenshot())
        supportAttachment.name = "settings-style-support"
        supportAttachment.lifetime = .keepAlways
        add(supportAttachment)

        app.buttons["modalDismissButton"].tap()
        XCTAssertTrue(app.scrollViews["supportTipsScreen"].waitForNonExistence(timeout: 5))

        let creditsButton = app.buttons["settingsCreditsButton"]
        scroll(settingsScroll, untilHittable: creditsButton)
        XCTAssertTrue(creditsButton.isHittable)
        creditsButton.tap()

        XCTAssertTrue(app.scrollViews["creditsScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["creditsOpenSideLink"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["creditsTeam"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["creditsEduPageAttribution"].exists)
        XCTAssertTrue(app.buttons["modalDismissButton"].isHittable)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
        let creditsAttachment = XCTAttachment(screenshot: app.screenshot())
        creditsAttachment.name = "settings-style-credits"
        creditsAttachment.lifetime = .keepAlways
        add(creditsAttachment)
    }

    @MainActor
    func testStravaCZConnectOrderCancelAndGlobalLogoutClearsSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        restoreMealsTabIfNeeded(in: app)

        app.tabBars.buttons.element(boundBy: 4).tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZConnectView"].waitForExistence(timeout: 5))

        app.textFields["stravaCZCanteenField"].tap()
        app.textFields["stravaCZCanteenField"].typeText("1234")

        app.textFields["stravaCZUsernameField"].tap()
        app.textFields["stravaCZUsernameField"].typeText("student")

        let passwordField = app.secureTextFields["stravaCZPasswordField"].exists
            ? app.secureTextFields["stravaCZPasswordField"]
            : app.textFields["stravaCZPasswordField"]
        passwordField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        passwordField.typeText("secret")

        app.buttons["stravaCZConnectButton"].tap()

        XCTAssertTrue(app.collectionViews["stravaCZMenuList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["stravaCZBalance"].waitForExistence(timeout: 5))

        let orderButton = app.descendants(matching: .any)["stravaCZOrderButton-1"]
        if !orderButton.waitForExistence(timeout: 2) {
            app.collectionViews["stravaCZMenuList"].swipeUp()
        }
        XCTAssertTrue(orderButton.waitForExistence(timeout: 5))
        orderButton.tap()

        let cancelButton = app.descendants(matching: .any)["stravaCZCancelButton-1"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZOrderButton-1"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 0).tap()
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-account",
                detailIdentifier: "settingsDetail-account"
            ),
            in: app
        )

        let settingsScroll = settingsDetailScrollView(in: app)
        let logoutButton = waitForAny([
            app.buttons["accountSignOutButton"],
            app.buttons["logoutButton"],
            app.buttons["Log out"],
            app.buttons["Odhlásit se"]
        ])
        scroll(settingsScroll, untilExists: logoutButton)
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 3))
        logoutButton.tap()

        let confirmLogout = waitForAny([
            app.buttons["accountSignOutConfirmButton"],
            app.buttons["Log out"],
            app.buttons["Odhlásit se"],
            app.descendants(matching: .any)["accountSignOutConfirmButton"]
        ])
        XCTAssertTrue(confirmLogout.waitForExistence(timeout: 3))
        confirmLogout.tap()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        app.buttons["demoAccountButton"].tap()
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 4).tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZConnectView"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReleaseGuestActionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        let guestSetupArguments = [
            "-uiTestingMockAPI",
            "-uiTestingShowUpgradeOnboarding",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut",
            "-uiTestingResetGuestMode"
        ]
        app.launchArguments = guestSetupArguments
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = [
                "-uiTestingMockAPI",
                "-uiTestingRequiresGradeyID",
                "-uiTestingGradeyIDSignedOut",
                "-uiTestingResetGuestMode"
            ]
            app.launch()
            _ = app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 3)
                || app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 3)
            app.terminate()
        }

        completeUpgradeAsGuest(in: app, expectsToday: false)
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["gradeyIDEmailField"].exists)
        XCTAssertFalse(app.buttons["gradeyIDMagicLinkButton"].exists)

        app.terminate()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingRequiresGradeyID",
            "-uiTestingGradeyIDSignedOut"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gradeyIDAppleButton"].exists)
        XCTAssertFalse(app.buttons["gradeyIDBypassButton"].exists)
    }

    @MainActor
    func testGradeyAIToolbarEntryPresentsAndAcceptsConsent() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingGradeyAIConsentRequired"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        let aiButton = app.buttons["gradeyAIButton"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 3))
        aiButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIConsentView"].waitForExistence(timeout: 5))
        let consentButton = app.buttons["gradeyAIConsentButton"]
        XCTAssertTrue(consentButton.waitForExistence(timeout: 3))
        consentButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIEmptyConversations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gradeyAINewChatButton"].exists)
    }

    @MainActor
    func testGradeyAIDisabledStillShowsConsentAndChatShell() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingGradeyAIConsentRequired",
            "-uiTestingGradeyAIDisabled"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        let aiButton = app.buttons["gradeyAIButton"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 3))
        aiButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIConsentView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIServiceUnavailableBanner"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gradeyAIUnavailable"].exists)

        let consentButton = app.buttons["gradeyAIConsentButton"]
        XCTAssertTrue(consentButton.waitForExistence(timeout: 3))
        consentButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIEmptyConversations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIContextStatus"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIRemainingMessages"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIServiceUnavailableBanner"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gradeyAIUnavailable"].exists)

        let newChatButton = app.buttons["gradeyAINewChatButton"]
        XCTAssertTrue(newChatButton.exists)
        XCTAssertFalse(newChatButton.isEnabled)
    }

    @MainActor
    func testGuestOpeningGradeyAIShowsLoginInsteadOfErrorAlert() throws {
        let app = XCUIApplication()
        app.launchArguments = upgradeGuestLaunchArguments
        app.launch()
        completeUpgradeAsGuest(in: app)

        let aiButton = app.buttons["gradeyAIButton"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 3))
        aiButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gradeyAISignInView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].exists)
        XCTAssertFalse(app.buttons["gradeyIDBypassButton"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["gradeyAIView"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gradeyAIUnavailable"].exists)

        app.buttons["gradeyIDAppleButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["gradeyAIView"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["gradeyAISignInView"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testGradeyAIMockStreamUpdatesReplyAndQuota() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingGradeyAIQuota"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        let aiButton = app.buttons["gradeyAIButton"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 3))
        aiButton.tap()

        let quota = app.descendants(matching: .any)["gradeyAIRemainingMessages"]
        XCTAssertTrue(quota.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(quota, containingAny: ["3 of 5", "3 z 5"]))
        XCTAssertTrue(quota.label.contains("Resets") || quota.label.contains("Obnoví se"))

        let newChatButton = app.buttons["gradeyAINewChatButton"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 3))
        newChatButton.tap()

        let composer = app.descendants(matching: .any)["gradeyAIComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("How should I study for maths?")
        app.buttons["gradeyAISendButton"].tap()

        let mockReply = "I can help you understand your marks and plan around your timetable."
        XCTAssertTrue(app.staticTexts[mockReply].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(quota, containingAny: ["2 of 5", "2 z 5"]))
    }

    @MainActor
    func testSettingsSignedInOverviewNavigatesEveryDestinationAndModalDoneDismisses() throws {
        let app = launchSignedInApp()

        openSettings(in: app)
        let doneButton = app.buttons["settingsDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        let profileCard = app.descendants(matching: .any)["settingsDestination-account"]
        XCTAssertTrue(profileCard.label.contains("Preview Student"))
        XCTAssertTrue(profileCard.label.contains("Gradey ID"))
        XCTAssertFalse(app.staticTexts["student@example.com"].exists)

        for destination in settingsDestinations {
            openSettingsDestination(destination, in: app)
            if app.frame.width <= 700 {
                XCTAssertTrue(app.buttons["settingsBackButton"].waitForExistence(timeout: 3))
                XCTAssertFalse(app.buttons["settingsDoneButton"].exists)
            }
            if destination.rowIdentifier == "settingsDestination-account" {
                XCTAssertTrue(app.staticTexts["student@example.com"].waitForExistence(timeout: 3))
            }
            navigateBackToSettingsOverview(in: app)
        }

        doneButton.tap()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsMissingNameProfileFocusesEditorAndPropagatesSavedName() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + ["-uiTestingMissingGradeyName"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)

        let profileCard = app.descendants(matching: .any)["settingsDestination-account"]
        XCTAssertTrue(profileCard.label.contains("Add your name"))
        XCTAssertTrue(profileCard.label.contains("Personalize your Gradely profile"))
        XCTAssertFalse(app.staticTexts["student@example.com"].exists)

        openSettingsDestination(settingsDestinations[0], in: app)
        let nameField = app.textFields["accountFullNameField"]
        let saveButton = app.buttons["accountFullNameSaveButton"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        XCTAssertTrue(nameField.isHittable)
        XCTAssertFalse(saveButton.isEnabled)

        nameField.tap()
        nameField.typeText("  Žofie Nováková  ")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Žofie Nováková"].waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled)
        navigateBackToSettingsOverview(in: app)
        XCTAssertTrue(
            waitForLabel(
                app.descendants(matching: .any)["settingsDestination-account"],
                containingAny: ["Žofie Nováková"]
            )
        )
    }

    @MainActor
    func testSettingsNameSaveFailureKeepsDraftAndShowsInlineError() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-uiTestingMissingGradeyName",
            "-uiTestingGradeyNameUpdateFailure"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openSettingsDestination(settingsDestinations[0], in: app)

        let nameField = app.textFields["accountFullNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Žofie Nováková")

        let saveButton = app.buttons["accountFullNameSaveButton"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["accountFullNameSaveError"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(nameField.value as? String, "Žofie Nováková")
        XCTAssertTrue(saveButton.isEnabled)
    }

    @MainActor
    func testSettingsVisualReferenceCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-uiTestingLinkedAccounts",
            "-uiTestingQuietHoursEnabled"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        openSettings(in: app)
        XCTAssertTrue(app.buttons["settingsDoneButton"].waitForExistence(timeout: 5))

        if app.frame.width > 700 {
            XCTAssertTrue(
                app.descendants(matching: .any)["settingsDetail-account"]
                    .waitForExistence(timeout: 5)
            )
        }

        // Accessibility can become available a frame before the full-screen
        // split-view presentation finishes compositing on iPad.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-overview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testGradeySessionWithoutSchoolUsesOnboardingNotSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingBackButton"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settingsDoneButton"].exists)
        XCTAssertFalse(app.scrollViews["accountHubScroll"].exists)

        app.buttons["onboardingBackButton"].tap()
        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gradeyIDBypassButton"].exists)
        XCTAssertFalse(app.scrollViews["accountHubScroll"].exists)
    }

    @MainActor
    func testSettingsGuestKeepsUnavailableNotificationControlsVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = upgradeGuestLaunchArguments
        app.launch()
        completeUpgradeAsGuest(in: app)

        openSettings(in: app)
        let guestProfile = app.descendants(matching: .any)["settingsDestination-account"]
        XCTAssertFalse(guestProfile.label.contains("Add your name"))
        openSettingsDestination(settingsDestinations[0], in: app)
        XCTAssertFalse(app.textFields["accountFullNameField"].exists)
        navigateBackToSettingsOverview(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-notifications",
                detailIdentifier: "settingsDetail-notifications"
            ),
            in: app
        )

        let detail = settingsDetailScrollView(in: app)
        let notificationsToggle = app.descendants(matching: .any)["newMarkNotificationsToggle"]
        let privacyPicker = app.descendants(matching: .any)["lockScreenDetailPicker"]
        let quietHoursToggle = app.descendants(matching: .any)["quietHoursToggle"]
        for control in [notificationsToggle, privacyPicker, quietHoursToggle] {
            scroll(detail, untilExists: control)
            XCTAssertTrue(control.exists)
            XCTAssertFalse(control.isEnabled)
        }

        let explanation = waitForAny([
            app.staticTexts["settingsNotificationsUnavailableExplanation"],
            app.descendants(matching: .any)["settingsNotificationsUnavailableExplanation"],
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Gradey ID")).firstMatch,
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "účet Gradey")).firstMatch
        ])
        scroll(detail, untilExists: explanation)
        XCTAssertTrue(explanation.exists)
    }

    @MainActor
    func testSettingsGlobalSignOutRequiresConfirmation() throws {
        let app = launchSignedInApp()
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-account",
                detailIdentifier: "settingsDetail-account"
            ),
            in: app
        )

        let detail = settingsDetailScrollView(in: app)
        let signOut = app.buttons["accountSignOutButton"]
        scroll(detail, untilHittable: signOut)
        XCTAssertTrue(signOut.exists)
        signOut.tap()

        let cancel = waitForAny([
            app.buttons.matching(identifier: "accountSignOutCancelButton").firstMatch,
            app.buttons["Cancel"],
            app.buttons["Zrušit"]
        ])
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settingsDetail-account"].exists)
        cancel.tap()

        signOut.tap()
        let confirm = waitForAny([
            app.buttons.matching(identifier: "accountSignOutConfirmButton").firstMatch,
            app.buttons["Log out"],
            app.buttons["Odhlásit se"],
            app.descendants(matching: .any)
                .matching(identifier: "accountSignOutConfirmButton")
                .firstMatch
        ])
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsDeleteAccountRequiresTwoDestructiveConfirmations() throws {
        let app = launchSignedInApp()
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-privacyData",
                detailIdentifier: "settingsDetail-privacyData"
            ),
            in: app
        )

        let detail = settingsDetailScrollView(in: app)
        let exportButton = app.buttons["accountExportButton"]
        scroll(detail, untilHittable: exportButton)
        XCTAssertTrue(exportButton.isHittable)

        let deleteButton = waitForAny([
            app.buttons["accountDeleteButton"],
            app.buttons["deleteGradeyAccountButton"],
            app.descendants(matching: .any)["accountDeleteButton"]
        ])
        scroll(detail, untilHittable: deleteButton)
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        let firstConfirmation = waitForAny([
            app.buttons.matching(identifier: "accountDeleteFirstConfirmButton").firstMatch,
            app.buttons["Continue"],
            app.buttons["Pokračovat"],
            app.descendants(matching: .any)
                .matching(identifier: "accountDeleteFirstConfirmButton")
                .firstMatch
        ])
        XCTAssertTrue(firstConfirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settingsDetail-privacyData"].exists)
        firstConfirmation.tap()

        let finalConfirmation = waitForAny([
            app.buttons.matching(identifier: "accountDeleteFinalConfirmButton").firstMatch,
            app.buttons["Delete account"],
            app.buttons["Smazat účet"],
            app.descendants(matching: .any)
                .matching(identifier: "accountDeleteFinalConfirmButton")
                .firstMatch
        ])
        XCTAssertTrue(finalConfirmation.waitForExistence(timeout: 3))
        finalConfirmation.tap()

        XCTAssertTrue(app.buttons["gradeyIDAppleButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsMealsTabCanBeRemovedImmediatelyAndStaysHiddenAfterRelaunch() throws {
        let app = launchSignedInApp()
        restoreMealsTabIfNeeded(in: app)
        defer { restoreMealsTabIfNeeded(in: app) }

        let mealsTab = mealsTabButton(in: app)
        XCTAssertTrue(mealsTab.waitForExistence(timeout: 3))
        mealsTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["stravaCZConnectView"].waitForExistence(timeout: 5)
                || app.collectionViews["stravaCZMenuList"].exists
        )

        // Settings must be reachable from Meals, not only from the academic tabs.
        openSettings(in: app, waitsForToday: false)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-appPreferences",
                detailIdentifier: "settingsDetail-appPreferences"
            ),
            in: app
        )
        let toggle = app.descendants(matching: .any)["showMealsTabToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        scroll(
            app.descendants(matching: .any)["settingsDetail-appPreferences"],
            untilHittable: toggle
        )
        XCTAssertTrue(isSwitchOn(toggle))
        toggle.tap()

        // Removing the currently selected Meals tab also removes the view that
        // presented Settings, so the sheet closes as the app returns to Today.
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        XCTAssertFalse(mealsTabButton(in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["todayLunchCard"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        XCTAssertFalse(mealsTabButton(in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["todayLunchCard"].exists)
    }

    @MainActor
    func testSettingsLanguagePickerExposesChronicallyOnlineOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments
        app.launch()

        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-appPreferences",
                detailIdentifier: "settingsDetail-appPreferences"
            ),
            in: app
        )

        XCTAssertTrue(app.descendants(matching: .any)["appLanguageOptions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["appLanguageOption-english"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["appLanguageOption-czech"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chronicallyOnlineToggle"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appLanguageOption-englishChronicallyOnline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appLanguageOption-czechChronicallyOnline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appLanguageOption-system"].exists)
    }

    @MainActor
    func testChronicallyOnlineEnglishUsesLowercaseTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-settings.appLanguage",
            "englishChronicallyOnline"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        let todayTab = waitForAny([
            app.tabBars.buttons["today"],
            app.tabBars.buttons["Today"]
        ])
        XCTAssertTrue(todayTab.waitForExistence(timeout: 3))
        XCTAssertEqual(todayTab.label.lowercased(), "today")
    }

    @MainActor
    func testSettingsCzechLocalizationKeepsOverviewAndDetailsNavigable() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-AppleLanguages", "(cs)",
            "-AppleLocale", "cs_CZ"
        ]
        app.launch()

        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Nastavení"].exists || app.staticTexts["Nastavení"].exists)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-supportAbout",
                detailIdentifier: "settingsDetail-supportAbout"
            ),
            in: app
        )
        XCTAssertTrue(app.descendants(matching: .any)["settingsDetail-supportAbout"].exists)
    }

    @MainActor
    func testSettingsLargestAccessibilityTextKeepsLastDestinationReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        openSettings(in: app)
        let destination = SettingsDestinationSpec(
            rowIdentifier: "settingsDestination-supportAbout",
            detailIdentifier: "settingsDetail-supportAbout"
        )
        let row = app.descendants(matching: .any)[destination.rowIdentifier]
        scroll(settingsOverview(in: app), untilHittable: row, attempts: 10)
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)[destination.detailIdentifier].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsConnectedServicesEmptyStateHasSinglePrimaryLinkActions() throws {
        let app = launchSignedInApp()
        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-connectedServices",
                detailIdentifier: "settingsDetail-connectedServices"
            ),
            in: app
        )

        XCTAssertTrue(app.buttons["accountLinkSchoolButton"].exists)
        XCTAssertTrue(app.buttons["accountLinkStravaCZButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["linkedAccountsEmptyState"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["accountEmptyLinkSchoolButton"].exists)
        XCTAssertTrue(app.buttons["settingsBackButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testGradeyAccountHubShowsPersistentSchoolCloudLinkRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingSchoolCloudLinkFailure",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        let settingsButton = waitForAny([
            app.buttons["openAccountHubButton"],
            app.buttons["accountMenuButton"]
        ])
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-connectedServices",
                detailIdentifier: "settingsDetail-connectedServices"
            ),
            in: app
        )
        let settingsScroll = settingsDetailScrollView(in: app)
        let retry = app.buttons["accountRetry-schoolCloudLink"]
        scroll(settingsScroll, untilExists: retry)
        XCTAssertTrue(retry.exists)
    }

    @MainActor
    func testTodayShowsActionRequiredNoticeBeforeOpeningPrefilledReconnect() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-uiTestingLinkedAccounts",
            "-uiTestingLinkedAccountActionRequired"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["todaySchoolConnectionNotice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["todaySchoolReconnectSheet"].exists)
        XCTAssertFalse(app.textFields["usernameField"].exists)

        let reconnectButton = app.buttons["todaySchoolReconnectButton"]
        XCTAssertTrue(reconnectButton.exists)
        reconnectButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["todaySchoolReconnectSheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selectedSchoolSummary"].exists)
        XCTAssertEqual(app.textFields["usernameField"].value as? String, "apple-review")
        XCTAssertFalse(app.textFields["schoolURLField"].exists)

        app.buttons["selectedSchoolSummary"].tap()
        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schoolURLField"].value as? String, "https://demo.bakalari.cz/")
    }

    @MainActor
    func testSettingsOfflineRefreshKeepsCachedLinkedAccountVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + [
            "-uiTestingLinkedAccounts",
            "-uiTestingAccountSettingsOffline"
        ]
        app.launch()

        openSettings(in: app)
        let savedStatus = app.descendants(matching: .any)["settingsProfileSyncStatus"]
        XCTAssertTrue(savedStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(savedStatus, containingAny: ["Saved data", "Uložená data"]))
        XCTAssertFalse(app.alerts.firstMatch.exists)

        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-connectedServices",
                detailIdentifier: "settingsDetail-connectedServices"
            ),
            in: app
        )
        let row = app.descendants(matching: .any)["linkedAccountRow-preview-school"]
        scroll(settingsDetailScrollView(in: app), untilHittable: row)
        XCTAssertTrue(row.exists)
    }

    @MainActor
    func testSettingsSignOutThenSignInRestoresSchoolAndReturnsToToday() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + ["-uiTestingLinkedAccounts"]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.scrollViews["subjectsList"].waitForExistence(timeout: 5))
        openSettings(in: app, waitsForToday: false)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-account",
                detailIdentifier: "settingsDetail-account"
            ),
            in: app
        )

        let signOut = app.buttons["accountSignOutButton"]
        scroll(settingsDetailScrollView(in: app), untilHittable: signOut)
        signOut.tap()
        let confirm = waitForAny([
            app.buttons.matching(identifier: "accountSignOutConfirmButton").firstMatch,
            app.buttons["Log out"],
            app.buttons["Odhlásit se"]
        ])
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let mockSignIn = app.buttons["gradeyIDAppleButton"]
        XCTAssertTrue(mockSignIn.waitForExistence(timeout: 5))
        mockSignIn.tap()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 8))
        XCTAssertFalse(settingsOverview(in: app).exists)
    }

    @MainActor
    func testOfflineAccountSettingsStillOpensTodayFromCachedSchool() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingRequiresGradeyID",
            "-uiTestingResetGuestMode",
            "-uiTestingLinkedAccounts",
            "-uiTestingAccountSettingsOffline"
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.scrollViews["accountHubScroll"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testGradeyAccountNotificationToggleDisablesLockScreenPicker() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + ["-uiTestingLinkedAccounts"]
        app.launch()

        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-notifications",
                detailIdentifier: "settingsDetail-notifications"
            ),
            in: app
        )
        let scrollView = settingsDetailScrollView(in: app)

        let toggle = waitForAny([
            app.switches["newMarkNotificationsToggle"],
            app.descendants(matching: .any)["newMarkNotificationsToggle"]
        ])
        let picker = waitForAny([
            app.segmentedControls["lockScreenDetailPicker"],
            app.descendants(matching: .any)["lockScreenDetailPicker"]
        ])

        scroll(scrollView, untilHittable: toggle)
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(picker.exists)
        XCTAssertTrue(picker.isEnabled)

        toggle.tap()

        XCTAssertFalse(picker.isEnabled)
        XCTAssertTrue(app.staticTexts["lockScreenDetailSummary"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsLinkedSchoolCanTogglePerAccountMarkAlerts() throws {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments + ["-uiTestingLinkedAccounts"]
        app.launch()

        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-connectedServices",
                detailIdentifier: "settingsDetail-connectedServices"
            ),
            in: app
        )

        let toggle = app.descendants(matching: .any)["linkedAccountNotificationsToggle-preview-school"]
        scroll(settingsDetailScrollView(in: app), untilHittable: toggle)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(toggle.isEnabled)

        let originalValue = isSwitchOn(toggle)
        toggle.tap()
        XCTAssertTrue(waitForSwitch(toggle, toEqual: !originalValue))

        // Leave the shared UI-test fixture in its initial state.
        toggle.tap()
        XCTAssertTrue(waitForSwitch(toggle, toEqual: originalValue))
    }

    @MainActor
    func testGradeyAccountUnlinkRequiresConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingMockAPI",
            "-uiTestingLoggedIn",
            "-uiTestingRequiresGradeyID",
            "-uiTestingLinkedAccounts",
            "-uiTestingResetGuestMode"
        ]
        app.launch()

        openSettings(in: app)
        openSettingsDestination(
            SettingsDestinationSpec(
                rowIdentifier: "settingsDestination-connectedServices",
                detailIdentifier: "settingsDetail-connectedServices"
            ),
            in: app
        )

        let row = app.descendants(matching: .any)["linkedAccountRow-preview-school"]
        scroll(settingsDetailScrollView(in: app), untilHittable: row)
        XCTAssertTrue(row.isHittable)

        let unlinkAction = waitForAny([
            app.buttons["linkedAccountUnlinkAction-preview-school"],
            app.buttons["Unlink"],
            app.buttons["Odpojit"],
            app.descendants(matching: .any)["linkedAccountUnlinkAction-preview-school"]
        ])
        scroll(settingsDetailScrollView(in: app), untilHittable: unlinkAction)
        XCTAssertTrue(unlinkAction.isHittable)
        unlinkAction.tap()

        let confirmButton = waitForAny([
            app.buttons.matching(identifier: "accountUnlinkConfirmButton").firstMatch,
            app.buttons["Unlink account"],
            app.buttons["Odpojit účet"],
            app.descendants(matching: .any)
                .matching(identifier: "accountUnlinkConfirmButton")
                .firstMatch
        ])
        XCTAssertTrue(confirmButton.exists)
        XCTAssertTrue(row.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTestingMockAPI"]
            app.launch()
        }
    }

    @MainActor
    private func launchSignedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = signedInLaunchArguments
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func completeUpgradeAsGuest(in app: XCUIApplication, expectsToday: Bool = true) {
        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingPrimaryButton"].tap()

        let guestButton = app.buttons["gradeyIDBypassButton"]
        XCTAssertTrue(guestButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            guestButton.label.contains("Continue without")
                || guestButton.label.contains("Pokračovat bez")
                || guestButton.label.contains("without an account")
                || guestButton.label.contains("bez účtu")
        )
        guestButton.tap()

        XCTAssertTrue(app.buttons["onboardingUpgradeFinishButton"].waitForExistence(timeout: 5))
        app.buttons["onboardingUpgradeFinishButton"].tap()
        if expectsToday {
            XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func openSettings(in app: XCUIApplication, waitsForToday: Bool = true) {
        if waitsForToday {
            XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 5))
        }

        let settingsButton = waitForAny([
            app.buttons["openAccountHubButton"],
            app.buttons["accountMenuButton"]
        ])
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(settingsOverview(in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    private func openSettingsDestination(
        _ destination: SettingsDestinationSpec,
        in app: XCUIApplication
    ) {
        let overview = settingsOverview(in: app)
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any)[destination.rowIdentifier]
        scroll(overview, untilHittable: row, attempts: 8)
        XCTAssertTrue(row.isHittable, "Could not reach settings row: \(destination.rowIdentifier)")
        row.tap()

        let detail = app.descendants(matching: .any)[destination.detailIdentifier]
        XCTAssertTrue(
            detail.waitForExistence(timeout: 5),
            "Settings destination did not open: \(destination.detailIdentifier)"
        )
    }

    @MainActor
    private func navigateBackToSettingsOverview(in app: XCUIApplication) {
        let backButton = waitForAny([
            app.buttons["settingsBackButton"],
            app.navigationBars.buttons["Settings"],
            app.navigationBars.buttons["Nastavení"],
            app.navigationBars.buttons["Account & Settings"],
            app.navigationBars.buttons["Účet a nastavení"],
            app.navigationBars.buttons.element(boundBy: 0)
        ])
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
        XCTAssertTrue(settingsOverview(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func dismissSettings(in app: XCUIApplication) {
        var doneButton = app.buttons["settingsDoneButton"]
        if !doneButton.waitForExistence(timeout: 1) {
            navigateBackToSettingsOverview(in: app)
            doneButton = app.buttons["settingsDoneButton"]
        }
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()
    }

    private func settingsOverview(in app: XCUIApplication) -> XCUIElement {
        let scrollView = app.scrollViews["accountHubScroll"]
        if scrollView.exists {
            return scrollView
        }
        return app.descendants(matching: .any)["accountHubScroll"]
    }

    private func settingsDetailScrollView(in app: XCUIApplication) -> XCUIElement {
        let identified = app.scrollViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "settingsDetail-")
        ).firstMatch
        if identified.exists {
            return identified
        }

        let detailRoot = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "settingsDetail-")
        ).firstMatch
        let nestedScrollView = detailRoot.descendants(matching: .scrollView).firstMatch
        if nestedScrollView.exists {
            return nestedScrollView
        }

        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            return scrollView
        }
        return app.collectionViews.firstMatch
    }

    private func mealsTabButton(in app: XCUIApplication) -> XCUIElement {
        waitForAny([
            app.tabBars.buttons["Meals"],
            app.tabBars.buttons["Jídelna"],
            app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Meal")).firstMatch,
            app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Jídel")).firstMatch
        ], timeout: 1)
    }

    @MainActor
    private func restoreMealsTabIfNeeded(in app: XCUIApplication) {
        if app.state != .runningForeground {
            app.launch()
            _ = app.scrollViews["todayScrollView"].waitForExistence(timeout: 5)
        }

        if mealsTabButton(in: app).exists {
            return
        }

        let resetArgument = "-uiTestingRestoreMealsTab"
        app.terminate()
        if !app.launchArguments.contains(resetArgument) {
            app.launchArguments.append(resetArgument)
        }
        app.launch()
        _ = mealsTabButton(in: app).waitForExistence(timeout: 5)

        app.terminate()
        app.launchArguments.removeAll { $0 == resetArgument }
        app.launch()
        _ = app.scrollViews["todayScrollView"].waitForExistence(timeout: 5)
    }

    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        if let bool = element.value as? Bool {
            return bool
        }
        if let number = element.value as? NSNumber {
            return number.boolValue
        }
        guard let value = element.value as? String else { return false }
        return ["1", "true", "on", "yes", "zapnuto"].contains(value.lowercased())
    }

    private func waitForAny(_ candidates: [XCUIElement], timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = candidates.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return candidates[0]
    }

    private func waitForLabel(
        _ element: XCUIElement,
        containingAny fragments: [String],
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if fragments.contains(where: { element.label.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return fragments.contains(where: { element.label.contains($0) })
    }

    private func waitForSwitch(
        _ element: XCUIElement,
        toEqual expectedValue: Bool,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isSwitchOn(element) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline
        return isSwitchOn(element) == expectedValue
    }

    private func scroll(_ scrollView: XCUIElement, untilExists element: XCUIElement, attempts: Int = 4) {
        guard scrollView.exists else { return }
        for _ in 0..<attempts where !element.exists || !element.isHittable {
            scrollView.swipeUp()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
    }

    private func scroll(
        _ scrollView: XCUIElement,
        untilHittable element: XCUIElement,
        attempts: Int = 6
    ) {
        guard scrollView.exists else { return }
        for _ in 0..<attempts where !element.isHittable {
            scrollView.swipeUp()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        }
        for _ in 0..<attempts where !element.isHittable {
            scrollView.swipeDown()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        }
    }
}
