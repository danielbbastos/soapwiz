import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVTextDecoderTests {
    @Test func text_EmptyData_ReturnsNil() {
        #expect(CSVTextDecoder.text(from: Data()) == nil)
    }

    @Test func text_PlainUTF8_Decodes() throws {
        let data = try #require("Óleo de coco".data(using: .utf8))
        #expect(CSVTextDecoder.text(from: data) == "Óleo de coco")
    }

    @Test func text_UTF8WithBOM_StripsBOM() throws {
        let data = try Data([0xEF, 0xBB, 0xBF]) + #require("name,price".data(using: .utf8))
        #expect(CSVTextDecoder.text(from: data) == "name,price")
    }

    @Test func text_UTF16LittleEndianWithBOM_Decodes() throws {
        let data = try Data([0xFF, 0xFE]) + #require("Óleo;5,50".data(using: .utf16LittleEndian))
        #expect(CSVTextDecoder.text(from: data) == "Óleo;5,50")
    }

    @Test func text_UTF16BigEndianWithBOM_Decodes() throws {
        let data = try Data([0xFE, 0xFF]) + #require("Óleo;5,50".data(using: .utf16BigEndian))
        #expect(CSVTextDecoder.text(from: data) == "Óleo;5,50")
    }

    @Test func text_WindowsCP1252Bytes_FallsBackToCP1252() throws {
        let data = try #require("Óleo de coco".data(using: .windowsCP1252))
        #expect(String(data: data, encoding: .utf8) == nil)
        #expect(CSVTextDecoder.text(from: data) == "Óleo de coco")
    }

    @Test func text_CP1252EuroSign_Decodes() throws {
        let data = try #require("5,00 €".data(using: .windowsCP1252))
        #expect(CSVTextDecoder.text(from: data) == "5,00 €")
    }

    @Test func text_BOMOnly_ReturnsEmptyText() {
        #expect(CSVTextDecoder.text(from: Data([0xEF, 0xBB, 0xBF])) == "")
    }
}
