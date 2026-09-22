import Testing
import Foundation
import FoundationModels
@testable import SoapWiz

/// How the extractor's final generated content becomes the draft the review
/// screen shows, as opposed to the mid-stream snapshots the progress screen shows.
@Suite("Generated recipe draft mapping")
struct GeneratedRecipeDraftMappingTests {

    @available(iOS 26, macOS 26, *)
    @Test func asImportDraft_CompletedRowWithBlankName_KeepsTheRow() throws {
        let content = try GeneratedContent(json: Self.json(oilNames: ["Olive Oil", ""]))
        let draft = try GeneratedRecipeDraft(content).asImportDraft()

        #expect(draft.oils.map(\.name) == ["Olive Oil", ""])
    }

    @available(iOS 26, macOS 26, *)
    @Test func partialAsImportDraft_RowWithBlankName_DropsTheRow() throws {
        let content = try GeneratedContent(json: Self.json(oilNames: ["Olive Oil", ""]))
        let draft = try GeneratedRecipeDraft.PartiallyGenerated(content).asImportDraft()

        #expect(draft.oils.map(\.name) == ["Olive Oil"])
    }

    @available(iOS 26, macOS 26, *)
    @Test func asImportDraft_TrimsNamesAndBlankUnits() throws {
        let content = try GeneratedContent(json: Self.json(oilNames: ["  Olive Oil  "], unit: " "))
        let oil = try #require(try GeneratedRecipeDraft(content).asImportDraft().oils.first)

        #expect(oil.name == "Olive Oil")
        #expect(oil.unit == nil)
    }

    // MARK: - Fixtures

    private static func json(oilNames: [String], unit: String = "g") -> String {
        let oils = oilNames
            .map { #"{"name": "\#($0)", "amount": 100, "unit": "\#(unit)"}"# }
            .joined(separator: ", ")
        return """
            {"name": "Castile Bar", "oils": [\(oils)], "additives": [], "fragrances": [], \
            "amountsArePercentages": false}
            """
    }
}
