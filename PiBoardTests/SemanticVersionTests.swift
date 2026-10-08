import Testing
@testable import PiBoard

struct SemanticVersionTests {
    @Test func parsesCoreAndPreRelease() throws {
        let version = try #require(SemanticVersion("1.2.3-beta.4"))
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
        #expect(version.preRelease == ["beta", "4"])
    }

    @Test func ordersNumericallyNotLexically() throws {
        let lower = try #require(SemanticVersion("1.9.0"))
        let higher = try #require(SemanticVersion("1.10.0"))
        #expect(lower < higher)
        #expect(try #require(SemanticVersion("2.0.0")) > higher)
        #expect(try #require(SemanticVersion("1.10.1")) > higher)
    }

    @Test func preReleaseIsLowerThanRelease() throws {
        let preRelease = try #require(SemanticVersion("1.0.0-rc.1"))
        let release = try #require(SemanticVersion("1.0.0"))
        #expect(preRelease < release)
        #expect(!(release < preRelease))
    }

    @Test func preReleaseIdentifiersFollowSemverPrecedence() throws {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        let versions = try ordered.map { try #require(SemanticVersion($0)) }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            #expect(lower < higher)
        }
    }

    @Test func buildMetadataIsIgnored() throws {
        let withMetadata = try #require(SemanticVersion("1.0.0+build.5"))
        let plain = try #require(SemanticVersion("1.0.0"))
        #expect(withMetadata == plain)
    }

    @Test(arguments: ["", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "1..3", "-1.2.3", "1.2.3-", "1.2.3-beta..1", "v1.2.3", "1.2.3-be_ta", ".."])
    func rejectsInvalidStrings(_ string: String) {
        #expect(SemanticVersion(string) == nil)
    }
}
