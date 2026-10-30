import XCTest

// Must match LaunchArguments.uiTesting; the test bundle cannot import the app's internal types cleanly.
private let uiTestingArgument = "--ui-testing"
// Must match LaunchArguments.uiTestingPiEntryPrefix.
private let uiTestingPiEntryPrefix = "--ui-testing-pi-entry="
// Must match LaunchArguments.uiTestingOpenCodePrefix.
private let uiTestingOpenCodePrefix = "--ui-testing-opencode="
// Must match LaunchArguments.uiTestingClaudePrefix.
private let uiTestingClaudePrefix = "--ui-testing-claude="
// Must match LaunchArguments.uiTestingRootPrefix.
private let uiTestingRootPrefix = "--ui-testing-root="
// Menu item titles of the agent picker; an agent turned off in Settings carries AgentKindPicker.offSuffix.
private let openCodeAgentTitle = "OpenCode"
private let claudeAgentTitle = "Claude Code"
private let terminalFocusOffset = CGVector(dx: 0.5, dy: 0.5)

// Must match AccessibilityID in the app.
private enum ID {
    static let inspectorToggle = "inspectorToggle"
    static let changesToggle = "changesToggle"
    static let newTask = "newTask"
    static let insertTemplate = "insertTemplate"
    static let terminalDrawerToggle = "terminalDrawerToggle"
    static let backToBoard = "backToBoard"
    static let boardTitle = "boardTitle"
    static let sheetCancel = "sheetCancel"
    static let drawerHide = "drawerHide"
    static let drawerClose = "drawerClose"
    static let changesHide = "changesHide"
    static let changesPush = "changesPush"
    static let changesPullRequest = "changesPullRequest"
    static let preparationStart = "preparationStart"
    static let preparationRunAnyway = "preparationRunAnyway"
    static let preparationResume = "preparationResume"
    static let preparationAgentPicker = "preparationAgentPicker"
    static let projectDefaultAgentPicker = "projectDefaultAgentPicker"
    static let openCodeRefresh = "openCodeRefresh"
    static let terminalStop = "terminalStop"
    static let terminalInterrupt = "terminalInterrupt"
    static let terminalResume = "terminalResume"
    static let terminalHost = "terminalHost"
    static let terminalStatus = "terminalStatus"
    static let confirmDestructive = "confirmDestructive"
    static let sidebarRowPrefix = "sidebarRow."
    static let taskCardPrefix = "taskCard."
    static let commandPaletteField = "commandPaletteField"
    static let commandPaletteRowPrefix = "commandPaletteRow."
    static let commitGenerate = "commitGenerate"
    static let commitGenerateAgentPrefix = "commitGenerateAgent."
}

private let seedEnvironmentKey = "PIBOARD_MONKEY_SEED"
private let stepsEnvironmentKey = "PIBOARD_MONKEY_STEPS"
private let defaultSeed: UInt64 = 1
private let defaultSteps = 200
private let canaryInterval = 10
private let probeTimeout: TimeInterval = 2
private let canaryTimeout: TimeInterval = 3
private let confirmationTimeout: TimeInterval = 1
// One workspace terminal plus one drawer; more means terminal views stacked.
private let maxTerminalViews = 2
private let maxSheets = 1
private let typedText = "hey!\r"
private let dragHoldDuration: TimeInterval = 0.3
private let debugDescriptionLineLimit = 150
private let viewMenuTitle = "View"
// Must match CommandPaletteCommand.menuTitle.
private let commandPaletteMenuTitle = "Command Palette..."
private let paletteQuery = "a"

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class MonkeyTests: XCTestCase {
    private struct MonkeyAction {
        let name: String
        let run: () -> Void
    }

    private var app = XCUIApplication()
    private var generator = SplitMix64(seed: defaultSeed)
    private var seed = defaultSeed
    private var fixture: FakeOpenCodeFixture?
    private static let activityTimeout: TimeInterval = 8
    private static let workingLabel = "Working"
    private static let needsInputLabel = "Needs input"
    private static let idleLabel = "Idle"
    private static let permissionCommand = "permission"
    private static let finishCommand = "finish"
    private static let permissionReply = "yes\r"
    private static let typedPermissionCommand = "permission\r"
    private static let typedFinishCommand = "finish\r"
    private static let freshTaskTitle = "Add dark mode toggle"
    private static let moveToInProgressTitle = "Move to In Progress"

    private func cleanUp() {
        // The app goes first so an in-flight service start cannot spawn a new detached server after shutdown.
        app.terminate()
        defer { fixture = nil }
        do { try fixture?.stop() }
        catch { XCTFail("Fake teardown failed: \(error.localizedDescription)") }
    }

    private func launch(deterministic: Bool) async throws -> FakeOpenCodeFixture {
        let fake = try FakeOpenCodeFixture(deterministic: deterministic)
        fixture = fake
        // A failed XCTest assertion unwinds with an Objective-C exception that skips Swift `defer`, so teardown is registered here too.
        addTeardownBlock { @MainActor [self] in cleanUp() }
        app = XCUIApplication()
        app.launchEnvironment = ["HOME": fake.directory.path, "CFFIXED_USER_HOME": fake.directory.path]
        app.launchArguments = [uiTestingArgument, uiTestingPiEntryPrefix + fake.piEntry.path, uiTestingOpenCodePrefix + fake.binary.path, uiTestingClaudePrefix + fake.claudeBinary.path, uiTestingRootPrefix + fake.appRoot.path]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: canaryTimeout))
        return fake
    }

    func testOpenCodeActivityAndReconnectResync() async throws {
        defer { cleanUp() }
        continueAfterFailure = false
        let fake = try await launch(deterministic: true)
        click(ID.sheetCancel)
        elements(withPrefix: ID.sidebarRowPrefix).element(boundBy: 0).click()
        let card = elements(withPrefix: ID.taskCardPrefix).containing(.staticText, identifier: Self.freshTaskTitle).firstMatch
        guard card.waitForExistence(timeout: canaryTimeout) else {
            XCTFail("Fresh task missing. \(captureFailureState(context: "OpenCode setup"))")
            return
        }
        card.rightClick()
        app.menuItems[Self.moveToInProgressTitle].click()
        let picker = app.descendants(matching: .any).matching(identifier: ID.preparationAgentPicker).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: Self.activityTimeout))
        waitUntilEnabled(picker)
        picker.click()
        let item = app.menuItems[openCodeAgentTitle]
        XCTAssertTrue(item.waitForExistence(timeout: Self.activityTimeout))
        item.click()
        let start = app.buttons[ID.preparationStart]
        XCTAssertTrue(start.waitForExistence(timeout: Self.activityTimeout))
        waitUntilEnabled(start)
        start.click()
        let initial = try await fake.waitForState("initial subscription and active TUI", matching: { $0.active.count == 1 && $0.streams == 1 && $0.resyncs >= 1 })
        let sessionID = try XCTUnwrap(initial.active.first)
        assertActivity(Self.workingLabel)

        try await fake.control(Self.permissionCommand, sessionID: sessionID)
        assertActivity(Self.needsInputLabel)
        // A pending permission must remain active and must not finish on a timer.
        let pendingPermission = try await fake.state()
        XCTAssertTrue(pendingPermission.active.contains(sessionID))
        focusTerminal()
        app.typeText(Self.permissionReply)
        assertActivity(Self.workingLabel)
        try await fake.control(Self.finishCommand, sessionID: sessionID)
        assertActivity(Self.idleLabel)
        _ = try await fake.waitForState("completed turn removed from active set", matching: { $0.active.isEmpty })

        // A live start event, not the resync snapshot, must set Working.
        focusTerminal()
        app.typeText(typedText)
        assertActivity(Self.workingLabel)
        try await fake.control(Self.finishCommand, sessionID: sessionID)
        assertActivity(Self.idleLabel)
        _ = try await fake.waitForState("live turn removed from active set", matching: { $0.active.isEmpty })

        // Lose the next start event: reconnect must recover Working from the active snapshot.
        try await fake.disconnect()
        focusTerminal()
        app.typeText(typedText)
        _ = try await fake.waitForState("turn started while disconnected", matching: { $0.blocked && $0.active.contains(sessionID) })
        assertActivity(Self.idleLabel)
        try await fake.reconnect()
        _ = try await fake.waitForState("second subscription and resync", matching: { $0.subscriptions > initial.subscriptions && $0.resyncs > initial.resyncs && $0.streams == 1 })
        assertActivity(Self.workingLabel)

        // Lose completion too: resync must clear stale Working rather than replay fake events.
        let connected = try await fake.state()
        try await fake.disconnect()
        try await fake.control(Self.finishCommand, sessionID: sessionID)
        _ = try await fake.waitForState("turn finished while disconnected", matching: { $0.blocked && $0.active.isEmpty })
        assertActivity(Self.workingLabel)
        try await fake.reconnect()
        _ = try await fake.waitForState("third subscription and resync", matching: { $0.subscriptions > connected.subscriptions && $0.resyncs > connected.resyncs && $0.streams == 1 })
        assertActivity(Self.idleLabel)
    }

    func testClaudeCodeActivityThroughTitleAndHooks() async throws {
        defer { cleanUp() }
        continueAfterFailure = false
        _ = try await launch(deterministic: true)
        click(ID.sheetCancel)
        elements(withPrefix: ID.sidebarRowPrefix).element(boundBy: 0).click()
        let card = elements(withPrefix: ID.taskCardPrefix).containing(.staticText, identifier: Self.freshTaskTitle).firstMatch
        guard card.waitForExistence(timeout: canaryTimeout) else {
            XCTFail("Fresh task missing. \(captureFailureState(context: "Claude Code setup"))")
            return
        }
        card.rightClick()
        app.menuItems[Self.moveToInProgressTitle].click()
        let picker = app.descendants(matching: .any).matching(identifier: ID.preparationAgentPicker).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: Self.activityTimeout))
        waitUntilEnabled(picker)
        picker.click()
        let item = app.menuItems[claudeAgentTitle]
        XCTAssertTrue(item.waitForExistence(timeout: Self.activityTimeout))
        item.click()
        let start = app.buttons[ID.preparationStart]
        XCTAssertTrue(start.waitForExistence(timeout: Self.activityTimeout))
        waitUntilEnabled(start)
        start.click()
        assertActivity(Self.workingLabel)

        focusTerminal()
        app.typeText(Self.typedPermissionCommand)
        assertActivity(Self.needsInputLabel)
        app.typeText(Self.permissionReply)
        assertActivity(Self.workingLabel)
        app.typeText(Self.typedFinishCommand)
        assertActivity(Self.idleLabel)
    }

    // The terminal view is not exposed to accessibility, so focus it by clicking the middle of the window.
    private func focusTerminal() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: terminalFocusOffset).click()
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        let result = XCTWaiter().wait(for: [ready], timeout: Self.activityTimeout)
        if result != .completed { _ = captureFailureState(context: "OpenCode preflight") }
        XCTAssertEqual(result, .completed)
    }

    private func assertActivity(_ label: String) {
        let badge = app.descendants(matching: .any).matching(identifier: ID.terminalStatus).firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ OR value == %@", label, label), object: badge)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.activityTimeout)
        if result != .completed { _ = captureFailureState(context: "Expected terminal activity: \(label)") }
        XCTAssertEqual(result, .completed, "Expected terminal activity: \(label)")
    }

    func testRandomClicksKeepTheWindowResponsive() async throws {
        defer { cleanUp() }
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        seed = environment[seedEnvironmentKey].flatMap(UInt64.init) ?? defaultSeed
        let steps = environment[stepsEnvironmentKey].flatMap(Int.init) ?? defaultSteps
        generator = SplitMix64(seed: seed)
        print("monkey seed=\(seed) steps=\(steps)")

        _ = try await launch(deterministic: false)

        let actions = makeActions()
        for step in 0..<steps {
            let action = actions[Int.random(in: 0..<actions.count, using: &generator)]
            print("monkey step=\(step) action=\(action.name)")
            action.run()
            guard isResponsive() else {
                let state = captureFailureState(context: "step=\(step) action=\(action.name)")
                XCTFail("toolbar stopped responding. \(failureContext(step: step, action: action.name)) \(state)")
                return
            }
            if let violation = checkInvariants() {
                let state = captureFailureState(context: "step=\(step) action=\(action.name)")
                XCTFail("\(violation) \(failureContext(step: step, action: action.name)) \(state)")
                return
            }
            if (step + 1) % canaryInterval == 0, let failure = runCanary() {
                let state = captureFailureState(context: "step=\(step) canary after \(action.name)")
                XCTFail("\(failure) \(failureContext(step: step, action: "canary after \(action.name)")) \(state)")
                return
            }
        }
        click(ID.backToBoard)
        if let violation = checkInvariants() {
            let state = captureFailureState(context: "final check")
            XCTFail("\(violation) \(failureContext(step: steps, action: "final check")) \(state)")
            return
        }
        print("monkey finished seed=\(seed) steps=\(steps)")
    }

    private func failureContext(step: Int, action: String) -> String {
        "step=\(step) action=\(action) seed=\(seed)"
    }

    private func captureFailureState(context: String) -> String {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = app.debugDescription.split(separator: "\n", omittingEmptySubsequences: false).prefix(debugDescriptionLineLimit)
        print("monkey failure context=\(context)\n\(tree.joined(separator: "\n"))")
        return "windows=\(app.windows.count) sheets=\(app.sheets.count) menus=\(app.menus.count) dialogs=\(app.dialogs.count) boardTitles=\(app.staticTexts.matching(identifier: ID.boardTitle).count) anyBoardTitle=\(app.descendants(matching: .any).matching(identifier: ID.boardTitle).count) sidebarRows=\(elements(withPrefix: ID.sidebarRowPrefix).count) firstResponderWindowTitle=\(app.windows.firstMatch.title)"
    }

    private func makeActions() -> [MonkeyAction] {
        [
            MonkeyAction(name: "click sidebar row") { [self] in randomElement(withPrefix: ID.sidebarRowPrefix)?.click() },
            MonkeyAction(name: "click task card") { [self] in randomElement(withPrefix: ID.taskCardPrefix)?.click() },
            MonkeyAction(name: "double-click task card") { [self] in randomElement(withPrefix: ID.taskCardPrefix)?.doubleClick() },
            MonkeyAction(name: "right-click task card") { [self] in
                randomElement(withPrefix: ID.taskCardPrefix)?.rightClick()
                app.typeKey(.escape, modifierFlags: [])
            },
            MonkeyAction(name: "click inspector toggle") { [self] in click(ID.inspectorToggle) },
            MonkeyAction(name: "click changes toggle") { [self] in click(ID.changesToggle) },
            MonkeyAction(name: "click terminal drawer toggle") { [self] in click(ID.terminalDrawerToggle) },
            MonkeyAction(name: "new task then cancel") { [self] in
                click(ID.newTask)
                click(ID.sheetCancel)
            },
            MonkeyAction(name: "click back to board") { [self] in click(ID.backToBoard) },
            MonkeyAction(name: "press escape") { [self] in app.typeKey(.escape, modifierFlags: []) },
            MonkeyAction(name: "drawer hide") { [self] in click(ID.drawerHide) },
            MonkeyAction(name: "drawer close") { [self] in click(ID.drawerClose) },
            MonkeyAction(name: "changes hide") { [self] in click(ID.changesHide) },
            MonkeyAction(name: "changes push") { [self] in click(ID.changesPush) },
            MonkeyAction(name: "stop pi") { [self] in stopPi() },
            MonkeyAction(name: "interrupt pi") { [self] in click(ID.terminalInterrupt) },
            MonkeyAction(name: "resume pi") { [self] in click(ID.terminalResume) },
            MonkeyAction(name: "command palette") { [self] in usePalette() },
        ] + weighted
    }

    // Listed twice so terminal activity dominates the random walk.
    private var weighted: [MonkeyAction] {
        let heavy = [
            MonkeyAction(name: "drag task card") { [self] in dragRandomCard() },
            MonkeyAction(name: "start pi from preparation") { [self] in startPiFromPreparation() },
            MonkeyAction(name: "open terminal") { [self] in randomElement(withPrefix: ID.taskCardPrefix)?.doubleClick() },
            MonkeyAction(name: "type hey") { [self] in typeIntoTerminal() },
            MonkeyAction(name: "pick opencode agent") { [self] in pickAgent(title: openCodeAgentTitle) },
            MonkeyAction(name: "pick claude agent") { [self] in pickAgent(title: claudeAgentTitle) },
            MonkeyAction(name: "commit generate") { [self] in click(ID.commitGenerate) },
            MonkeyAction(name: "commit generate menu") { [self] in pickCommitGenerateAgent() },
        ]
        return heavy + heavy
    }

    private func startPiFromPreparation() {
        for identifier in [ID.preparationStart, ID.preparationRunAnyway, ID.preparationResume] where exists(identifier) {
            click(identifier)
            return
        }
    }

    // The picker is a popup; its options only exist while the menu is open, so close it when the item is missing.
    private func pickAgent(title: String) {
        let picker = app.descendants(matching: .any).matching(identifier: ID.preparationAgentPicker).firstMatch
        guard picker.exists, picker.isHittable, picker.isEnabled else { return }
        picker.click()
        let item = app.menuItems[title]
        guard item.waitForExistence(timeout: confirmationTimeout), item.isEnabled else {
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        item.click()
    }

    // The menu indicator sits at the trailing edge of the split button; close the menu when no item appears.
    private func pickCommitGenerateAgent() {
        let button = app.descendants(matching: .any).matching(identifier: ID.commitGenerate).firstMatch
        guard button.exists, button.isHittable, button.isEnabled else { return }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
        guard let item = randomElement(withPrefix: ID.commitGenerateAgentPrefix) else {
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        item.click()
    }

    private func typeIntoTerminal() {
        let host = app.descendants(matching: .any).matching(identifier: ID.terminalHost).firstMatch
        guard host.exists, host.isHittable else { return }
        host.click()
        app.typeText(typedText)
    }

    private func stopPi() {
        click(ID.terminalStop)
        let confirm = app.descendants(matching: .any).matching(identifier: ID.confirmDestructive).firstMatch
        if confirm.waitForExistence(timeout: confirmationTimeout), confirm.isHittable {
            confirm.click()
        }
    }

    // Opens the palette from the menu bar (shortcuts are not started under UI testing), searches, and picks or cancels.
    private func usePalette() {
        let menu = app.menuBarItems[viewMenuTitle]
        guard menu.exists else { return }
        menu.click()
        let item = menu.menuItems[commandPaletteMenuTitle]
        guard item.waitForExistence(timeout: confirmationTimeout) else {
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        item.click()
        let field = app.descendants(matching: .any).matching(identifier: ID.commandPaletteField).firstMatch
        guard field.waitForExistence(timeout: confirmationTimeout) else { return }
        app.typeText(paletteQuery)
        if Bool.random(using: &generator) {
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
        } else {
            click(ID.sheetCancel)
        }
    }

    private func exists(_ identifier: String) -> Bool {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        return element.exists && element.isHittable
    }

    private func elements(withPrefix prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func randomElement(withPrefix prefix: String) -> XCUIElement? {
        let query = elements(withPrefix: prefix)
        let count = query.count
        guard count > 0 else { return nil }
        let element = query.element(boundBy: Int.random(in: 0..<count, using: &generator))
        return element.exists && element.isHittable ? element : nil
    }

    private func click(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard element.exists, element.isHittable else { return }
        element.click()
    }

    private func dragRandomCard() {
        guard let source = randomElement(withPrefix: ID.taskCardPrefix),
              let target = randomElement(withPrefix: ID.taskCardPrefix),
              source.identifier != target.identifier else { return }
        source.press(forDuration: dragHoldDuration, thenDragTo: target)
        click(ID.sheetCancel)
    }

    private func isResponsive() -> Bool {
        let window = app.windows.firstMatch
        guard window.exists else { return false }
        let button = window.toolbars.buttons.firstMatch
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: button)
        return XCTWaiter().wait(for: [hittable], timeout: probeTimeout) == .completed
    }

    // Returns a failure message, or nil when no structural invariant is broken.
    private func checkInvariants() -> String? {
        let hosts = app.windows.firstMatch.descendants(matching: .any).matching(identifier: ID.terminalHost).count
        if hosts > maxTerminalViews {
            return "terminal views stacked: \(hosts) terminalHost elements, max \(maxTerminalViews)."
        }
        let sheets = app.sheets.count
        if sheets > maxSheets {
            return "\(sheets) sheets on screen, max \(maxSheets)."
        }
        return nil
    }

    // Returns a failure message, or nil when the first project's board is on screen again.
    private func runCanary() -> String? {
        click(ID.backToBoard)
        guard let row = elements(withPrefix: ID.sidebarRowPrefix).allElementsBoundByIndex.first(where: \.isHittable) else {
            return "no hittable sidebar row."
        }
        row.click()
        let title = app.staticTexts[ID.boardTitle]
        guard title.waitForExistence(timeout: canaryTimeout) else {
            return "board title missing after clicking the first project."
        }
        return nil
    }
}
