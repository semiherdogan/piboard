import Foundation
import Testing
@testable import PiBoard

struct PiSettingsProbeTests {
    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiSettingsProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func readsTrueFromTheTerminalSection() {
        let json = data(#"{"terminal":{"showTerminalProgress":true}}"#)
        #expect(PiSettingsProbe.showsTerminalProgress(in: json) == true)
    }

    @Test func readsFalse() {
        let json = data(#"{"terminal":{"showTerminalProgress":false}}"#)
        #expect(PiSettingsProbe.showsTerminalProgress(in: json) == false)
    }

    @Test func missingKeyIsNil() {
        #expect(PiSettingsProbe.showsTerminalProgress(in: data(#"{"terminal":{}}"#)) == nil)
        #expect(PiSettingsProbe.showsTerminalProgress(in: data("{}")) == nil)
    }

    @Test func invalidJSONIsNil() {
        #expect(PiSettingsProbe.showsTerminalProgress(in: data("not json")) == nil)
    }

    @Test func missingFileIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let probe = PiSettingsProbe(agentDirectory: directory)
        #expect(probe.showsTerminalProgress() == nil)
        #expect(probe.settingsFile.lastPathComponent == PiSettingsProbe.settingsFileName)
    }

    @Test func readsTheFileOnDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let probe = PiSettingsProbe(agentDirectory: directory)
        try data(#"{"terminal":{"showTerminalProgress":true}}"#).write(to: probe.settingsFile)
        #expect(probe.showsTerminalProgress() == true)
    }
}
