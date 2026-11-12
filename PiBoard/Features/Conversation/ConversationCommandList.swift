import SwiftUI

private let commandRowHeight: CGFloat = 26
private let commandMaxVisibleRows = 8
private let commandRowSpacing: CGFloat = 8
private let commandRowHorizontalPadding: CGFloat = 8
private let commandRowCornerRadius: CGFloat = 6
private let commandSelectedOpacity = 0.15
private let commandNamePrefix = "/"

/// The `/command` suggestions above the composer field; the composer owns the keys and the selection.
struct ConversationCommandList: View {
    let commands: [ConversationCommand]
    let selection: Int
    let onPick: (ConversationCommand) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                        row(command, index: index)
                            .id(index)
                    }
                }
            }
            .frame(height: CGFloat(min(commands.count, commandMaxVisibleRows)) * commandRowHeight)
            .onChange(of: selection) { _, index in
                proxy.scrollTo(index)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.chatCommandList)
    }

    private func row(_ command: ConversationCommand, index: Int) -> some View {
        Button {
            onPick(command)
        } label: {
            HStack(spacing: commandRowSpacing) {
                Text("\(commandNamePrefix)\(command.name)")
                    .font(.body.monospaced())
                    .lineLimit(1)
                if let description = command.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if !command.source.isEmpty {
                    Text(command.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, commandRowHorizontalPadding)
            .frame(height: commandRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                index == selection ? Color.accentColor.opacity(commandSelectedOpacity) : Color.clear,
                in: RoundedRectangle(cornerRadius: commandRowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(AccessibilityID.chatCommandRowPrefix)\(index)")
    }
}
