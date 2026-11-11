import AppKit
import SwiftUI

private let userBubbleWidthFraction: CGFloat = 0.75
private let userBubbleVerticalPadding: CGFloat = 10
private let userBubbleHorizontalPadding: CGFloat = 14
private let userBubbleCornerRadius: CGFloat = 12
private let userBubbleFillOpacity = 0.12
private let userBubbleCaptionSpacing: CGFloat = 4
private let blockSpacing: CGFloat = 8
private let listItemSpacing: CGFloat = 4
private let listMarkerSpacing: CGFloat = 6
private let listBulletMarker = "\u{2022}"
private let listOrdinalSuffix = "."
private let listMarkerMinWidth: CGFloat = 16
private let listMarkerDigitWidth: CGFloat = 8
private let listMarkerPeriodWidth: CGFloat = 4
private let headingTopSpacing: CGFloat = 4
private let toolLineSpacing: CGFloat = 6
private let toolDetailSpacing: CGFloat = 4
private let toolDetailTitleSpacing: CGFloat = 2
private let toolDetailLineLimit = 40
private let toolSystemImage = "wrench.and.screwdriver"
private let toolFailedLabel = "Failed"
private let toolArgumentsLabel = "Arguments"
private let toolResultLabel = "Result"
private let thinkingTitle = "Thinking"
private let compactionFallback = "Context compacted"
private let compactionSystemImage = "arrow.triangle.2.circlepath"
private let noticeSystemImage = "info.circle"
private let streamingCursor = "\u{258D}"
private let codeCornerRadius: CGFloat = 8
private let codePadding: CGFloat = 10
private let codeCopyPadding: CGFloat = 6
private let codeCopySystemImage = "doc.on.doc"
private let codeCopyHelp = "Copy code"

/// One timeline entry; the spacing between rows is decided by `ConversationTimelineLayout`.
struct ConversationItemRow: View {
    let item: ConversationItem
    let thinkingDisplay: ChatThinkingDisplay
    let showsToolDetails: Bool
    let columnWidth: CGFloat

    var body: some View {
        switch item.kind {
        case .user(let text, let imageCount):
            userRow(text: text, imageCount: imageCount)
        case .assistant(let text):
            AssistantMarkdownView(text: text, isStreaming: item.isStreaming)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking(let text):
            if thinkingDisplay != .hidden {
                ThinkingBlock(text: text, display: thinkingDisplay)
            }
        case .toolCall(let call):
            toolRow(call)
        case .compaction(let summary):
            secondaryLabel(summary ?? compactionFallback, systemImage: compactionSystemImage)
        case .notice(let text):
            secondaryLabel(text, systemImage: noticeSystemImage)
        }
    }

    private func userRow(text: String, imageCount: Int) -> some View {
        VStack(alignment: .trailing, spacing: userBubbleCaptionSpacing) {
            Text(text)
                .textSelection(.enabled)
                .padding(.vertical, userBubbleVerticalPadding)
                .padding(.horizontal, userBubbleHorizontalPadding)
                .background(.tint.opacity(userBubbleFillOpacity), in: RoundedRectangle(cornerRadius: userBubbleCornerRadius, style: .continuous))
            if imageCount > 0 {
                Text("^[\(imageCount) image](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: columnWidth * userBubbleWidthFraction, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func toolRow(_ call: ToolCallItem) -> some View {
        if showsToolDetails {
            DisclosureGroup {
                toolDetails(call)
            } label: {
                toolLine(call)
            }
        } else {
            toolLine(call)
        }
    }

    private func toolLine(_ call: ToolCallItem) -> some View {
        HStack(spacing: toolLineSpacing) {
            Image(systemName: toolSystemImage)
            Text(call.name)
                .font(.callout.monospaced())
            if let summary = ToolCallSummary.argumentSummary(json: call.argumentsJSON) {
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            switch call.status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .finished:
                if call.isError {
                    Text(toolFailedLabel)
                        .foregroundStyle(.red)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func toolDetails(_ call: ToolCallItem) -> some View {
        VStack(alignment: .leading, spacing: toolDetailSpacing) {
            detailBlock(title: toolArgumentsLabel, text: call.argumentsJSON)
            if let result = call.resultText {
                detailBlock(title: toolResultLabel, text: result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: toolDetailTitleSpacing) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.monospaced())
                .lineLimit(toolDetailLineLimit)
                .textSelection(.enabled)
        }
    }

    private func secondaryLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantMarkdownView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        let blocks = MarkdownBlocks.split(text)
        VStack(alignment: .leading, spacing: blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isLast = index == blocks.count - 1
                switch block {
                case .paragraph(let paragraph):
                    Text(paragraphText(paragraph, appendsCursor: isStreaming && isLast))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .heading(let level, let title):
                    Text(paragraphText(title, appendsCursor: isStreaming && isLast))
                        .font(headingFont(level))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, headingTopSpacing)
                case .list(let items):
                    listView(items, appendsCursor: isStreaming && isLast)
                case .code(_, let code):
                    CodeBlockView(code: code)
                    if isStreaming && isLast {
                        Text(streamingCursor)
                    }
                }
            }
            if isStreaming && blocks.isEmpty {
                Text(streamingCursor)
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case MarkdownBlocks.headlineLevel: .title3.bold()
        case MarkdownBlocks.subheadlineLevel: .headline
        default: .body.bold()
        }
    }

    private func listMarkerWidth(_ items: [MarkdownBlocks.ListItem]) -> CGFloat {
        guard let widest = items.compactMap(\.ordinal).max() else { return listMarkerMinWidth }
        let digits = CGFloat(String(widest).count)
        return max(listMarkerMinWidth, digits * listMarkerDigitWidth + listMarkerPeriodWidth)
    }

    private func listView(_ items: [MarkdownBlocks.ListItem], appendsCursor: Bool) -> some View {
        let markerWidth = listMarkerWidth(items)
        return VStack(alignment: .leading, spacing: listItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: listMarkerSpacing) {
                    Text(item.ordinal.map { "\($0)\(listOrdinalSuffix)" } ?? listBulletMarker)
                        .monospacedDigit()
                        .frame(width: markerWidth, alignment: .trailing)
                    Text(paragraphText(item.text, appendsCursor: appendsCursor && index == items.count - 1))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func paragraphText(_ paragraph: String, appendsCursor: Bool) -> AttributedString {
        var result = (try? AttributedString(
            markdown: paragraph,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(paragraph)
        if appendsCursor { result += AttributedString(streamingCursor) }
        return result
    }
}

private struct CodeBlockView: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .padding(codePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: codeCornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: codeCopySystemImage)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(codeCopyPadding)
                .help(codeCopyHelp)
                .accessibilityLabel(codeCopyHelp)
                .accessibilityIdentifier(AccessibilityID.chatCodeCopy)
            }
    }
}

// Owns its expansion so a streaming update of the text does not fold a block the user opened.
private struct ThinkingBlock: View {
    let text: String
    let display: ChatThinkingDisplay
    @State private var isExpanded: Bool

    init(text: String, display: ChatThinkingDisplay) {
        self.text = text
        self.display = display
        _isExpanded = State(initialValue: display == .expanded)
    }

    var body: some View {
        DisclosureGroup(thinkingTitle, isExpanded: $isExpanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .onChange(of: display) { _, newValue in
            isExpanded = newValue == .expanded
        }
    }
}
