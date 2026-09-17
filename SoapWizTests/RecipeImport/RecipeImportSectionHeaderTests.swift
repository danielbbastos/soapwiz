import Testing
import Foundation
@testable import SoapWiz

/// A header such as "Additives:" that the model reported as an ingredient.
///
/// Tapping Add on one would create a real inventory ingredient with no SAP
/// value, so the filter has to be deterministic whatever the model returns.
@Suite("Recipe import section headers")
struct RecipeImportSectionHeaderTests {

    @Test(arguments: ["Additives", "Fragrance", "fragrances", "OILS", "Oil", "Lye", "Ingredients", " Additives "])
    func isSectionHeader_SectionWordWithoutAmount_IsTrue(_ name: String) {
        #expect(ImportedIngredient(name: name, amount: 0, unit: nil).isSectionHeader)
    }

    @Test(arguments: ["Fragrance:", "Essential Oils:", "Butters :", "Additivés:"])
    func isSectionHeader_NameEndingInColonWithoutAmount_IsTrue(_ name: String) {
        #expect(ImportedIngredient(name: name, amount: 0, unit: nil).isSectionHeader)
    }

    @Test func isSectionHeader_AccentedSectionWord_IsTrue() {
        #expect(ImportedIngredient(name: "Addítives", amount: 0, unit: nil).isSectionHeader)
    }

    @Test(arguments: ["Oil", "Lye", "Fragrance", "Additives"])
    func isSectionHeader_SectionWordWithAmount_IsFalse(_ name: String) {
        #expect(!ImportedIngredient(name: name, amount: 15, unit: "g").isSectionHeader)
    }

    @Test func isSectionHeader_NameEndingInColonWithAmount_IsFalse() {
        #expect(!ImportedIngredient(name: "Water:", amount: 300, unit: "g").isSectionHeader)
    }

    @Test func isSectionHeader_IngredientWithoutAmount_IsFalse() {
        #expect(!ImportedIngredient(name: "Rosemary Extract", amount: 0, unit: nil).isSectionHeader)
    }

    @Test func isSectionHeader_NameContainingSectionWord_IsFalse() {
        #expect(!ImportedIngredient(name: "Olive Oil", amount: 0, unit: nil).isSectionHeader)
    }

    @Test func isSectionHeader_EmptyName_IsFalse() {
        #expect(!ImportedIngredient(name: "", amount: 0, unit: nil).isSectionHeader)
    }

    @Test func droppingSectionHeaders_HeadersInEveryList_RemovesOnlyTheHeaders() {
        let draft = RecipeImportDraft.mock(
            oils: [
                ImportedIngredient(name: "Oils:", amount: 0, unit: nil),
                ImportedIngredient(name: "Olive Oil", amount: 45, unit: nil),
                ImportedIngredient(name: "Coconut Oil", amount: 30, unit: nil)
            ],
            additives: [
                ImportedIngredient(name: "Additives", amount: 0, unit: nil),
                ImportedIngredient(name: "Sodium Lactate", amount: 15, unit: "g")
            ],
            fragrances: [
                ImportedIngredient(name: "Fragrance", amount: 0, unit: nil),
                ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of oils")
            ]
        )

        let result = draft.droppingSectionHeaders()

        #expect(result.oils.map(\.name) == ["Olive Oil", "Coconut Oil"])
        #expect(result.additives.map(\.name) == ["Sodium Lactate"])
        #expect(result.fragrances.map(\.name) == ["Lavender Essential Oil"])
    }

    @Test func droppingSectionHeaders_NoHeaders_LeavesDraftUnchanged() {
        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Kaolin Clay", amount: 15, unit: "g")]
        )

        let result = draft.droppingSectionHeaders()

        #expect(result.oils.map(\.id) == draft.oils.map(\.id))
        #expect(result.additives.map(\.id) == draft.additives.map(\.id))
        #expect(result.fragrances.isEmpty)
        #expect(result.name == draft.name)
        #expect(result.lyeType == draft.lyeType)
    }

    @Test func droppingSectionHeaders_OnlyHeaders_HasNoIngredient() {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Oils:", amount: 0, unit: nil)],
            additives: [ImportedIngredient(name: "Additives", amount: 0, unit: nil)],
            fragrances: [ImportedIngredient(name: "Fragrance:", amount: 0, unit: nil)]
        )

        #expect(!draft.droppingSectionHeaders().hasAnyIngredient)
    }
}
