import Foundation
import Testing
@testable import PiBoard

struct TestingConfigurationTests {
    @Test func normalLaunchDetectsNothing() {
        let configuration = TestingConfiguration.detect(environment: [:], arguments: ["PiBoard"])

        #expect(configuration.isUnitTesting == false)
        #expect(configuration.isUITesting == false)
        #expect(configuration.isRunningTests == false)
        #expect(configuration.uiTestingRoot == nil)
        #expect(configuration.agentDirectory == nil)
        #expect(configuration.projectFolder(named: "X") == nil)
    }

    @Test func unitTestingComesFromTheXCTestEnvironment() {
        let configuration = TestingConfiguration.detect(
            environment: [LaunchEnvironment.testConfigurationEnvKey: "/tmp/x"],
            arguments: []
        )

        #expect(configuration.isUnitTesting)
        #expect(configuration.isRunningTests)
        #expect(configuration.uiTestingRoot == nil)
    }

    @Test func uiTestingCreatesATemporaryRootAndReadsTheFakeEntry() throws {
        let configuration = TestingConfiguration.detect(
            environment: [:],
            arguments: ["PiBoard", LaunchArguments.uiTesting, LaunchArguments.uiTestingPiEntryPrefix + "/tmp/fake-pi.js"]
        )
        let root = try #require(configuration.uiTestingRoot)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(configuration.isUITesting)
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(configuration.fakePiEntry?.path == "/tmp/fake-pi.js")
        #expect(configuration.agentDirectory?.path.hasPrefix(root.path) == true)
        #expect(configuration.worktreesRoot?.path.hasPrefix(root.path) == true)
        #expect(configuration.projectFolder(named: "My App")?.lastPathComponent == "my-app")
    }
}
