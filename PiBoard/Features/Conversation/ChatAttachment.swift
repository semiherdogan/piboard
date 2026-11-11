import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A file picked or dropped for the next chat message: images travel as image blocks, anything else as a path in the text.
struct ChatAttachment: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case file(URL)
        case image(Data, mimeType: String)
    }

    /// What a picked file becomes: an image block, a path in the text, or nothing when the image is too big to send.
    enum Kind: Equatable, Sendable {
        case image(mimeType: String)
        case file
        case imageTooLarge
    }

    /// Files that were picked and the ones refused for size, so the composer can say why.
    struct Loaded: Sendable {
        var attachments: [ChatAttachment] = []
        var rejectedImageCount = 0
    }

    static let maxImageBytes = 5 * 1024 * 1024
    static let imageTooLargeMessage = "Image is larger than 5 MB."
    private static let supportedImageTypes: [UTType] = [.png, .jpeg, .gif, .webP]
    private static let lineSeparator = "\n"

    let id = UUID()
    let name: String
    let source: Source

    /// Reads image files off the main actor; a file that cannot be read stays a plain path.
    static func load(_ urls: [URL]) async -> Loaded {
        await Task.detached(priority: .userInitiated) {
            var loaded = Loaded()
            for url in urls {
                if let attachment = attachment(for: url) {
                    loaded.attachments.append(attachment)
                } else {
                    loaded.rejectedImageCount += 1
                }
            }
            return loaded
        }.value
    }

    /// Appends what could be read and reports a refused image through `error`.
    @MainActor
    static func add(_ urls: [URL], to attachments: Binding<[ChatAttachment]>, error: Binding<String?>) async {
        let loaded = await load(urls)
        attachments.wrappedValue += loaded.attachments
        error.wrappedValue = loaded.rejectedImageCount > 0 ? imageTooLargeMessage : nil
    }

    static func classify(mimeType: String?, byteCount: Int) -> Kind {
        guard let mimeType else { return .file }
        return byteCount > maxImageBytes ? .imageTooLarge : .image(mimeType: mimeType)
    }

    static func mimeType(for url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return supportedImageTypes.first { type.conforms(to: $0) }?.preferredMIMEType
    }

    /// The message text (typed text, then one path per line) and the images to send with it.
    static func payload(text: String, attachments: [ChatAttachment]) -> (text: String, images: [PromptImage]) {
        var lines = text.isEmpty ? [] : [text]
        var images: [PromptImage] = []
        for attachment in attachments {
            switch attachment.source {
            case .file(let url):
                lines.append(DroppedFilePaths.text(for: [url]).trimmingCharacters(in: .whitespaces))
            case .image(let data, let mimeType):
                images.append(PromptImage(data: data, mimeType: mimeType))
            }
        }
        return (lines.joined(separator: lineSeparator), images)
    }

    /// Nil when the file is an image over the size limit.
    private static func attachment(for url: URL) -> ChatAttachment? {
        let name = url.lastPathComponent
        let mimeType = mimeType(for: url)
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        switch classify(mimeType: mimeType, byteCount: byteCount) {
        case .imageTooLarge:
            return nil
        case .image(let mimeType):
            guard let data = try? Data(contentsOf: url) else { return ChatAttachment(name: name, source: .file(url)) }
            return ChatAttachment(name: name, source: .image(data, mimeType: mimeType))
        case .file:
            return ChatAttachment(name: name, source: .file(url))
        }
    }
}
