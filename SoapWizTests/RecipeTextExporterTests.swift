import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The clipboard text is for a person to read, so the assertions check the
/// structure and that the numbers agree with the model — never a formatted
/// string spelled out by hand, which would pass in one region and fail in another.
@Suite("Recipe text exporter", .serialized)
@MainActor
struct RecipeTextExporterTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// 1200 g of oils split 70/30, one additive, one fragrance.
    @discardableResult
    private func seedRecipe(_ ctx: ModelContext) -> Recipe {
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        olive.sapValue = 0.1345
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        coconut.sapValue = 0.19
        let lactate = Ingredient(name: "Sodium Lactate", unit: "g")
        let lavender = Ingredient(name: "Lavender EO", unit: "g")
        for ingredient in [olive, coconut, lactate, lavender] {
            ctx.insert(ingredient)
        }

        let recipe = Recipe(name: "Classic Bar", desc: "A gentle everyday bar")
        recipe.weightUnit = "%"
        recipe.oilWeightUnit = "g"
        recipe.totalOilWeight = 1200
        ctx.insert(recipe)

        for (ingredient, pct) in [(olive, 70.0), (coconut, 30.0)] {
            let line = RecipeIngredient(ingredient: ingredient, percentage: pct, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        let additive = RecipeIngredient(ingredient: lactate, percentage: 0, role: .additive)
        additive.additiveAmount = 12
        additive.additiveUnit = "g"
        additive.recipe = recipe
        ctx.insert(additive)

        let fragrance = RecipeIngredient(ingredient: lavender, percentage: 0, role: .fragrance)
        fragrance.additiveAmount = 100
        fragrance.additiveUnit = FragranceUnit.percentOfFragrances.rawValue
        fragrance.recipe = recipe
        ctx.insert(fragrance)

        try? ctx.save()
        return recipe
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: - Header

    @Test func text_RecipeWithDescription_StartsWithNameThenDescription() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let lines = RecipeTextExporter.text(for: recipe).components(separatedBy: "\n")

        #expect(lines.first == "Classic Bar")
        #expect(lines.dropFirst().first == "A gentle everyday bar")
    }

    @Test func text_NoDescription_OmitsTheDescriptionLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Blank")
        ctx.insert(recipe)
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text == "Blank")
    }

    @Test func text_UnnamedRecipe_FallsBackToAPlaceholderTitle() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "")
        ctx.insert(recipe)
        try ctx.save()

        #expect(RecipeTextExporter.text(for: recipe).hasPrefix("Untitled Recipe"))
    }

    // MARK: - Collections

    @Test func text_FiledRecipe_ListsItsCollectionsAlphabetically() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        let gifts = RecipeCollection(name: "Gifts")
        let christmas = RecipeCollection(name: "Christmas")
        ctx.insert(gifts)
        ctx.insert(christmas)
        recipe.collections = [gifts, christmas]
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("Collections: Christmas, Gifts"))
    }

    @Test func text_UnfiledRecipe_OmitsTheCollectionsLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        #expect(!RecipeTextExporter.text(for: recipe).contains("Collections:"))
    }

    // MARK: - Ingredient sections

    @Test func text_Oils_ListsEachOilWithItsShareAndWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("Oils"))
        #expect(text.contains("Olive Oil — 70% (\(number(840)) g)"))
        #expect(text.contains("Coconut Oil — 30% (\(number(360)) g)"))
    }

    /// Highest share first, matching the order the detail screen lists them in.
    @Test func text_Oils_AreOrderedByDescendingShare() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)
        let olive = try #require(text.range(of: "Olive Oil"))
        let coconut = try #require(text.range(of: "Coconut Oil"))

        #expect(olive.lowerBound < coconut.lowerBound)
    }

    @Test func text_AdditivesAndFragrances_AreListedWithTheirUnits() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("Additives"))
        #expect(text.contains("Sodium Lactate — \(number(12)) g"))
        #expect(text.contains("Fragrances"))
        #expect(text.contains("Lavender EO"))
    }

    @Test func text_NoAdditivesOrFragrances_OmitsThoseSections() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        olive.sapValue = 0.1345
        ctx.insert(olive)
        let recipe = Recipe(name: "Castile")
        recipe.weightUnit = "%"
        recipe.totalOilWeight = 500
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("Oils"))
        #expect(!text.contains("Additives"))
        #expect(!text.contains("Fragrances"))
    }

    @Test func text_RecipeWithNoIngredients_OmitsEverySection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Blank", desc: "Nothing yet")
        ctx.insert(recipe)
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(!text.contains("Oils"))
        #expect(!text.contains("Calculated amounts"))
    }

    // MARK: - Calculated amounts

    /// The whole point of routing through `RecipeFormViewModel`: the clipboard
    /// and the detail screen must not be able to print different numbers.
    @Test func text_CalculatedAmounts_MatchTheModelsOwnRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        let rows = try #require(model.calculatedAmountRows)
        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("Calculated amounts"))
        for row in rows {
            #expect(text.contains("\(row.label) — \(number(row.weight)) \(model.displayWeightUnit)"))
        }
    }

    @Test func text_CalculatedAmounts_IncludeTheBatchTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        let total = try #require(model.calculatedAmountRows?.last)
        let text = RecipeTextExporter.text(for: recipe)

        #expect(total.label == "Batch total")
        #expect(text.contains("Batch total — \(number(total.weight)) g"))
    }

    // MARK: - Shape

    @Test func text_Blocks_AreSeparatedByABlankLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("\n\nOils"))
        #expect(text.contains("\n\nCalculated amounts"))
        #expect(!text.hasSuffix("\n"))
    }
}
