import Foundation
import Testing
@testable import PiBoard

struct GitRemoteURLTests {
    private func browse(_ remote: String) -> String? {
        GitRemoteURL.browseURL(for: remote)?.absoluteString
    }

    @Test func scpStyleRemotesBecomeHTTPS() {
        #expect(browse("git@github.com:owner/repo.git") == "https://github.com/owner/repo")
        #expect(browse("git@bitbucket.org:team/repo.git") == "https://bitbucket.org/team/repo")
        // Cloning without the suffix is equally common.
        #expect(browse("git@github.com:owner/repo") == "https://github.com/owner/repo")
    }

    @Test func sshRemotesBecomeHTTPS() {
        #expect(browse("ssh://git@github.com/owner/repo.git") == "https://github.com/owner/repo")
        #expect(browse("git://github.com/owner/repo.git") == "https://github.com/owner/repo")
    }

    // The port serves the Git transport; the web interface is not on it.
    @Test func theTransportPortIsDropped() {
        #expect(browse("ssh://git@git.example.com:7999/proj/repo.git") == "https://git.example.com/proj/repo")
    }

    @Test func credentialsNeverSurviveIntoTheBrowsedURL() {
        #expect(browse("https://someone@bitbucket.org/team/repo.git") == "https://bitbucket.org/team/repo")
        #expect(browse("https://someone:token@github.com/owner/repo.git") == "https://github.com/owner/repo")
    }

    // An internal server may not serve HTTPS at all, so a browsable scheme is kept as it is.
    @Test func existingHTTPSchemeIsKept() {
        #expect(browse("http://git.internal/team/repo.git") == "http://git.internal/team/repo")
        #expect(browse("https://github.com/owner/repo.git") == "https://github.com/owner/repo")
    }

    @Test func nestedPathsOfSelfHostedForgesSurvive() {
        #expect(browse("git@gitlab.example.com:group/subgroup/repo.git") == "https://gitlab.example.com/group/subgroup/repo")
    }

    @Test func trailingSlashesAreTrimmed() {
        #expect(browse("https://github.com/owner/repo.git/") == "https://github.com/owner/repo")
        #expect(browse("  git@github.com:owner/repo.git  ") == "https://github.com/owner/repo")
    }

    @Test func remotesWithNothingToBrowseAreRefused() {
        for remote in ["", "   ", "/Users/x/mirrors/repo.git", "../sibling", "file:///Users/x/repo.git", "https://github.com", "https://github.com/"] {
            #expect(GitRemoteURL.browseURL(for: remote) == nil, "\(remote)")
        }
    }
}
