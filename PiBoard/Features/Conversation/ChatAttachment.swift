import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Numbers pasted images; it only counts up so a removed attachment never frees its name for the next paste.
struct PastedImageCounter: Equatable, Sendable {
    private(set) var value = 0

    mutating func next() -> Int {
        value += 1
        return value
    }
}

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

    /// What a paste carries that the chat can use; a text-only pasteboard is `.none` and stays with the text field.
    enum PasteContent: Equatable, Sendable {
        case files([URL])
        case image(Data, mimeType: String)
        // Converted to PNG off the main actor, together with the size check.
        case tiff(Data)
        case none

        var isImage: Bool {
            switch self {
            case .image, .tiff: true
            case .files, .none: false
            }
        }
    }

    /// Files that were picked and the ones refused for size, so the composer can say why.
    struct Loaded: Sendable {
        var attachments: [ChatAttachment] = []
        var rejectedImageCount = 0
    }

    static let maxImageBytes = 5 * 1024 * 1024
    static let imageTooLargeMessage = "Image is larger than 5 MB."
    static let imageUnreadableMessage = "The image could not be read."
    private static let supportedImageTypes: [UTType] = [.png, .jpeg, .gif, .webP]
    private static let lineSeparator = "\n"
    private static let pastedImageNamePrefix = "Pasted image"
    private static let pastedImageFallbackExtension = "png"
    // Formats Pi accepts as they are, in the order a paste prefers them; anything else (TIFF) is converted to PNG.
    private static let pasteboardImageTypes: [(pasteboard: NSPasteboard.PasteboardType, type: UTType)] = [
        (.png, .png),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), .jpeg),
    ]

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

    /// Files win over images: copying a file in Finder can also put its icon on the pasteboard.
    static func pasteContent(from pasteboard: NSPasteboard) -> PasteContent {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        if let urls, !urls.isEmpty { return .files(urls) }
        for entry in pasteboardImageTypes {
            if let data = pasteboard.data(forType: entry.pasteboard), let mimeType = entry.type.preferredMIMEType {
                return .image(data, mimeType: mimeType)
            }
        }
        if let tiff = pasteboard.data(forType: .tiff) { return .tiff(tiff) }
        return .none
    }

    /// Whether a paste belongs to the chat: files always, an image only when the pasteboard carries no text.
    static func isAttachmentPaste(on pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return true }
        if pasteboard.availableType(from: [.string]) != nil { return false }
        let imageTypes = pasteboardImageTypes.map(\.pasteboard) + [.tiff]
        return pasteboard.availableType(from: imageTypes) != nil
    }

    /// Nil for a paste that is not an image, one that cannot be converted, or one over the size limit.
    static func pastedImage(for content: PasteContent, number: Int) -> ChatAttachment? {
        switch content {
        case .image(let data, let mimeType):
            return pastedImage(data: data, mimeType: mimeType, number: number)
        case .tiff(let tiff):
            guard let png = convertedPNG(from: tiff), let mimeType = UTType.png.preferredMIMEType else { return nil }
            return pastedImage(data: png, mimeType: mimeType, number: number)
        case .files, .none:
            return nil
        }
    }

    private static func convertedPNG(from tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// Why a paste produced no image: a TIFF that cannot be converted is unreadable, anything else is over the limit.
    static func pastedImageFailureMessage(for content: PasteContent) -> String {
        if case .tiff(let tiff) = content, convertedPNG(from: tiff) == nil { return imageUnreadableMessage }
        return imageTooLargeMessage
    }

    /// Nil when the image is over the size limit.
    static func pastedImage(data: Data, mimeType: String, number: Int) -> ChatAttachment? {
        guard case .image = classify(mimeType: mimeType, byteCount: data.count) else { return nil }
        let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? pastedImageFallbackExtension
        return ChatAttachment(name: "\(pastedImageNamePrefix) \(number).\(fileExtension)", source: .image(data, mimeType: mimeType))
    }

    /// Appends what a paste carried and reports a refused image through `error`; `number` names a pasted image.
    @MainActor
    static func addPasted(_ content: PasteContent, number: Int, to attachments: Binding<[ChatAttachment]>, error: Binding<String?>) async {
        switch content {
        case .none:
            return
        case .files(let urls):
            await add(urls, to: attachments, error: error)
        case .image, .tiff:
            let attachment = await Task.detached(priority: .userInitiated) { pastedImage(for: content, number: number) }.value
            if let attachment {
                attachments.wrappedValue.append(attachment)
                error.wrappedValue = nil
            } else {
                error.wrappedValue = pastedImageFailureMessage(for: content)
            }
        }
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
