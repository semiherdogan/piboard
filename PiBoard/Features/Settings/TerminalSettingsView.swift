import SwiftUI

private let systemMonospacedTitle = "System Monospaced"
private let previewLines = [
    "~/project $ pi --resume",
    "  \u{2713} 12 tests passed in 0.84s",
    "fn main() { println!(\"0O 1lI {}[]\"); }",
]
private let previewPadding: CGFloat = 10
private let previewCornerRadius: CGFloat = 6
private let fontSizeFieldWidth: CGFloat = 48
private let lineHeightFractionDigits = 2

struct TerminalSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        let appearance = TerminalAppearance.make(from: preferences)
        Form {
            Section("Font") {
                Picker("Font", selection: $preferences.terminalFontName) {
                    Text(systemMonospacedTitle).tag(TerminalFontChoice.systemMonospaced)
                    Divider()
                    ForEach(TerminalFontCatalog.monospacedFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                LabeledContent("Size") {
                    HStack {
                        TextField("Size", value: $preferences.terminalFontSize, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: fontSizeFieldWidth)
                        Stepper(
                            "Size",
                            value: $preferences.terminalFontSize,
                            in: TerminalFontChoice.sizeRange,
                            step: TerminalFontChoice.sizeStep
                        )
                        .labelsHidden()
                    }
                }
                LabeledContent("Line Height") {
                    Stepper(
                        value: $preferences.terminalLineHeightMultiplier,
                        in: TerminalLineHeight.range,
                        step: TerminalLineHeight.step
                    ) {
                        Text(
                            preferences.terminalLineHeightMultiplier,
                            format: .number.precision(.fractionLength(lineHeightFractionDigits))
                        )
                        .monospacedDigit()
                    }
                }
                preview(appearance: appearance)
            }

            Section("Cursor") {
                Picker("Style", selection: cursorShapeBinding(preferences)) {
                    ForEach(TerminalCursorShape.allCases, id: \.self) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                Toggle("Blink", isOn: cursorBlinkBinding(preferences))
            }

            Section {
                Picker("Scrollback", selection: $preferences.terminalScrollbackLines) {
                    ForEach(TerminalScrollback.choices, id: \.self) { lines in
                        Text("\(lines.formatted()) lines").tag(lines)
                    }
                }
                Text("Applies to new sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use Option as Meta", isOn: $preferences.terminalOptionAsMeta)
                Text("When off, Option types special characters instead of sending Esc-prefixed keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func preview(appearance: TerminalAppearance) -> some View {
        let font = appearance.font
        // Extra leading approximates SwiftTerm's multiplier applied to the natural line height.
        let naturalLineHeight = font.ascender - font.descender + font.leading
        return Text(previewLines.joined(separator: "\n"))
            .font(Font(font))
            .lineSpacing(naturalLineHeight * (appearance.lineSpacing - 1))
            .foregroundStyle(Color(nsColor: appearance.foreground))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(previewPadding)
            .background(Color(nsColor: appearance.background), in: RoundedRectangle(cornerRadius: previewCornerRadius))
    }

    private func cursorShapeBinding(_ preferences: AppPreferences) -> Binding<TerminalCursorShape> {
        Binding(
            get: { preferences.terminalCursorStyle.shape },
            set: { preferences.terminalCursorStyle = TerminalCursorStyleChoice(shape: $0, blinks: preferences.terminalCursorStyle.blinks) }
        )
    }

    private func cursorBlinkBinding(_ preferences: AppPreferences) -> Binding<Bool> {
        Binding(
            get: { preferences.terminalCursorStyle.blinks },
            set: { preferences.terminalCursorStyle = TerminalCursorStyleChoice(shape: preferences.terminalCursorStyle.shape, blinks: $0) }
        )
    }
}
