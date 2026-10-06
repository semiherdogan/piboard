import Foundation
@testable import PiBoard

/// Throwaway repository under the system temp directory; never touches the PiBoard checkout.
struct GitTestRepository {
    static let initialBranch = "main"
    static let trackedFileName = "README.md"

    let url: URL

    static var isGitAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: GitCommandRunner.defaultExecutable.path)
    }

    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectPathService.canonicalize(url)
    }

    /// Initializes a repository with one commit on `initialBranch`.
    static func make() throws -> GitTestRepository {
        let repository = GitTestRepository(url: try makeTempDirectory())
        try repository.git("init", "-q", "-b", initialBranch)
        try repository.write("hello\n", to: trackedFileName)
        try repository.git("add", trackedFileName)
        try repository.commit("initial")
        return repository
    }

    func write(_ contents: String, to fileName: String) throws {
        try Data(contents.utf8).write(to: url.appendingPathComponent(fileName))
    }

    func commit(_ message: String) throws {
        // Identity, signing and hooks are pinned so the user's global config cannot break the fixture.
        try git(
            "-c", "user.name=PiBoard Tests",
            "-c", "user.email=tests@piboard.invalid",
            "-c", "commit.gpgsign=false",
            "commit", "-q", "--no-verify", "-m", message
        )
    }

    func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = GitCommandRunner.defaultExecutable
        process.arguments = ["-C", url.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitServiceError.commandFailed(code: process.terminationStatus, stderr: arguments.joined(separator: " "))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
