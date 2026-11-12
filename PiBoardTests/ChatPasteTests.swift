import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PiBoard

@MainActor
struct ChatPasteTests {
    private static func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("dev.piboard.tests.paste.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private static func pngData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private static func tiffData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(data: try pngData()))
        return try #require(bitmap.representation(using: .tiff, properties: [:]))
    }

    @Test func pngOnThePasteboardBecomesAnImage() throws {
        let board = Self.pasteboard()
        let png = try Self.pngData()
        board.setData(png, forType: .png)

        #expect(ChatAttachment.pasteContent(from: board) == .image(png, mimeType: "image/png"))
    }

    @Test func tiffIsConvertedToPNG() throws {
        let board = Self.pasteboard()
        board.setData(try Self.tiffData(), forType: .tiff)

        let content = ChatAttachment.pasteContent(from: board)
        guard case .tiff = content else {
            Issue.record("Expected a TIFF")
            return
        }
        guard let attachment = ChatAttachment.pastedImage(for: content, number: 1),
              case .image(let data, let mimeType) = attachment.source else {
            Issue.record("Expected a converted image")
            return
        }
        #expect(mimeType == "image/png")
        #expect(attachment.name == "Pasted image 1.png")
        #expect(NSBitmapImageRep(data: data) != nil)
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func textOnlyPasteboardHasNoAttachment() {
        let board = Self.pasteboard()
        board.setString("just text", forType: .string)

        #expect(ChatAttachment.pasteContent(from: board) == .none)
    }

    @Test func emptyPasteboardHasNoAttachment() {
        #expect(ChatAttachment.pasteContent(from: Self.pasteboard()) == .none)
    }

    @Test func aFileURLBecomesAFile() {
        let board = Self.pasteboard()
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        board.writeObjects([url as NSURL])

        #expect(ChatAttachment.pasteContent(from: board) == .files([url]))
    }

    @Test func filesWinOverAnImageOnTheSamePasteboard() throws {
        let board = Self.pasteboard()
        let url = URL(fileURLWithPath: "/tmp/picture.png")
        board.writeObjects([url as NSURL])
        board.setData(try Self.pngData(), forType: .png)

        #expect(ChatAttachment.pasteContent(from: board) == .files([url]))
    }

    @Test func textWinsOverAnImageButFilesWinOverText() throws {
        let imageOnly = Self.pasteboard()
        imageOnly.setData(try Self.pngData(), forType: .png)
        #expect(ChatAttachment.isAttachmentPaste(on: imageOnly))

        let both = Self.pasteboard()
        both.setData(try Self.pngData(), forType: .png)
        both.setString("cells", forType: .string)
        #expect(!ChatAttachment.isAttachmentPaste(on: both))

        let file = Self.pasteboard()
        file.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
        file.setString("a.txt", forType: .string)
        #expect(ChatAttachment.isAttachmentPaste(on: file))

        #expect(!ChatAttachment.isAttachmentPaste(on: Self.pasteboard()))
    }

    @Test func pastedImageGetsANumberedName() throws {
        let png = try Self.pngData()
        let attachment = try #require(ChatAttachment.pastedImage(data: png, mimeType: "image/png", number: 2))

        #expect(attachment.name == "Pasted image 2.png")
        #expect(attachment.source == .image(png, mimeType: "image/png"))
    }

    @Test func pastedImageNumbersNeverRepeatAfterARemoval() throws {
        var counter = PastedImageCounter()
        let png = try Self.pngData()
        var attachments = [
            try #require(ChatAttachment.pastedImage(data: png, mimeType: "image/png", number: counter.next())),
            try #require(ChatAttachment.pastedImage(data: png, mimeType: "image/png", number: counter.next())),
        ]
        attachments.removeLast()
        let next = try #require(ChatAttachment.pastedImage(data: png, mimeType: "image/png", number: counter.next()))

        #expect(next.name == "Pasted image 3.png")
        #expect(attachments.count == 1)
    }

    @Test func unreadableTIFFHasItsOwnMessage() {
        let garbage = ChatAttachment.PasteContent.tiff(Data([0, 1, 2]))

        #expect(ChatAttachment.pastedImage(for: garbage, number: 1) == nil)
        #expect(ChatAttachment.pastedImageFailureMessage(for: garbage) == ChatAttachment.imageUnreadableMessage)
        #expect(ChatAttachment.pastedImageFailureMessage(for: .image(Data(), mimeType: "image/png")) == ChatAttachment.imageTooLargeMessage)
    }

    @Test func pastedImageOverTheLimitIsRefused() {
        let big = Data(count: ChatAttachment.maxImageBytes + 1)

        #expect(ChatAttachment.pastedImage(data: big, mimeType: "image/png", number: 1) == nil)
    }

    @Test func pastedImageAtTheLimitIsKept() {
        let exact = Data(count: ChatAttachment.maxImageBytes)

        #expect(ChatAttachment.pastedImage(data: exact, mimeType: "image/png", number: 1) != nil)
    }
}
