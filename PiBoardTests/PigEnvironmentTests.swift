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
    private let pigActive = (version: "0.5.3", entry: URL(fileURLWithPath: "/usr/local/bin/pig"))

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

    @Test func pigLauncherRunsTheBinaryWithTheSharedEnvironment() {
        let node = node
        let pigActive = pigActive

        let resolved = PiEngineLaunch.pig(active: pigActive, node: node, baseEnvironment: ["PATH": "/usr/bin"])

        let expected = PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: ["PATH": "/usr/bin"])
        #expect(resolved.version == pigActive.version)
        #expect(resolved.launcher == .native(executable: pigActive.entry, environment: expected))
    }
}
