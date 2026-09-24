import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The reader's contract is the exporter's output, so most tests start from a
/// real recipe run through `RecipeTextExporter.text(for:)` — never from text
/// typed out by hand, which would be formatted in one region only.
@Suite("Recipe text export reader", .serialized)
@MainActor
struct RecipeTextExportReaderTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    // MARK: - Round trip

    @Test func read_PercentageRecipe_RecoversSharesAndBatchSize() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.name == "Classic Bar")
        #expect(draft.desc == "A gentle everyday bar")
        #expect(draft.amountsArePercentages)
        #expect(draft.batchSize == 1310.4)
        #expect(draft.batchUnit == "g")
        #expect(draft.oils.map(\.name) == ["Olive Oil", "Coconut Oil"])
        #expect(draft.oils.map(\.amount) == [70, 30])
    }

    @Test func read_PercentageRecipe_KeepsAdditiveAndFragranceUnits() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        let additive = try #require(draft.additives.first)
        #expect(additive.name == "Sodium Lactate")
        #expect(additive.amount == 1)
        #expect(additive.unit == "% of oils")
        let fragrance = try #require(draft.fragrances.first)
        #expect(fragrance.name == "Lavender EO")
        #expect(fragrance.amount == 100)
        #expect(fragrance.unit == FragranceUnit.percentOfFragrances.rawValue)
    }

    /// The blend's shares say how it splits, not how much of it there is; the
    /// load is recovered from the bracketed weights.
    @Test func read_FragranceBlend_RecoversTheFragranceLoad() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.fragrancePercentage = 5
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.fragrancePercentage == 5)
    }

    /// Shares print with one decimal; the weights carry two, which is enough to
    /// get a third back to 33.33 rather than 33.3.
    @Test func read_ThirdsOfABatch_RecoversSharesBeyondThePrintedDecimal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx, shares: [33.33, 33.33, 33.34], total: 1000)

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.oils.map(\.amount) == [33.34, 33.33, 33.33])
        #expect(draft.batchSize == 1000)
    }

    @Test func read_AbsoluteRecipe_ReadsWeightsInTheirUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.weightUnit = "oz"
        for line in recipe.ingredients where line.ingredientRole == .oil {
            line.percentage = line.percentage == 70 ? 21 : 9
        }
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(!draft.amountsArePercentages)
        #expect(draft.batchUnit == "oz")
        #expect(draft.oils.map(\.amount) == [21, 9])
        #expect(draft.oils.allSatisfy { $0.unit == "oz" })
    }

    @Test func read_SingleLyeSettings_ReadsLyeSuperfatAndWater() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.lyeType = "KOH"
        recipe.lyePurity = 85
        recipe.superFat = 7.5
        recipe.waterParts = 2.5
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.lyeType == "KOH")
        #expect(draft.lyePurity == recipe.lyePurity)
        #expect(draft.kohPercentage == nil)
        #expect(draft.superFat == 7.5)
        #expect(draft.waterParts == 2.5)
        #expect(draft.cfmNeutralizer == nil)
        #expect(!draft.isCreamSoap)
    }

    @Test func read_HybridFailorCreamSoap_ReadsEveryMethod() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.useHybrid = true
        recipe.kohPercentage = 70
        recipe.naohPercentage = 30
        recipe.kohPurity = 85
        recipe.naohPurity = 97.5
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        recipe.isCreamSoap = true
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.lyeType == nil)
        #expect(draft.kohPercentage == 70)
        #expect(draft.kohPurity == 85)
        #expect(draft.naohPurity == 97.5)
        #expect(draft.cfmNeutralizer == .borax)
        #expect(draft.isCreamSoap)
    }

    @Test func read_FiledRecipe_ReadsCollectionNames() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        let gifts = RecipeCollection(name: "Gifts")
        let summer = RecipeCollection(name: "Summer")
        ctx.insert(gifts)
        ctx.insert(summer)
        recipe.collections = [summer, gifts]
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.collectionNames == ["Gifts", "Summer"])
    }

    /// A comma inside a name is the exporter's separator too, so the name is
    /// quoted rather than read back as two collections.
    @Test func read_CollectionNameWithAComma_ReadsAsOneName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        let kids = RecipeCollection(name: "Kids, Sensitive Skin")
        let quoted = RecipeCollection(name: "\"Best\", Ever")
        let summer = RecipeCollection(name: "Summer")
        [kids, quoted, summer].forEach(ctx.insert)
        recipe.collections = [summer, kids, quoted]
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.collectionNames == ["\"Best\", Ever", "Kids, Sensitive Skin", "Summer"])
    }

    @Test(arguments: [
        ("Gifts", ["Gifts"]),
        ("Gifts, Summer", ["Gifts", "Summer"]),
        ("\"Kids, Sensitive Skin\", Summer", ["Kids, Sensitive Skin", "Summer"]),
        ("Gifts, \"Say \"\"Hi\"\", Mum\"", ["Gifts", "Say \"Hi\", Mum"]),
        ("Mum's \"Best\" Bars", ["Mum's \"Best\" Bars"])
    ])
    func collectionNames_ExporterList_ReadsEachName(_ list: String, _ expected: [String]) {
        #expect(RecipeTextExportReader.collectionNames(in: list[...]) == expected)
    }

    @Test(arguments: ["\"Kids, Sensitive Skin", "\"Kids\" Summer"])
    func collectionNames_BrokenQuoting_ReturnsNil(_ list: String) {
        #expect(RecipeTextExportReader.collectionNames(in: list[...]) == nil)
    }

    @Test func read_MultiLineDescription_KeepsEveryLine() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.desc = "A gentle bar.\nCure six weeks."
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.desc == "A gentle bar.\nCure six weeks.")
    }

    /// Mail and some notes apps drop the leading spaces on the rows.
    @Test func read_IndentationStripped_StillReads() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        let text = RecipeTextExporter.text(for: recipe)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        let draft = try #require(RecipeTextExportReader.read(text))

        #expect(draft.oils.count == 2)
    }

    // MARK: - Hand-built text

    /// The case from the device: a space-grouped weight, with a comma decimal.
    @Test func read_SpaceGroupedWeights_ReadsTheBatch() throws {
        let text = """
        Hard Bar

        Oils
          Olive Oil — 60% (786,24 g)
          Coconut Oil — 40% (524,16 g)

        NaOH (99% pure) · 5% superfat · water 2,5:1
        """

        let draft = try #require(RecipeTextExportReader.read(text))

        #expect(draft.batchSize == 1310.4)
        #expect(draft.oils.map(\.amount) == [60, 40])
        #expect(draft.waterParts == 2.5)
    }

    @Test func read_NameWithADash_SplitsAtTheLastSeparator() throws {
        let text = """
        Bar

        Oils
          Olive Oil — Extra Virgin — 100% (500 g)
        """

        let draft = try #require(RecipeTextExportReader.read(text))

        #expect(draft.oils.first?.name == "Olive Oil — Extra Virgin")
    }

    /// The exporter writes a settings line for every soap recipe and never
    /// for anything else, so its absence is what says "not soap".
    @Test func read_NoSettingsLine_ReadsAsNonSoap() throws {
        let text = """
        Body Butter

        Oils
          Shea Butter — 100% (200 g)
        """

        let draft = try #require(RecipeTextExportReader.read(text))

        #expect(!draft.statesLyeSettings)
        #expect(draft.recipeKind == .general)
    }

    @Test func read_SoapRecipe_LeavesTheKindToTheForm() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.recipeKind == nil)
    }

    @Test func read_NonSoapRecipe_ReadsAsNonSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue
        try ctx.save()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.recipeKind == .general)
        #expect(draft.lyeType == nil)
    }

    // MARK: - Not ours

    @Test(arguments: [
        "",
        "Olive Oil 70%\nCoconut Oil 30%\nNaOH 5% superfat",
        "Bar\n\nOils\n  Olive Oil — lots",
        "Bar\n\nAdditives\n  Sodium Lactate — 1 % of oils",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nNaOH (99% pure) · 5% superfat · cured in a shoebox",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nNaOH (99% pure) · 5% superfat\nMy grandmother's recipe",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nNaOH · 5% superfat",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nNaOH (140% pure) · 5% superfat",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nKOH (90% pure) · 5% superfat · Failor method",
        "Bar\nCollections: \"Kids, Sensitive Skin\nOils\n  Olive Oil — 100% (500 g)",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\nOils\n  Coconut Oil — 100% (500 g)",
        "Bar\n\nOils\n  Olive Oil — 60% (300 g)\n  Coconut Oil — 40% (200 oz)",
        "Bar\n\nOils\n  Olive Oil — 100% (500 g)\n\nAdditives\n  Clay — 1 % of oils (5 oz)"
    ])
    func read_TextSoapWizDidNotWrite_ReturnsNil(_ text: String) {
        #expect(RecipeTextExportReader.read(text) == nil)
    }

    // MARK: - Numbers

    @Test(arguments: [
        ("60", 60.0),
        ("2,5", 2.5),
        ("2.5", 2.5),
        ("1 310,4", 1310.4),
        ("1\u{00A0}310,4", 1310.4),
        ("1\u{202F}310,4", 1310.4),
        ("1,310.4", 1310.4),
        ("1.310,4", 1310.4),
        ("1'310.4", 1310.4),
        ("1,310", 1310.0),
        ("1.310", 1310.0),
        ("1 234 567,89", 1_234_567.89)
    ])
    func decimal_ExporterFormattedNumber_ReadsTheValue(_ token: String, _ expected: Double) {
        #expect(RecipeTextExportReader.decimal(token) == expected)
    }
}

extension Recipe {
    /// Olive and coconut oil by share, sodium lactate at 1% of oils and a
    /// lavender blend, weighing 1310.4 g — the batch from the device report.
    @MainActor
    static func exportMock(
        in context: ModelContext,
        shares: [Double] = [70, 30],
        total: Double = 1310.4
    ) -> Recipe {
        let names = ["Olive Oil", "Coconut Oil", "Castor Oil"]
        let recipe = Recipe(name: "Classic Bar", desc: "A gentle everyday bar")
        recipe.weightUnit = "%"
        recipe.oilWeightUnit = "g"
        recipe.totalOilWeight = total
        context.insert(recipe)

        for (name, share) in zip(names, shares) {
            let oil = Ingredient(name: name, unit: "g")
            oil.sapValue = 0.15
            context.insert(oil)
            let line = RecipeIngredient(ingredient: oil, percentage: share, role: .oil)
            line.recipe = recipe
            context.insert(line)
        }

        let lactate = Ingredient(name: "Sodium Lactate", unit: "g")
        context.insert(lactate)
        let additive = RecipeIngredient(ingredient: lactate, percentage: 0, role: .additive)
        additive.additiveAmount = 1
        additive.additiveUnit = "% of oils"
        additive.recipe = recipe
        context.insert(additive)

        let lavender = Ingredient(name: "Lavender EO", unit: "g")
        context.insert(lavender)
        let fragrance = RecipeIngredient(ingredient: lavender, percentage: 0, role: .fragrance)
        fragrance.additiveAmount = 100
        fragrance.additiveUnit = FragranceUnit.percentOfFragrances.rawValue
        fragrance.recipe = recipe
        context.insert(fragrance)
        recipe.fragranceUnit = FragranceUnit.percentOfFragrances.rawValue

        try? context.save()
        return recipe
    }
}
