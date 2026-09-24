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

    // MARK: - Settings line

    /// The trimmed text drops the whole calculated-amounts table in favour of a
    /// single settings line, so a copied recipe is short enough to send.
    @Test func text_SoapRecipe_OmitsTheCalculatedAmountsTable() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(!text.contains("Calculated amounts"))
        #expect(!text.contains("Batch total"))
    }

    @Test func text_SingleLyeRecipe_CarriesLyeSuperfatAndWater() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.lyeType = "KOH"
        recipe.lyePurity = 90
        recipe.superFat = 8
        recipe.waterParts = 2
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("KOH (\(number(90))% pure) · \(number(8))% superfat · water \(number(2)):1"))
    }

    @Test func text_HybridRecipe_SpellsOutTheKOHNaOHSplit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.useHybrid = true
        recipe.kohPercentage = 70
        recipe.naohPercentage = 30
        try ctx.save()

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("KOH/NaOH \(number(70))/\(number(30))"))
        #expect(text.contains("(\(number(recipe.kohPurity))%/\(number(recipe.naohPurity))% pure)"))
    }

    @Test func text_FailorRecipe_AppendsTheMethod() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.useCFM = true
        try ctx.save()

        #expect(RecipeTextExporter.text(for: recipe).contains("· Failor method"))
    }

    /// Named so a pasted copy comes back with the same neutraliser, not the
    /// default one.
    @Test func text_FailorRecipe_NamesTheNeutralizer() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        try ctx.save()

        #expect(RecipeTextExporter.text(for: recipe).contains("· Failor method (borax)"))
    }

    @Test func text_CreamSoapRecipe_AppendsTheMethod() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.isCreamSoap = true
        try ctx.save()

        #expect(RecipeTextExporter.text(for: recipe).contains("· cream soap method"))
    }

    @Test func text_PlainRecipe_HasNeitherMethodOnTheSettingsLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(!text.contains("Failor method"))
        #expect(!text.contains("cream soap method"))
    }

    @Test func text_SoapRecipeWithNoOils_OmitsTheSettingsLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Just a name")
        ctx.insert(recipe)
        try ctx.save()

        #expect(RecipeTextExporter.text(for: recipe) == "Just a name")
    }

    // MARK: - Shape

    @Test func text_Blocks_AreSeparatedByABlankLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let text = RecipeTextExporter.text(for: recipe)

        #expect(text.contains("\n\nOils"))
        #expect(text.contains("\n\nNaOH ("))
        #expect(!text.hasSuffix("\n"))
    }
}
