import Foundation
import Testing
@testable import PiBoard

@MainActor
struct PigEnvironmentTests {
    private let node = BundledNode(
        nodeExecutable: URL(fileURLWithPath: "/apps/PiBoard.app/Contents/Resources/node/bin/node"),
        npmCLI: URL(fileURLWithPath: "/apps/PiBoard.app/Contents/Resources/node/lib/npm-cli.js")
    )
    private let nodeDirectory = "/apps/PiBoard.app/Contents/Resources/node/bin"
    private let home = URL(fileURLWithPath: "/Users/someone")
    private let piActive = (version: "1.0.4", entry: URL(fileURLWithPath: "/support/pi/cli.js"))
    private let pigActive = (version: "0.5.3", entry: URL(fileURLWithPath: "/usr/local/bin/pig"))

    private struct Unexpected: Error {}

    @Test func overridesShareThePiDirectoriesAndAppendNodeToPath() {
        let overrides = PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: ["PATH": "/usr/bin:/bin"])

        #expect(overrides[PigEnvironment.usePiDirectoriesKey] == PigEnvironment.usePiDirectoriesValue)
        #expect(overrides["PATH"] == "/usr/bin:/bin:" + nodeDirectory)
    }

    @Test func overridesUseOnlyTheNodeDirectoryWithoutABasePath() {
        #expect(PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: [:])["PATH"] == nodeDirectory)
        #expect(PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: ["PATH": ""])["PATH"] == nodeDirectory)
    }

    @Test func cacheRootDefaultsToTheHomeFolder() {
        let root = PigEnvironment.cacheRoot(environment: [:], home: home)

        #expect(root.path == "/Users/someone/.pig/cache")
    }

    @Test func cacheRootHonorsPigHome() {
        let root = PigEnvironment.cacheRoot(environment: [PigEnvironment.homeKey: "/data/pig"], home: home)

        #expect(root.path == "/data/pig/cache")
    }

    @Test func cacheRootExpandsATildeInPigHome() {
        let root = PigEnvironment.cacheRoot(environment: [PigEnvironment.homeKey: "~/custom-pig"], home: home)

        #expect(root.path == (("~/custom-pig" as NSString).expandingTildeInPath) + "/cache")
    }

    @Test func cacheRootIgnoresAnEmptyPigHome() {
        let root = PigEnvironment.cacheRoot(environment: [PigEnvironment.homeKey: ""], home: home)

        #expect(root.path == "/Users/someone/.pig/cache")
    }

    @Test func resolvingPiNeverAsksPig() throws {
        let node = node
        let piActive = piActive

        let resolved = try PiEngineLaunch.resolve(
            engine: .pi,
            pi: { piActive },
            pig: { throw Unexpected() },
            locateNode: { node },
            baseEnvironment: { [:] }
        )

        #expect(resolved.version == piActive.version)
        #expect(resolved.launcher == .node(executable: node.nodeExecutable, entry: piActive.entry))
    }

    @Test func resolvingPigNeverAsksPi() throws {
        let node = node
        let pigActive = pigActive

        let resolved = try PiEngineLaunch.resolve(
            engine: .pig,
            pi: { throw Unexpected() },
            pig: { pigActive },
            locateNode: { node },
            baseEnvironment: { ["PATH": "/usr/bin"] }
        )

        let expected = PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: ["PATH": "/usr/bin"])
        #expect(resolved.version == pigActive.version)
        #expect(resolved.launcher == .native(executable: pigActive.entry, environment: expected))
    }

    @Test func resolvingAsksTheRuntimeBeforeNode() {
        let pigActive = pigActive

        #expect(throws: PiRuntimeManagerError.noActiveVersion) {
            try PiEngineLaunch.resolve(
                engine: .pig,
                pi: { pigActive },
                pig: { throw PiRuntimeManagerError.noActiveVersion },
                locateNode: { throw Unexpected() },
                baseEnvironment: { [:] }
            )
        }
    }
}
