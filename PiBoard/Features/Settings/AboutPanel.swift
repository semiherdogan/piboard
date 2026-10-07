import AppKit

/// Contents of the standard About panel.
///
/// macOS renders the `credits` option in a text view that follows links, which is the only place
/// the stock panel accepts one. The panel is otherwise left alone so the icon, name and version
/// keep coming from the bundle.
enum AboutPanel {
    static let repositoryURL = URL(string: "https://github.com/semiherdogan/piboard")!
    private static let linkTitle = "PiBoard on GitHub"

    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: linkTitle,
            attributes: [
                .link: repositoryURL,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ]
        )
    }
}
