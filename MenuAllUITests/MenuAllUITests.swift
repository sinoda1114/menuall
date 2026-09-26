import XCTest

@MainActor
final class MenuAllUITests: XCTestCase {
    private enum Identifier {
        static let onboarding = "menuall.onboarding"
        static let popover = "menuall.popover"
        static let popoverHeader = "menuall.popover.header"
        static let popoverEmptyState = "menuall.popover.empty"
        static let hiddenSection = "menuall.section.hidden"
        static let visibleSection = "menuall.section.visible"
        static let unknownSection = "menuall.section.unknown"
        static let unavailableSection = "menuall.section.unavailable"
        static let hiddenFixtureItem = "menuall.item.ui-test-hidden"
        static let visibleFixtureItem = "menuall.item.ui-test-visible"
        static let unknownFixtureItem = "menuall.item.ui-test-position-unknown"
        static let unsupportedFixtureItem = "menuall.item.ui-test-unsupported"
        static let hiddenFixtureOpen = "menuall.item.ui-test-hidden.open"
        static let hiddenFixtureToggle = "menuall.item.ui-test-hidden.visibility-toggle"
        static let visibleFixtureToggle = "menuall.item.ui-test-visible.visibility-toggle"
        static let unknownFixtureToggle = "menuall.item.ui-test-position-unknown.visibility-toggle"
        static let unsupportedFixtureToggle = "menuall.item.ui-test-unsupported.visibility-toggle"
        static let unsupportedFixtureReason = "menuall.item.ui-test-unsupported.visibility-unsupported"
        static let visibilityError = "menuall.visibility.error"
        static let visibilityUndo = "menuall.visibility.undo"
        static let visibilityUndoAction = "menuall.visibility.undo.action"
        static let itemOpened = "menuall.item-opened"
        static let actionError = "menuall.action-error"
        static let refresh = "menuall.refresh"
        static let settings = "menuall.settings"
        static let permissionReason = "menuall.permission.reason"
        static let permissionDenied = "menuall.permission.state.denied"
        static let permissionGranted = "menuall.permission.state.granted"
        static let openSystemSettings = "menuall.permission.open-system-settings"
        static let recheckPermission = "menuall.permission.recheck"
        static let quit = "menuall.quit"
    }

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDeniedPermissionShowsReasonAndRecoveryActions() throws {
        launchOnboarding(accessibilitySequence: [.denied])

        XCTAssertTrue(element(Identifier.onboarding).waitForExistence(timeout: 3))
        XCTAssertTrue(element(Identifier.permissionDenied).exists)
        XCTAssertTrue(element(Identifier.permissionReason).exists)
        XCTAssertTrue(element(Identifier.openSystemSettings).isEnabled)
        XCTAssertTrue(element(Identifier.recheckPermission).isEnabled)
        XCTAssertTrue(element(Identifier.quit).isEnabled)
    }

    @MainActor
    func testRecheckReflectsPermissionGranted() throws {
        launchOnboarding(accessibilitySequence: [.denied, .granted])

        XCTAssertTrue(element(Identifier.permissionDenied).waitForExistence(timeout: 3))
        element(Identifier.recheckPermission).click()

        XCTAssertTrue(element(Identifier.permissionGranted).waitForExistence(timeout: 3))
    }

    @MainActor
    func testSystemSettingsActionKeepsGuideOpenWhenNavigationIsSuppressed() throws {
        launchOnboarding(accessibilitySequence: [.denied])

        let guide = element(Identifier.onboarding)
        XCTAssertTrue(guide.waitForExistence(timeout: 3))
        element(Identifier.openSystemSettings).click()

        XCTAssertTrue(guide.waitForExistence(timeout: 1))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testQuitEndsApplicationFromPermissionGuide() throws {
        launchOnboarding(accessibilitySequence: [.denied])

        let quitButton = element(Identifier.quit)
        XCTAssertTrue(quitButton.waitForExistence(timeout: 3))
        quitButton.click()

        assertApplicationTerminates()
    }

    func testGrantedPopoverShowsHeaderEmptyStateAndActions() throws {
        launchPopover()

        XCTAssertTrue(
            element(Identifier.popover).waitForExistence(timeout: 3),
            app.debugDescription
        )
        XCTAssertTrue(element(Identifier.popoverHeader).exists)
        XCTAssertTrue(element(Identifier.popoverEmptyState).exists)
        XCTAssertTrue(element(Identifier.refresh).isEnabled)
        XCTAssertTrue(element(Identifier.settings).isEnabled)
        XCTAssertTrue(element(Identifier.quit).isEnabled)

        element(Identifier.refresh).click()
        XCTAssertTrue(element(Identifier.popover).waitForExistence(timeout: 1))
    }

    func testSettingsOpensFromGrantedPopover() throws {
        launchPopover()

        XCTAssertTrue(element(Identifier.settings).waitForExistence(timeout: 3))
        element(Identifier.settings).click()

        XCTAssertTrue(app.windows["MenuAll 設定"].waitForExistence(timeout: 3))
    }

    func testQuitEndsApplicationFromGrantedPopover() throws {
        launchPopover()

        let quitButton = element(Identifier.quit)
        XCTAssertTrue(quitButton.waitForExistence(timeout: 3))
        quitButton.click()

        assertApplicationTerminates()
    }

    func testPopoverSeparatesKnownVisibilityFromUnavailableItems() throws {
        launchPopover(showsVisibilityFixture: true)

        let hiddenSection = element(Identifier.hiddenSection)
        let visibleSection = element(Identifier.visibleSection)
        let unknownSection = element(Identifier.unknownSection)
        let hiddenFixtureItem = element(Identifier.hiddenFixtureItem)
        let visibleFixtureItem = element(Identifier.visibleFixtureItem)
        let unknownFixtureItem = element(Identifier.unknownFixtureItem)
        let unavailableSection = element(Identifier.unavailableSection)

        XCTAssertTrue(hiddenSection.waitForExistence(timeout: 3))
        XCTAssertEqual(hiddenSection.label, "メニューバーで非表示")
        XCTAssertTrue(visibleSection.exists)
        XCTAssertEqual(visibleSection.label, "メニューバーに表示中")
        XCTAssertFalse(unknownSection.exists)
        XCTAssertTrue(unavailableSection.exists)
        XCTAssertEqual(unavailableSection.label, "表示切り替えができない項目")
        XCTAssertTrue(hiddenFixtureItem.exists)
        XCTAssertTrue(visibleFixtureItem.exists)
        XCTAssertTrue(unknownFixtureItem.exists)
        XCTAssertTrue(unknownFixtureItem.isEnabled)
        XCTAssertLessThan(hiddenSection.frame.minY, visibleSection.frame.minY)
        XCTAssertLessThan(visibleSection.frame.minY, unavailableSection.frame.minY)
    }

    func testTwoVisibilityGroupsReverseOrderWhenVisibleItemsAreFirst() throws {
        launchPopover(showsVisibilityFixture: true, prioritizesHidden: false)

        let hiddenSection = element(Identifier.hiddenSection)
        let visibleSection = element(Identifier.visibleSection)
        let unknownSection = element(Identifier.unknownSection)

        XCTAssertTrue(visibleSection.waitForExistence(timeout: 3))
        XCTAssertTrue(hiddenSection.exists)
        XCTAssertFalse(unknownSection.exists)
        XCTAssertEqual(visibleSection.label, "メニューバーに表示中")
        XCTAssertLessThan(visibleSection.frame.minY, hiddenSection.frame.minY)
    }

    func testFailedItemActionReopensPopoverAndShowsError() throws {
        launchPopover(showsVisibilityFixture: true)

        let fixtureItem = element(Identifier.hiddenFixtureOpen)
        XCTAssertTrue(fixtureItem.waitForExistence(timeout: 3))
        fixtureItem.click()

        XCTAssertTrue(element(Identifier.popover).waitForExistence(timeout: 3))
        let error = element(Identifier.actionError)
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "項目が更新されたため、もう一度選択してください。")
    }

    func testAccessibilityLossDuringItemActionReopensPermissionGuide() throws {
        launchPopover(
            showsVisibilityFixture: true,
            revokesAccessibilityOnItemAction: true
        )

        let fixtureItem = element(Identifier.hiddenFixtureOpen)
        XCTAssertTrue(fixtureItem.waitForExistence(timeout: 3))
        fixtureItem.click()

        XCTAssertTrue(element(Identifier.popover).waitForExistence(timeout: 3))
        XCTAssertTrue(element(Identifier.permissionDenied).waitForExistence(timeout: 3))
        XCTAssertTrue(element(Identifier.permissionReason).exists)
        XCTAssertTrue(element(Identifier.openSystemSettings).isEnabled)
        XCTAssertFalse(element(Identifier.actionError).exists)
    }

    func testHiddenItemCanBeShownAndMovesToVisibleGroup() throws {
        launchPopover(
            showsVisibilityFixture: true,
            visibilityChangeScenario: .success
        )

        let toggle = element(Identifier.hiddenFixtureToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(toggle), false, toggle.debugDescription)

        toggle.click()

        XCTAssertTrue(waitUntil(timeout: 3) { self.toggleIsOn(toggle) == true })
        XCTAssertTrue(element(Identifier.visibilityUndo).exists)
        XCTAssertTrue(element(Identifier.visibilityUndoAction).isEnabled)
        XCTAssertGreaterThan(
            element(Identifier.hiddenFixtureItem).frame.minY,
            element(Identifier.visibleSection).frame.minY
        )
    }

    func testVisibleItemCanBeHiddenAndMovesToHiddenGroup() throws {
        launchPopover(
            showsVisibilityFixture: true,
            visibilityChangeScenario: .success
        )

        let toggle = element(Identifier.visibleFixtureToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(toggle), true)

        toggle.click()

        XCTAssertTrue(waitUntil(timeout: 3) { self.toggleIsOn(toggle) == false })
        XCTAssertFalse(element(Identifier.visibleSection).exists)
        XCTAssertGreaterThan(
            element(Identifier.visibleFixtureItem).frame.minY,
            element(Identifier.hiddenSection).frame.minY
        )
        XCTAssertLessThan(
            element(Identifier.visibleFixtureItem).frame.minY,
            element(Identifier.unavailableSection).frame.minY
        )
    }

    func testFailedVisibilityChangeKeepsOriginalGroupAndShowsError() throws {
        launchPopover(
            showsVisibilityFixture: true,
            visibilityChangeScenario: .failure
        )

        let toggle = element(Identifier.hiddenFixtureToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.click()

        XCTAssertTrue(element(Identifier.visibilityError).waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(toggle), false)
        XCTAssertLessThan(
            element(Identifier.hiddenFixtureItem).frame.minY,
            element(Identifier.visibleSection).frame.minY
        )
    }

    func testUnsupportedAndUnknownItemsExplainWhyToggleIsDisabled() throws {
        launchPopover(
            showsVisibilityFixture: true,
            visibilityChangeScenario: .unsupported
        )

        let unknownToggle = element(Identifier.unknownFixtureToggle)
        let unsupportedToggle = element(Identifier.unsupportedFixtureToggle)
        XCTAssertTrue(unknownToggle.waitForExistence(timeout: 3))
        XCTAssertFalse(unknownToggle.isEnabled)
        XCTAssertTrue(unsupportedToggle.exists)
        XCTAssertFalse(unsupportedToggle.isEnabled)
        XCTAssertEqual(
            element(Identifier.unsupportedFixtureReason).label,
            "この項目は表示切り替えに対応していません。"
        )
    }

    func testOpenOriginalMenuDoesNotChangeVisibility() throws {
        launchPopover(
            showsVisibilityFixture: true,
            visibilityChangeScenario: .success
        )

        let openButton = element(Identifier.hiddenFixtureOpen)
        let toggle = element(Identifier.hiddenFixtureToggle)
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(toggle), false)

        openButton.click()

        XCTAssertTrue(element(Identifier.itemOpened).waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(toggle), false)
    }

    @MainActor
    private func launchOnboarding(accessibilitySequence: [AccessibilityState]) {
        registerTerminationCleanup()
        app.launchEnvironment["MENUALL_UI_TESTING"] = "1"
        app.launchEnvironment["MENUALL_UI_TEST_ROUTE"] = "onboarding"
        app.launchEnvironment["MENUALL_UI_TEST_ACCESSIBILITY_SEQUENCE"] = accessibilitySequence
            .map(\.rawValue)
            .joined(separator: ",")
        app.launchEnvironment["MENUALL_UI_TEST_SUPPRESS_EXTERNAL_NAVIGATION"] = "1"
        app.launch()
    }

    private func launchPopover(
        showsVisibilityFixture: Bool = false,
        prioritizesHidden: Bool? = nil,
        revokesAccessibilityOnItemAction: Bool = false,
        visibilityChangeScenario: VisibilityChangeScenario? = nil
    ) {
        registerTerminationCleanup()
        app.launchEnvironment["MENUALL_UI_TESTING"] = "1"
        app.launchEnvironment["MENUALL_UI_TEST_ROUTE"] = "popover"
        app.launchEnvironment["MENUALL_UI_TEST_ACCESSIBILITY_SEQUENCE"] = "granted"
        app.launchEnvironment["MENUALL_UI_TEST_SUPPRESS_EXTERNAL_NAVIGATION"] = "1"
        if showsVisibilityFixture {
            app.launchEnvironment["MENUALL_UI_TEST_VISIBILITY_FIXTURE"] = "three-categories"
        } else {
            app.launchEnvironment.removeValue(forKey: "MENUALL_UI_TEST_VISIBILITY_FIXTURE")
        }
        if let prioritizesHidden {
            app.launchArguments += ["-prioritizeHidden", prioritizesHidden ? "YES" : "NO"]
        }
        if revokesAccessibilityOnItemAction {
            app.launchEnvironment["MENUALL_UI_TEST_REVOKE_ACCESSIBILITY_ON_ITEM_ACTION"] = "1"
        } else {
            app.launchEnvironment.removeValue(
                forKey: "MENUALL_UI_TEST_REVOKE_ACCESSIBILITY_ON_ITEM_ACTION"
            )
        }
        if let visibilityChangeScenario {
            app.launchEnvironment["MENUALL_UI_TEST_VISIBILITY_CHANGE_SCENARIO"] =
                visibilityChangeScenario.rawValue
        } else {
            app.launchEnvironment.removeValue(
                forKey: "MENUALL_UI_TEST_VISIBILITY_CHANGE_SCENARIO"
            )
        }
        app.launch()
    }

    private func registerTerminationCleanup() {
        addTeardownBlock { @MainActor [weak app] in
            guard let app, app.state != .notRunning else { return }
            app.terminate()
        }
    }

    private func assertApplicationTerminates() {
        let terminated = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak app] _, _ in
                app?.state == .notRunning
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [terminated], timeout: 3), .completed)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func toggleIsOn(_ toggle: XCUIElement) -> Bool? {
        if let value = toggle.value as? NSNumber {
            return value.boolValue
        }
        if let value = toggle.value as? String {
            if ["1", "on", "オン"].contains(value.lowercased()) { return true }
            if ["0", "off", "オフ"].contains(value.lowercased()) { return false }
        }
        return nil
    }
}

private enum AccessibilityState: String {
    case denied
    case granted
}

private enum VisibilityChangeScenario: String {
    case success
    case failure
    case unsupported
}
