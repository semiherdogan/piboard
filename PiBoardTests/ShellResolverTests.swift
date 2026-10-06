import Testing
@testable import PiBoard

struct ShellResolverTests {
    @Test func execNameAddsLeadingDash() {
        #expect(ShellResolver.loginExecName(for: "/bin/zsh") == "-zsh")
    }

    @Test func loginShellReturnsNonEmptyAbsolutePath() {
        let shell = ShellResolver.loginShell()
        #expect(!shell.isEmpty)
        #expect(shell.hasPrefix("/"))
    }
}
