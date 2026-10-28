import Foundation
import Testing
@testable import PiBoard

struct PromptTemplateTests {
    private let template = PromptTemplate(name: "Review", text: "b")

    @Test func insertIntoEmptyPromptIsTheTemplate() {
        #expect(PromptTemplate.insert(template, into: "") == "b")
        #expect(PromptTemplate.insert(template, into: " \n") == "b")
    }

    @Test func insertAppendsAsNewParagraph() {
        #expect(PromptTemplate.insert(template, into: "a") == "a\n\nb")
    }

    @Test func insertTrimsTrailingWhitespaceFirst() {
        #expect(PromptTemplate.insert(template, into: "a \n") == "a\n\nb")
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode([template])
        let decoded = try JSONDecoder().decode([PromptTemplate].self, from: data)
        #expect(decoded == [template])
    }
}
