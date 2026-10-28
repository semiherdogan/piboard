import Foundation
import Testing
@testable import PiBoard

struct OpenCodeServiceLocatorTests {
    private let executable = URL(fileURLWithPath: "/opt/opencode")
    private let serviceURL = "http://127.0.0.1:49374"

    private func makeConfigDirectory(file contents: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let contents {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(OpenCodeServiceLocator.configFileName))
        }
        return directory
    }

    @Test func parseStatusReadsTheFirstLineURL() {
        #expect(OpenCodeServiceLocator.parseStatus(serviceURL + "\nextra\n")?.absoluteString == serviceURL)
    }

    @Test func parseStatusReturnsNilForEmptyOutput() {
        #expect(OpenCodeServiceLocator.parseStatus("") == nil)
        #expect(OpenCodeServiceLocator.parseStatus("\n  \n") == nil)
    }

    @Test func parseStatusReturnsNilForGarbage() {
        #expect(OpenCodeServiceLocator.parseStatus("service is not running") == nil)
        #expect(OpenCodeServiceLocator.parseStatus("file:///tmp/x") == nil)
    }

    @Test func readPasswordReadsServiceJSON() throws {
        let directory = try makeConfigDirectory(file: #"{"password":"secret-value"}"#)
        #expect(OpenCodeServiceLocator.readPassword(configDirectory: directory) == "secret-value")
    }

    @Test func readPasswordReturnsNilWhenMissingOrMalformed() throws {
        #expect(OpenCodeServiceLocator.readPassword(configDirectory: try makeConfigDirectory(file: nil)) == nil)
        #expect(OpenCodeServiceLocator.readPassword(configDirectory: try makeConfigDirectory(file: "not json")) == nil)
        #expect(OpenCodeServiceLocator.readPassword(configDirectory: try makeConfigDirectory(file: #"{"other":"x"}"#)) == nil)
    }

    @Test func defaultConfigDirectoryIsUnderDotConfig() {
        let home = URL(fileURLWithPath: "/Users/x", isDirectory: true)
        #expect(OpenCodeServiceLocator.defaultConfigDirectory(home: home).path == "/Users/x/.config/opencode")
    }

    @Test func discoverReturnsTheURLWithoutStartingWhenRunning() {
        let runner = ScriptedRunner(outputs: [serviceURL])
        let url = OpenCodeServiceLocator.discover(runner: runner, executable: executable, environment: [:])
        #expect(url?.absoluteString == serviceURL)
        #expect(runner.arguments == [OpenCodeServiceLocator.statusArguments])
    }

    @Test func discoverStartsTheServiceWhenStatusIsEmpty() {
        let runner = ScriptedRunner(outputs: ["", "", serviceURL])
        let url = OpenCodeServiceLocator.discover(runner: runner, executable: executable, environment: [:])
        #expect(url?.absoluteString == serviceURL)
        #expect(runner.arguments == [
            OpenCodeServiceLocator.statusArguments,
            OpenCodeServiceLocator.startArguments,
            OpenCodeServiceLocator.statusArguments,
        ])
    }

    @Test func discoverReturnsNilWhenTheServiceStaysDown() {
        let runner = ScriptedRunner(outputs: ["", "", ""])
        #expect(OpenCodeServiceLocator.discover(runner: runner, executable: executable, environment: [:]) == nil)
    }
}

private final class ScriptedRunner: CommandRunning, @unchecked Sendable {
    private var outputs: [String]
    private(set) var arguments: [[String]] = []

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        self.arguments.append(arguments)
        let stdout = outputs.isEmpty ? "" : outputs.removeFirst()
        return CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}
