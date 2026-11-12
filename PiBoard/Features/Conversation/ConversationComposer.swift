import AppKit
import SwiftUI

private let composerSpacing: CGFloat = 8
private let composerChipSpacing: CGFloat = 8
private let composerPlaceholder = "Message the agent, tag @files, or use /commands"
private let attachSystemImage = "plus"
private let attachHelp = "Attach files"
private let attachLabel = "Attach"
private let attachButtonSize: CGFloat = 24
private let attachSymbolSize: CGFloat = 13
private let removeAttachmentSystemImage = "xmark"
private let removeAttachmentLabel = "Remove attachment"
private let attachmentChipSpacing: CGFloat = 6
private let attachmentChipMaxWidth: CGFloat = 160
private let attachmentChipCornerRadius: CGFloat = 6
private let attachmentFileSystemImage = "doc"
private let attachmentImageSystemImage = "photo"
private let attachmentSymbolSize: CGFloat = 9
private let chipCornerRadius: CGFloat = 8
private let chipBorderWidth: CGFloat = 1
private let chipHorizontalPadding: CGFloat = 8
private let chipVerticalPadding: CGFloat = 4
private let chipContentSpacing: CGFloat = 4
private let chipChevronSystemImage = "chevron.down"
private let chipChevronSize: CGFloat = 8
private let modelSystemImage = "cpu"
private let thinkingSystemImage = "brain"
private let sendButtonSize: CGFloat = 28
private let sendButtonDisabledOpacity = 0.3
private let sendSystemImage = "arrow.up"
private let abortSystemImage = "stop.fill"
private let sendSymbolSize: CGFloat = 12
private let abortHelp = "Stop the current run (Escape)"
private let sendHelp = "Send (Return)"
private let queueHelp = "Queue after the current run"
private let sendLabel = "Send"
private let abortLabel = "Abort"
private let modelFallbackTitle = "Model"
private let thinkingFallbackTitle = "Thinking"
private let modelsLoadingTitle = "Loading models"
private let selectedSystemImage = "checkmark"
private let tokensSuffix = "tokens"
private let usageSeparator = " \u{B7} "
private let agentChipSeparator = " \u{B7} "
private let statusValueSeparator = "  "
private let statusMaxWidth: CGFloat = 260
private let newline = "\n"
private let queuedTitle = "Queued"
private let queuedChipSpacing: CGFloat = 6
private let queuedChipMaxWidth: CGFloat = 220
private let queuedChipCornerRadius: CGFloat = 6
private let unknownCommandMessage = "Not a chat command. It will be sent to the model as text."
private let sendAnywayTitle = "Send Anyway"
private let warningSpacing: CGFloat = 8
private let warningSystemImage = "exclamationmark.triangle.fill"

/// Messages sent during a run that the agent has not picked up yet.
struct QueuedMessagesRow: View {
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: queuedChipSpacing) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        HStack(spacing: chipContentSpacing) {
                            Text(queuedTitle)
                                .fontWeight(.semibold)
                            Text(message)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, chipHorizontalPadding)
                        .padding(.vertical, chipVerticalPadding)
                        .frame(maxWidth: queuedChipMaxWidth)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: queuedChipCornerRadius, style: .continuous))
                        .accessibilityIdentifier("\(AccessibilityID.chatQueuedPrefix)\(index)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact card input: Return sends, Shift+Return adds a line, a send during a run is queued.
struct ConversationComposer: View {
    let session: ConversationSession
    let agent: AgentKind
    @Binding var attachments: [ChatAttachment]
    @Binding var attachmentError: String?
    @State private var text = ""
    @State private var models: [ConversationModel] = []
    @State private var hasRequestedModels = false
    @State private var commandSelection = 0
    @State private var isCommandListDismissed = false
    // The message the unknown-command warning was shown for; editing it hides the warning again.
    @State private var warnedText: String?
    // Monotonic so a removed attachment never makes the next pasted image reuse its name.
    @State private var pastedImageCounter = PastedImageCounter()
    @State private var focusToken = 0

    private var isRunning: Bool { session.liveStatus.isRunning }
    private var isEnabled: Bool { session.runtimeState.isRunning }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasContent: Bool { !trimmedText.isEmpty || !attachments.isEmpty }
    private var canSend: Bool { isEnabled && hasContent }
    private var slashFragment: String? { SlashCommands.fragment(in: text) }
    private var commandMatches: [ConversationCommand] {
        slashFragment.map { SlashCommands.matches(for: $0, in: session.commands) } ?? []
    }
    private var isCommandListOpen: Bool { isEnabled && !isCommandListDismissed && !commandMatches.isEmpty }
    private var unknownCommand: String? { SlashCommands.unknownCommand(in: trimmedText, known: session.commands) }
    private var showsUnknownCommandWarning: Bool { unknownCommand != nil && warnedText == trimmedText }

    var body: some View {
        VStack(alignment: .leading, spacing: composerSpacing) {
            if !attachments.isEmpty {
                attachmentRow
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityID.chatAttachmentError)
            }
            if isCommandListOpen {
                ConversationCommandList(commands: commandMatches, selection: selectedCommandIndex, onPick: insert)
            }
            ComposerTextView(
                text: $text,
                placeholder: composerPlaceholder,
                isEnabled: isEnabled,
                focusToken: focusToken,
                accessibilityID: AccessibilityID.chatComposer,
                onCommand: handle,
                onPasteAttachment: paste
            )
            if showsUnknownCommandWarning {
                unknownCommandRow
            }
            // The extension status goes first when the row runs out of width, then the usage caption.
            ViewThatFits(in: .horizontal) {
                bottomRow(showsUsage: true, showsStatus: true)
                bottomRow(showsUsage: true, showsStatus: false)
                bottomRow(showsUsage: false, showsStatus: false)
            }
        }
        .conversationCard()
        .onChange(of: text) {
            commandSelection = 0
            isCommandListDismissed = false
        }
        .onChange(of: slashFragment != nil) { _, isTypingCommand in
            guard isTypingCommand else { return }
            Task { await session.refreshCommandsIfEmpty() }
        }
    }

    private var unknownCommandRow: some View {
        HStack(spacing: warningSpacing) {
            Label(unknownCommandMessage, systemImage: warningSystemImage)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityID.chatCommandWarning)
            Button(sendAnywayTitle) { send(anyway: true) }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier(AccessibilityID.chatSendAnyway)
            Spacer(minLength: 0)
        }
    }

    private var selectedCommandIndex: Int {
        min(commandSelection, max(commandMatches.count - 1, 0))
    }

    private func insert(_ command: ConversationCommand) {
        text = SlashCommands.insertion(for: command)
        focusToken += 1
    }

    private func insertSelectedCommand() {
        let matches = commandMatches
        guard matches.indices.contains(selectedCommandIndex) else { return }
        insert(matches[selectedCommandIndex])
    }

    private func moveCommandSelection(by step: Int) -> Bool {
        guard isCommandListOpen else { return false }
        commandSelection = min(max(selectedCommandIndex + step, 0), commandMatches.count - 1)
        return true
    }

    private var isExactCommand: Bool {
        SlashCommands.isExact(fragment: slashFragment, in: session.commands)
    }

    private func handle(_ command: ComposerTextView.Command) -> Bool {
        switch command {
        case .submit:
            if isCommandListOpen, !isExactCommand {
                insertSelectedCommand()
            } else {
                send()
            }
            return true
        case .complete:
            guard isCommandListOpen else { return false }
            insertSelectedCommand()
            return true
        case .moveUp:
            return moveCommandSelection(by: -1)
        case .moveDown:
            return moveCommandSelection(by: 1)
        case .cancel:
            if isCommandListOpen {
                isCommandListDismissed = true
                return true
            }
            // Handled even when idle: the text view's default opens word completion.
            guard isRunning else { return true }
            Task { await session.abort() }
            return true
        }
    }

    // Reads the pasteboard the text view hands over so files and images share one tested path.
    private func paste(_ pasteboard: NSPasteboard) {
        guard isEnabled else { return }
        let content = ChatAttachment.pasteContent(from: pasteboard)
        let number = content.isImage ? pastedImageCounter.next() : pastedImageCounter.value
        Task { await ChatAttachment.addPasted(content, number: number, to: $attachments, error: $attachmentError) }
    }

    private var statusText: String? {
        let statuses = session.liveStatus.statuses
        guard !statuses.isEmpty else { return nil }
        return statuses.keys.sorted().compactMap { statuses[$0] }.joined(separator: statusValueSeparator)
    }

    private func bottomRow(showsUsage: Bool, showsStatus: Bool) -> some View {
        HStack(spacing: composerChipSpacing) {
            if isEnabled {
                AgentStatusIndicator(kind: statusKind)
            }
            attachButton
            if showsUsage, let usage = usageText {
                Text(usage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            if showsStatus, let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: statusMaxWidth)
                    .accessibilityIdentifier(AccessibilityID.chatExtensionStatus)
            }
            agentChip
            modelChip
            if !session.thinkingLevels.isEmpty {
                thinkingChip
            }
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            }
            actionButtons
        }
    }

    private var statusKind: AgentStatusIndicator.Kind {
        switch session.liveStatus.agentActivity {
        case .working: .working
        case .idle: .idle
        case .needsInput: .needsInput
        }
    }

    private var agentChipTitle: String {
        guard let name = session.liveStatus.activeAgentName else { return agent.shortTitle }
        return agent.shortTitle + agentChipSeparator + name
    }

    private var agentChip: some View {
        HStack(spacing: chipContentSpacing) {
            Image(systemName: agent.systemImage)
            Text(agentChipTitle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .overlay(
            RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: chipBorderWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.chatAgentChip)
    }

    private var attachButton: some View {
        Button(action: chooseFiles) {
            Image(systemName: attachSystemImage)
                .font(.system(size: attachSymbolSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: attachButtonSize, height: attachButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(attachHelp)
        .accessibilityLabel(attachLabel)
        .accessibilityIdentifier(AccessibilityID.chatAttach)
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: attachmentChipSpacing) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    attachmentChip(attachment, index: index)
                }
            }
        }
    }

    private func attachmentChip(_ attachment: ChatAttachment, index: Int) -> some View {
        HStack(spacing: chipContentSpacing) {
            switch attachment.source {
            case .file: Image(systemName: attachmentFileSystemImage)
            case .image: Image(systemName: attachmentImageSystemImage)
            }
            Text(attachment.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                attachments.removeAll { $0.id == attachment.id }
                attachmentError = nil
            } label: {
                Image(systemName: removeAttachmentSystemImage)
                    .font(.system(size: attachmentSymbolSize, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeAttachmentLabel)
            .accessibilityIdentifier("\(AccessibilityID.chatAttachmentPrefix)\(index)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .frame(maxWidth: attachmentChipMaxWidth)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: attachmentChipCornerRadius, style: .continuous))
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { await ChatAttachment.add(urls, to: $attachments, error: $attachmentError) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            panel.begin(completionHandler: handle)
        }
    }

    private var modelChip: some View {
        Menu {
            if models.isEmpty {
                Text(modelsLoadingTitle)
            }
            ForEach(providerGroups, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.models, id: \.id) { model in
                        Button {
                            Task { await session.setModel(provider: model.provider, modelID: model.id) }
                        } label: {
                            if isCurrent(model) {
                                Label(model.name, systemImage: selectedSystemImage)
                            } else {
                                Text(model.name)
                            }
                        }
                    }
                }
            }
        } label: {
            chipLabel(session.info?.modelID ?? modelFallbackTitle, systemImage: modelSystemImage)
        }
        .chipStyle()
        // The menu offers no open callback; the first hover or press is the earliest signal before it opens.
        .onHover { if $0 { loadModelsIfNeeded() } }
        .simultaneousGesture(TapGesture().onEnded { loadModelsIfNeeded() })
        .accessibilityIdentifier(AccessibilityID.chatModelPicker)
    }

    private var thinkingChip: some View {
        Menu {
            ForEach(session.thinkingLevels, id: \.self) { level in
                Button(level.capitalized) {
                    Task { await session.setThinkingLevel(level) }
                }
            }
        } label: {
            chipLabel(session.liveStatus.thinkingLevel?.capitalized ?? thinkingFallbackTitle, systemImage: thinkingSystemImage)
        }
        .chipStyle()
        .accessibilityIdentifier(AccessibilityID.chatThinkingPicker)
    }

    private func chipLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: chipContentSpacing) {
            Image(systemName: systemImage)
            Text(title)
            Image(systemName: chipChevronSystemImage)
                .font(.system(size: chipChevronSize, weight: .semibold))
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .overlay(
            RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: chipBorderWidth)
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isRunning {
            Button {
                Task { await session.abort() }
            } label: {
                circle(systemImage: abortSystemImage, fill: AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(abortHelp)
            .accessibilityLabel(abortLabel)
            .accessibilityIdentifier(AccessibilityID.chatAbort)
            if hasContent {
                sendButton(help: queueHelp)
            }
        } else {
            sendButton(help: sendHelp)
        }
    }

    private func sendButton(help: String) -> some View {
        Button { send() } label: {
            circle(systemImage: sendSystemImage, fill: AnyShapeStyle(Color.accentColor.opacity(canSend ? 1 : sendButtonDisabledOpacity)))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(help)
        .accessibilityLabel(sendLabel)
        .accessibilityIdentifier(AccessibilityID.chatSend)
    }

    private func circle(systemImage: String, fill: AnyShapeStyle) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: sendSymbolSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: sendButtonSize, height: sendButtonSize)
            .background(fill, in: Circle())
    }

    private var providerGroups: [(provider: String, models: [ConversationModel])] {
        var order: [String] = []
        var grouped: [String: [ConversationModel]] = [:]
        for model in models {
            if grouped[model.provider] == nil { order.append(model.provider) }
            grouped[model.provider, default: []].append(model)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func isCurrent(_ model: ConversationModel) -> Bool {
        model.id == session.info?.modelID && model.provider == session.info?.provider
    }

    private func loadModelsIfNeeded() {
        guard !hasRequestedModels, isEnabled else { return }
        hasRequestedModels = true
        Task {
            models = await session.availableModels()
            // A failed fetch comes back empty; allow another try on the next open.
            hasRequestedModels = !models.isEmpty
        }
    }

    private var usageText: String? {
        let usage = session.liveStatus.usage
        guard usage.total > 0 else { return nil }
        var parts = ["\(SessionSummaryPresentation.compact(usage.total)) \(tokensSuffix)"]
        if usage.cost > 0 { parts.append(SessionSummaryPresentation.cost(usage.cost)) }
        return parts.joined(separator: usageSeparator)
    }

    private func send(anyway: Bool = false) {
        guard canSend else { return }
        if !anyway, unknownCommand != nil, warnedText != trimmedText {
            warnedText = trimmedText
            return
        }
        warnedText = nil
        let payload = ChatAttachment.payload(text: trimmedText, attachments: attachments)
        let sentText = text
        let sentAttachments = attachments
        text = ""
        attachments = []
        attachmentError = nil
        Task {
            let delivered = await session.send(payload.text, images: payload.images, whileRunning: .followUp)
            guard !delivered else { return }
            // Keep anything typed in the meantime after the restored message.
            text = text.isEmpty ? sentText : sentText + newline + text
            attachments = sentAttachments + attachments
        }
    }
}

private extension View {
    func chipStyle() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
