import Foundation

struct PiLaunchCommand: Equatable {
    private static let sessionIDFlag = "--session-id"
    private static let sessionFlag = "--session"
    private static let nameFlag = "--name"

    enum Mode: Equatable {
        case newSession(sessionID: UUID, name: String?, initialPrompt: String?)
        case resume(sessionID: UUID)
    }

    let executable: URL
    let arguments: [String]
    let currentDirectory: URL

    static func build(node: URL, piEntry: URL, mode: Mode, cwd: URL) -> PiLaunchCommand {
        var arguments = [piEntry.path]

        switch mode {
        case .newSession(let sessionID, let name, let initialPrompt):
            arguments.append(sessionIDFlag)
            arguments.append(sessionID.uuidString)
            if let name {
                arguments.append(nameFlag)
                arguments.append(name)
            }
            if let initialPrompt {
                arguments.append(initialPrompt)
            }
        case .resume(let sessionID):
            arguments.append(sessionFlag)
            arguments.append(sessionID.uuidString)
        }

        return PiLaunchCommand(executable: node, arguments: arguments, currentDirectory: cwd)
    }
}
