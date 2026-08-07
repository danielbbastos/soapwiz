import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// How a written amount survives the crossing into the form: what unit it ends
/// up in, and what happens when a source names the same ingredient twice.
@Suite("Recipe import → amounts and units", .serialized)
@MainActor
struct RecipeImportAmountMappingTests {

    private let fixture: RecipeImportFixture

    init() throws {
        fixture = try RecipeImportFixture()
    }

    // MARK: - Bare percentages

    /// Sources write "1%", the pickers only offer the compound forms. Falling
    /// back to a weight would turn one percent of the oils into one gram.
    @Test func applyImport_AdditiveStatedAsABarePercentage_StaysAPercentage() throws {
        let clay = fixture.insert("Kaolin Clay")

        let draft = RecipeImportDraft.mock(additives: [ImportedIngredient(name: "Kaolin Clay", amount: 1, unit: "%")])
        let model = fixture.apply(draft, inventory: [clay])

        let additive = try #require(model.additiveDrafts.first)
        #expect(additive.unit == "% of oils")
        #expect(additive.amount == 1)
    }

    /// The fragrance case hides in a percentage-mode recipe, because the
    /// fallback there is already a percent unit. It only shows up when the
    /// recipe is measured in weights and the fragrance is still given as a
    /// percentage — a common combination.
    @Test func applyImport_FragranceBarePercentageInAWeightRecipe_StaysAPercentage() throws {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 700, unit: "g")],
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "%")],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "g"
        )
        let model = fixture.apply(draft)

        let fragrance = try #require(model.fragranceDrafts.first)
        #expect(fragrance.unit == "% of oils")
        #expect(fragrance.amount == 3)
    }

    @Test(arguments: ["%", "percent", "PCT", " % "])
    func applyImport_PercentSpellings_AllResolveToPercentOfOils(_ written: String) throws {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: written)]
        )
        let model = fixture.apply(draft)
        #expect(model.fragranceDrafts.first?.unit == "% of oils")
    }

    /// An explicit base must survive untouched — the mapping is only for the
    /// bare case where the source said nothing.
    @Test func applyImport_ExplicitPercentBase_IsKept() throws {
        let clay = fixture.insert("Kaolin Clay")

        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Kaolin Clay", amount: 2, unit: "% of batch")]
        )
        let model = fixture.apply(draft, inventory: [clay])
        #expect(model.additiveDrafts.first?.unit == "% of batch")
    }

    /// A percentage that reaches the acid neutralisation must arrive as the
    /// share it was written as. Read as a weight it would move the lye.
    @Test func applyImport_AcidStatedAsAPercentage_KeepsItsShareOfTheOils() throws {
        let citric = fixture.insert("Citric Acid")

        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Citric Acid", amount: 2, unit: "%")],
            batchSize: 1_000
        )
        let model = fixture.apply(draft, inventory: [citric])

        let additive = try #require(model.additiveDrafts.first)
        #expect(additive.unit == "% of oils")
        // 2% of 1000 g of oils is 20 g of acid, not 2 g.
        let asWeight = IngredientUnitConverter.convert(
            additive.amount, from: additive.unit, to: "g", density: nil
        )
        #expect(asWeight == nil || asWeight?.value != 2)
    }

    // MARK: - Repeated ingredients

    /// A source can name the same oil twice — a summary above the table, or a
    /// line OCR read from both a sticky header and the body. Both rows resolve
    /// to one inventory ingredient, and the form holds one row per ingredient,
    /// so the later amount must not quietly replace the earlier one.
    @Test func applyImport_SameOilTwice_KeepsTheFirstAmount() throws {
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 25, unit: nil),
            ImportedIngredient(name: "Olive Oil", amount: 20, unit: nil)
        ])
        let model = fixture.apply(draft)

        #expect(model.oilDrafts.count == 2)
        let olive = try #require(model.oilDrafts.first { $0.ingredient.name == "Olive Oil" })
        #expect(olive.amount == 55)
    }

    @Test func applyImport_RepeatedIngredient_IsRecordedInTheDescription() {
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil),
            ImportedIngredient(name: "Olive Oil", amount: 20, unit: nil)
        ])
        let model = fixture.apply(draft)

        #expect(model.desc.contains("Olive Oil"))
        #expect(model.desc.lowercased().contains("repeated"))
    }

    @Test func applyImport_SameFragranceTwice_KeepsTheFirstAmount() throws {
        let draft = RecipeImportDraft.mock(fragrances: [
            ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of oils"),
            ImportedIngredient(name: "Lavender Essential Oil", amount: 1, unit: "% of oils")
        ])
        let model = fixture.apply(draft)

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.fragranceDrafts.first?.amount == 3)
    }

    @Test func applyImport_SameAdditiveTwice_KeepsTheFirstAmount() throws {
        let clay = fixture.insert("Kaolin Clay")

        let draft = RecipeImportDraft.mock(additives: [
            ImportedIngredient(name: "Kaolin Clay", amount: 15, unit: "g"),
            ImportedIngredient(name: "Kaolin Clay", amount: 4, unit: "g")
        ])
        let model = fixture.apply(draft, inventory: [clay])

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts.first?.amount == 15)
    }

    /// Distinct ingredients must be untouched by the duplicate handling.
    @Test func applyImport_DistinctIngredients_AllKeepTheirAmounts() {
        let model = fixture.apply(.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 30, unit: nil),
            ImportedIngredient(name: "Castor Oil", amount: 15, unit: nil)
        ]))
        #expect(model.oilDrafts.map(\.amount) == [55, 30, 15])
        #expect(!model.desc.lowercased().contains("repeated"))
    }

    // MARK: - Several fragrances

    /// A blend is two or three fragrances, and the second one used to eat the
    /// first. Setting a row's unit unlocks every fragrance row, so the amount
    /// already sitting in the earlier row went back to being a share of what
    /// was left of the target: 5% and 2% against a 3% target left the first
    /// row holding 1%.
    @Test func applyImport_TwoFragrancesAsPercentages_BothKeepTheirAmounts() throws {
        let orange = fixture.insert("Sweet Orange Essential Oil")

        let draft = RecipeImportDraft.mock(
            fragrances: [
                ImportedIngredient(name: "Lavender Essential Oil", amount: 5, unit: "% of oils"),
                ImportedIngredient(name: "Sweet Orange Essential Oil", amount: 2, unit: "% of oils")
            ],
            fragrancePercentage: 3
        )
        let model = fixture.apply(draft, inventory: [orange])

        #expect(model.fragranceDrafts.count == 2)
        let lavender = try #require(model.fragranceDrafts.first { $0.ingredient.name == "Lavender Essential Oil" })
        let sweetOrange = try #require(model.fragranceDrafts.first { $0.ingredient.name == "Sweet Orange Essential Oil" })
        #expect(lavender.amount == 5)
        #expect(sweetOrange.amount == 2)
    }

    /// The same collision in a weight recipe, where redistributing a percentage
    /// target across gram amounts has no business happening at all: 20 g and
    /// 10 g left the first fragrance at zero.
    @Test func applyImport_TwoFragrancesAsWeights_BothKeepTheirAmounts() throws {
        let orange = fixture.insert("Sweet Orange Essential Oil")

        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 700, unit: "g")],
            fragrances: [
                ImportedIngredient(name: "Lavender Essential Oil", amount: 20, unit: "g"),
                ImportedIngredient(name: "Sweet Orange Essential Oil", amount: 10, unit: "g")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "g"
        )
        let model = fixture.apply(draft, inventory: [orange])

        #expect(model.fragranceDrafts.count == 2)
        let lavender = try #require(model.fragranceDrafts.first { $0.ingredient.name == "Lavender Essential Oil" })
        let sweetOrange = try #require(model.fragranceDrafts.first { $0.ingredient.name == "Sweet Orange Essential Oil" })
        #expect(lavender.unit == "g")
        #expect(lavender.amount == 20)
        #expect(sweetOrange.amount == 10)
    }

    /// Three rows, because the two-row case can pass on an off-by-one that a
    /// third row still breaks.
    @Test func applyImport_ThreeFragrancesAsPercentages_AllKeepTheirAmounts() throws {
        let orange = fixture.insert("Sweet Orange Essential Oil")
        let patchouli = fixture.insert("Patchouli Essential Oil")

        let draft = RecipeImportDraft.mock(
            fragrances: [
                ImportedIngredient(name: "Lavender Essential Oil", amount: 4, unit: "% of oils"),
                ImportedIngredient(name: "Sweet Orange Essential Oil", amount: 2, unit: "% of oils"),
                ImportedIngredient(name: "Patchouli Essential Oil", amount: 1, unit: "% of oils")
            ],
            fragrancePercentage: 3
        )
        let model = fixture.apply(draft, inventory: [orange, patchouli])

        #expect(model.fragranceDrafts.count == 3)
        #expect(model.fragranceDrafts.map(\.amount) == [4, 2, 1])
    }
}
