import XCTest

// Must match LaunchArguments.uiTesting; the test bundle cannot import the app's internal types cleanly.
private let uiTestingArgument = "--ui-testing"
// Must match LaunchArguments.uiTestingPiEntryPrefix.
private let uiTestingPiEntryPrefix = "--ui-testing-pi-entry="
private let fakePiFileName = "fake-pi.js"

// Must match AccessibilityID in the app.
private enum ID {
    static let inspectorToggle = "inspectorToggle"
    static let changesToggle = "changesToggle"
    static let newTask = "newTask"
    static let terminalDrawerToggle = "terminalDrawerToggle"
    static let backToBoard = "backToBoard"
    static let boardTitle = "boardTitle"
    static let sheetCancel = "sheetCancel"
    static let drawerHide = "drawerHide"
    static let drawerClose = "drawerClose"
    static let changesHide = "changesHide"
    static let preparationStart = "preparationStart"
    static let preparationRunAnyway = "preparationRunAnyway"
    static let preparationResume = "preparationResume"
    static let terminalStop = "terminalStop"
    static let terminalResume = "terminalResume"
    static let terminalHost = "terminalHost"
    static let confirmDestructive = "confirmDestructive"
    static let sidebarRowPrefix = "sidebarRow."
    static let taskCardPrefix = "taskCard."
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

    func testRandomClicksKeepTheWindowResponsive() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        seed = environment[seedEnvironmentKey].flatMap(UInt64.init) ?? defaultSeed
        let steps = environment[stepsEnvironmentKey].flatMap(Int.init) ?? defaultSteps
        generator = SplitMix64(seed: seed)
        print("monkey seed=\(seed) steps=\(steps)")

        app = XCUIApplication()
        let fakePi = FileManager.default.temporaryDirectory.appendingPathComponent(fakePiFileName)
        try FakePi.script.write(to: fakePi, atomically: true, encoding: .utf8)
        app.launchArguments = [uiTestingArgument, uiTestingPiEntryPrefix + fakePi.path]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: canaryTimeout), failureContext(step: -1, action: "launch"))

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
            MonkeyAction(name: "stop pi") { [self] in stopPi() },
            MonkeyAction(name: "resume pi") { [self] in click(ID.terminalResume) },
        ] + weighted
    }

    // Listed twice so terminal activity dominates the random walk.
    private var weighted: [MonkeyAction] {
        let heavy = [
            MonkeyAction(name: "drag task card") { [self] in dragRandomCard() },
            MonkeyAction(name: "start pi from preparation") { [self] in startPiFromPreparation() },
            MonkeyAction(name: "open terminal") { [self] in randomElement(withPrefix: ID.taskCardPrefix)?.doubleClick() },
            MonkeyAction(name: "type hey") { [self] in typeIntoTerminal() },
        ]
        return heavy + heavy
    }

    private func startPiFromPreparation() {
        for identifier in [ID.preparationStart, ID.preparationRunAnyway, ID.preparationResume] where exists(identifier) {
            click(identifier)
            return
        }
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
