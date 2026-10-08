import Foundation

struct PiLaunchCommand: Equatable, Sendable {
    private static let sessionIDFlag = "--session-id"
    private static let sessionFlag = "--session"
    private static let nameFlag = "--name"
    private static let printFlag = "--print"
    private static let noToolsFlag = "--no-tools"
    private static let noExtensionsFlag = "--no-extensions"
    private static let noSkillsFlag = "--no-skills"
    private static let noContextFilesFlag = "--no-context-files"
    private static let noSessionFlag = "--no-session"
    private static let modelFlag = "--model"
    private static let extensionFlag = "--extension"
    private static let thinkingFlag = "--thinking"
    private static let thinkingOff = "off"
    private static let systemPromptFlag = "--system-prompt"
    private static let endOfOptions = "--"

    enum Mode: Equatable {
        case newSession(sessionID: UUID, name: String?, initialPrompt: String?)
        case resume(sessionID: UUID)
        /// One-shot, non-interactive run with every way of touching the project switched off.
        case headless(prompt: String, systemPrompt: String, model: String?, extensions: [String])
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
                // A prompt that starts with "-" would otherwise be read as an option.
                arguments.append(endOfOptions)
                arguments.append(initialPrompt)
            }
        case .resume(let sessionID):
            arguments.append(sessionFlag)
            arguments.append(sessionID.uuidString)
        case .headless(let prompt, let systemPrompt, let model, let extensions):
            arguments.append(contentsOf: [
                printFlag,
                noToolsFlag,
                noExtensionsFlag,
                noSkillsFlag,
                noContextFilesFlag,
                noSessionFlag,
            ])
            // Pi loads explicit --extension paths even with --no-extensions.
            for path in extensions {
                arguments.append(extensionFlag)
                arguments.append(path)
            }
            // A commit message needs no reasoning pass; thinking was most of the wall time.
            arguments.append(contentsOf: [thinkingFlag, thinkingOff])
            if let model {
                arguments.append(modelFlag)
                arguments.append(model)
            }
            arguments.append(contentsOf: [
                systemPromptFlag,
                systemPrompt,
                endOfOptions,
                prompt,
            ])
        }

        return PiLaunchCommand(executable: node, arguments: arguments, currentDirectory: cwd)
    }
}
