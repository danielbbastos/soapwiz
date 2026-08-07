import Testing
import Foundation
import FoundationModels
@testable import SoapWiz

/// What the schema handed to the on-device model demands of it.
///
/// Guided generation makes the schema a hard constraint rather than a request:
/// the model has to return something satisfying it. A minimum on an ingredient
/// list is therefore an instruction to invent an ingredient when the text has
/// none, which no wording in the prompt can talk it out of.
@Suite("Generated recipe schema")
struct GeneratedRecipeSchemaTests {

    /// A floor of one oil is answerable only by making one up, and it also
    /// pins `hasAnyIngredient` to true for every successful generation, which
    /// disarms the `.nothingRecognised` guard in `FoundationModelsRecipeExtractor`.
    /// A shopping list would then reach the review screen as a recipe.
    @available(iOS 26, macOS 26, *)
    @Test(arguments: ["oils", "additives", "fragrances"])
    func ingredientLists_StateNoMinimumCount(_ property: String) throws {
        let list = try Self.property(property)
        #expect(list["minItems"] == nil, "\(property) must not oblige the model to produce one")
    }

    /// The ceilings are the point of the guides and must survive.
    @available(iOS 26, macOS 26, *)
    @Test(arguments: [("oils", 20), ("additives", 12), ("fragrances", 8)])
    func ingredientLists_KeepTheirMaximumCount(_ property: String, _ expected: Int) throws {
        let list = try Self.property(property)
        #expect(list["maxItems"] as? Int == expected)
    }

    /// Required means the key has to be present, not that it has to be filled;
    /// an empty array still satisfies it. Worth pinning, because dropping
    /// `oils` from the required set would be a different and worse fix for the
    /// same problem — the field would go missing rather than come back empty.
    @available(iOS 26, macOS 26, *)
    @Test func oils_AreStillARequiredKey() throws {
        let required = try #require(Self.schema()["required"] as? [String])
        #expect(required.contains("oils"))
    }

    /// The other half of the guard: with no floor in the schema, a draft that
    /// genuinely found nothing reports so, and the extractor can reject it.
    @Test func hasAnyIngredient_DraftWithEmptyLists_IsFalse() {
        let draft = RecipeImportDraft.mock(oils: [], additives: [], fragrances: [])
        #expect(!draft.hasAnyIngredient)
    }

    @Test func hasAnyIngredient_DraftWithOnlyAnAdditive_IsTrue() {
        let draft = RecipeImportDraft.mock(
            oils: [],
            additives: [ImportedIngredient(name: "Kaolin Clay", amount: 15, unit: "g")]
        )
        #expect(draft.hasAnyIngredient)
    }

    // MARK: - Reading the schema

    @available(iOS 26, macOS 26, *)
    private static func schema() throws -> [String: Any] {
        let data = try JSONEncoder().encode(GeneratedRecipeDraft.generationSchema)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @available(iOS 26, macOS 26, *)
    private static func property(_ name: String) throws -> [String: Any] {
        let properties = try #require(try schema()["properties"] as? [String: Any])
        return try #require(properties[name] as? [String: Any])
    }
}
