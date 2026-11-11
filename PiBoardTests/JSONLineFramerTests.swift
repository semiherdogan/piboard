import Foundation
import Testing
@testable import PiBoard

struct JSONLineFramerTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func splitsOnLineFeed() {
        var framer = JSONLineFramer()
        #expect(strings(framer.append(Data("{\"a\":1}\n{\"b\":2}\n".utf8))) == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func stripsTrailingCarriageReturn() {
        var framer = JSONLineFramer()
        #expect(strings(framer.append(Data("a\r\nb\n".utf8))) == ["a", "b"])
    }

    @Test func keepsPartialTailUntilTheLineEnds() {
        var framer = JSONLineFramer()
        #expect(framer.append(Data("{\"a\"".utf8)).isEmpty)
        #expect(strings(framer.append(Data(":1}\n{\"b\"".utf8))) == ["{\"a\":1}"])
        #expect(strings(framer.append(Data(":2}\n".utf8))) == ["{\"b\":2}"])
    }

    @Test func doesNotSplitOnUnicodeLineSeparatorsInsideStrings() {
        var framer = JSONLineFramer()
        let line = "{\"s\":\"x\u{2028}y\u{2029}z\"}"
        #expect(strings(framer.append(Data((line + "\n").utf8))) == [line])
    }

    @Test func dropsEmptyLines() {
        var framer = JSONLineFramer()
        #expect(strings(framer.append(Data("\n\na\n\r\n".utf8))) == ["a"])
    }

    @Test func assemblesOneLineFedInManyChunks() {
        var framer = JSONLineFramer()
        let line = String(repeating: "x", count: 5000)
        let bytes = Array((line + "\nnext\n").utf8)
        var lines: [String] = []
        for chunkStart in stride(from: 0, to: bytes.count, by: 7) {
            lines += strings(framer.append(Data(bytes[chunkStart..<min(chunkStart + 7, bytes.count)])))
        }
        #expect(lines == [line, "next"])
    }

    @Test func joinsAMultiByteCharacterSplitAcrossChunks() {
        var framer = JSONLineFramer()
        let bytes = Array("é\n".utf8)
        #expect(framer.append(Data(bytes[0..<1])).isEmpty)
        #expect(strings(framer.append(Data(bytes[1...]))) == ["é"])
    }
}
