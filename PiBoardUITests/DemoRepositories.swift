import Foundation

// Git repos behind the sample projects for the README shots; git runs without the developer's config, hooks or signing.
enum DemoRepositories {
    // The /usr/bin/git xcrun shim refuses to run in the UI test sandbox, so make passes the real binary.
    private static let gitEnvironmentKey = "PIBOARD_GIT"
    private static let fallbackGit = "/Library/Developer/CommandLineTools/usr/bin/git"
    private static let homeKey = "HOME"
    private static let noSystemConfigKey = "GIT_CONFIG_NOSYSTEM"
    private static let noSystemConfigValue = "1"
    private static let pathKey = "PATH"
    private static let minimalPath = "/usr/bin:/bin"
    private static var git: URL {
        let configured = ProcessInfo.processInfo.environment[gitEnvironmentKey].flatMap { $0.isEmpty ? nil : $0 }
        return URL(fileURLWithPath: configured ?? fallbackGit)
    }
    private static let branch = "main"
    private static let identity = ["-c", "user.name=PiBoard Demo", "-c", "user.email=demo@example.com", "-c", "commit.gpgsign=false"]
    private static let initialCommitMessage = "Initial commit"

    private struct Repository {
        let folder: String
        let committed: [String: String]
        // Applied after the commit, so they show up as uncommitted changes.
        let changed: [String: String]
    }

    // Folder names must match TestingConfiguration.projectFolder(named:) for the sample projects.
    private static let repositories = [
        Repository(
            folder: "my-app",
            committed: [
                "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"MyApp\")\n",
                "Sources/App/Network/APIClient.swift": "import Foundation\n\nfinal class APIClient {\n    func send(_ request: URLRequest) async throws -> Data {\n        try await URLSession.shared.data(for: request).0\n    }\n}\n",
                "Sources/App/Network/Endpoint.swift": "struct Endpoint {\n    let path: String\n}\n",
            ],
            // New files go into folders that are already tracked: git status folds an untracked folder into one line.
            changed: [
                "Sources/App/Network/APIClient.swift": "import Foundation\n\nfinal class APIClient {\n    private let http: HTTPClient\n\n    init(http: HTTPClient) {\n        self.http = http\n    }\n}\n",
                "Sources/App/Network/HTTPClient.swift": "import Foundation\n\nprotocol HTTPClient: Sendable {\n    func send(_ request: URLRequest) async throws -> Data\n}\n",
                "Sources/App/Network/Endpoint.swift": "struct Endpoint: Sendable {\n    let path: String\n    let method: String\n}\n",
            ]
        ),
        Repository(
            folder: "website",
            committed: [
                "index.html": "<!doctype html>\n<nav class=\"menu\">Home About Blog Contact</nav>\n",
                "styles.css": ".menu { display: flex; }\n",
            ],
            changed: [
                "styles.css": ".menu { display: flex; flex-wrap: wrap; }\n",
            ]
        ),
    ]

    static func create(in projectsDirectory: URL, home: URL) throws {
        for repository in repositories {
            let folder = projectsDirectory.appendingPathComponent(repository.folder, isDirectory: true)
            try write(repository.committed, in: folder)
            try run(["init", "-q", "-b", branch], in: folder, home: home)
            try run(["add", "-A"], in: folder, home: home)
            try run(identity + ["commit", "-q", "-m", initialCommitMessage], in: folder, home: home)
            try write(repository.changed, in: folder)
        }
    }

    private static func write(_ files: [String: String], in folder: URL) throws {
        for (relativePath, contents) in files {
            let file = folder.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private static func run(_ arguments: [String], in folder: URL, home: URL) throws {
        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", folder.path] + arguments
        process.environment = [homeKey: home.path, noSystemConfigKey: noSystemConfigValue, pathKey: minimalPath]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed in \(folder.path)"])
        }
    }
}
