import SwiftUI

private let paletteWidth: CGFloat = 560
private let paletteListMaxHeight: CGFloat = 400
private let palettePadding: CGFloat = 12
private let paletteRowSpacing: CGFloat = 2
private let paletteRowPadding: CGFloat = 8
private let paletteRowCornerRadius: CGFloat = 6
private let paletteSelectionOpacity = 0.2

struct CommandPaletteView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var results: [CommandPaletteItem] {
        CommandPaletteSearch.results(query: query, projects: environment.board.projects, tasks: environment.board.tasks)
    }

    var body: some View {
        let results = results
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: palettePadding) {
                InsetTextField(placeholder: "Search projects and tasks", text: $query)
                    .focused($isFieldFocused)
                    .accessibilityIdentifier(AccessibilityID.commandPaletteField)

                if results.isEmpty {
                    Text("No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: paletteRowSpacing) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == selectedIndex)
                            }
                        }
                    }
                    .frame(maxHeight: paletteListMaxHeight)
                }

                HStack {
                    Text("Enter opens, Esc closes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.sheetCancel)
                }
            }
            .padding(palettePadding)
            .frame(width: paletteWidth)
            // These are local handlers inside the sheet, not app shortcuts.
            .onKeyPress(.downArrow) { move(by: 1, in: results, proxy: proxy) }
            .onKeyPress(.upArrow) { move(by: -1, in: results, proxy: proxy) }
            .onKeyPress(.return) {
                guard results.indices.contains(selectedIndex) else { return .ignored }
                environment.open(results[selectedIndex])
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
        .onChange(of: query) { selectedIndex = 0 }
        .onAppear { isFieldFocused = true }
    }

    private func row(_ item: CommandPaletteItem, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: paletteRowSpacing) {
            Label(item.title, systemImage: item.systemImage)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(paletteRowPadding)
        .background(
            RoundedRectangle(cornerRadius: paletteRowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(paletteSelectionOpacity) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { environment.open(item) }
        .id(item.id)
        .accessibilityIdentifier(AccessibilityID.commandPaletteRow(item.id))
    }

    private func move(by delta: Int, in results: [CommandPaletteItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
        proxy.scrollTo(results[selectedIndex].id)
        return .handled
    }
}
