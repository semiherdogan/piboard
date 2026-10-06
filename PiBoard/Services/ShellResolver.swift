import Foundation

enum ShellResolver {
    static let defaultShell = "/bin/zsh"

    static func loginShell() -> String {
        if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty {
                return path
            }
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return defaultShell
    }

    static func loginExecName(for shellPath: String) -> String {
        "-" + (shellPath as NSString).lastPathComponent
    }
}
