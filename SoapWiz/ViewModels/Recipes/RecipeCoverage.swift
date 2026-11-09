import Foundation
import SwiftData

/// What an ingredient contributes to a recipe's requirements: its unit and
/// density convert the amounts, its sap values size the lye, and its name,
/// category and slug decide which rows resolve as the default lye or
/// neutraliser.
struct RecipeIngredientFingerprint: Hashable {
    let id: PersistentIdentifier
    let name: String
    let unit: String
    let density: Double?
    let sapValue: Double?
    let kohSapValue: Double?
    let categoryName: String?
    let librarySlug: String

    init(_ ingredient: Ingredient) {
        id = ingredient.persistentModelID
        name = ingredient.name
        unit = ingredient.unit
        density = ingredient.density
        sapValue = ingredient.sapValue
        kohSapValue = ingredient.kohSapValue
        categoryName = ingredient.category?.name
        librarySlug = ingredient.librarySlug
    }
}

private func storedIngredient(_ ingredient: Ingredient?) -> Ingredient? {
    ingredient.flatMap { $0.modelContext == nil ? nil : $0 }
}

struct RecipeLineFingerprint: Hashable {
    let ingredient: PersistentIdentifier?
    let percentage: Double
    let role: String
    let additiveAmount: Double
    let additiveUnit: String

    init(_ line: RecipeIngredient) {
        ingredient = storedIngredient(line.ingredient)?.persistentModelID
        percentage = line.percentage
        role = line.role
        additiveAmount = line.additiveAmount
        additiveUnit = line.additiveUnit
    }
}

/// Everything the requirement breakdown reads, as a value that can be compared.
struct RecipeCoverageFingerprint: Hashable {
    let weightUnit: String
    let recipeKind: String
    let totalOilWeight: Double
    let oilWeightUnit: String
    let lyeType: String
    let lyePurity: Double
    let waterParts: Double
    let superFat: Double
    let fragrancePercentage: Double
    let fragranceUnit: String
    let useHybrid: Bool
    let kohPercentage: Double
    let naohPercentage: Double
    let kohPurity: Double
    let naohPurity: Double
    let isCreamSoap: Bool
    let useCFM: Bool
    let cfmNeutralizer: String
    let lyeIngredient: PersistentIdentifier?
    let kohLyeIngredient: PersistentIdentifier?
    let neutralizerIngredient: PersistentIdentifier?
    let lines: [RecipeLineFingerprint]
    let ingredients: [RecipeIngredientFingerprint]
    let lyeCandidates: [RecipeIngredientFingerprint]
    let neutralizerCandidates: [RecipeIngredientFingerprint]

    init(recipe: Recipe, lyeCandidates: [Ingredient], neutralizerCandidates: [Ingredient]) {
        weightUnit = recipe.weightUnit
        recipeKind = recipe.recipeKind
        totalOilWeight = recipe.totalOilWeight
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = recipe.lyePurity
        waterParts = recipe.waterParts
        superFat = recipe.superFat
        fragrancePercentage = recipe.fragrancePercentage
        fragranceUnit = recipe.fragranceUnit
        useHybrid = recipe.useHybrid
        kohPercentage = recipe.kohPercentage
        naohPercentage = recipe.naohPercentage
        kohPurity = recipe.kohPurity
        naohPurity = recipe.naohPurity
        isCreamSoap = recipe.isCreamSoap
        useCFM = recipe.useCFM
        cfmNeutralizer = recipe.cfmNeutralizer

        let lye = storedIngredient(recipe.lyeIngredient)
        let kohLye = storedIngredient(recipe.kohLyeIngredient)
        let neutralizer = storedIngredient(recipe.neutralizerIngredient)
        lyeIngredient = lye?.persistentModelID
        kohLyeIngredient = kohLye?.persistentModelID
        neutralizerIngredient = neutralizer?.persistentModelID

        let storedLines = recipe.ingredients.filter { $0.modelContext != nil }
        lines = storedLines.map(RecipeLineFingerprint.init).sorted { $0.sortKey < $1.sortKey }

        let referenced = storedLines.compactMap { storedIngredient($0.ingredient) } + [lye, kohLye, neutralizer].compactMap { $0 }
        var seen = Set<PersistentIdentifier>()
        ingredients = referenced
            .filter { seen.insert($0.persistentModelID).inserted }
            .map(RecipeIngredientFingerprint.init)
            .sorted { $0.sortKey < $1.sortKey }

        self.lyeCandidates = lyeCandidates.filter { $0.modelContext != nil }.map(RecipeIngredientFingerprint.init)
        self.neutralizerCandidates = neutralizerCandidates.filter { $0.modelContext != nil }
            .map(RecipeIngredientFingerprint.init)
    }
}

private extension RecipeLineFingerprint {
    var sortKey: String { "\(String(describing: ingredient))|\(role)|\(percentage)|\(additiveAmount)|\(additiveUnit)" }
}

private extension RecipeIngredientFingerprint {
    var sortKey: String { String(describing: id) }
}

/// How many whole batches of each recipe current stock covers, and what is
/// short for one. Requirements come from the same `RecipeRequirementLine`
/// Create Batch uses; only stock differs, read from `StockLevels`.
///
/// A recipe has no modification date (and gaining a stored property would
/// change the CloudKit schema), so there is no cheap "did it change" signal.
/// Building the breakdown for every recipe on every render is the cost this
/// avoids: each recipe's one-batch requirements are cached against a
/// fingerprint of everything the breakdown reads. That includes the ingredients
/// themselves, since editing one's unit or density changes the amounts without
/// touching the recipe. Stock is never cached; it is weighed on every call.
@MainActor
final class RecipeCoverage {
    struct Coverage {
        /// Whole batches stock covers; zero when anything is short for one.
        let batches: Int
        /// What is short for one batch, sorted by ingredient name; each one's
        /// `shortfall` is for a single batch.
        let shortages: [BatchRequirement]
    }

    private struct Entry {
        let fingerprint: RecipeCoverageFingerprint
        let lines: [RecipeRequirementLine]
    }

    private var cache: [PersistentIdentifier: Entry] = [:]

    /// How many times a recipe's requirements were rebuilt rather than served
    /// from the cache.
    private(set) var computeCount = 0

    func coverage(
        for recipe: Recipe,
        stock: StockLevels,
        lyeCandidates: [Ingredient],
        neutralizerCandidates: [Ingredient],
        tracksInventory: Bool
    ) -> Coverage? {
        guard tracksInventory, recipe.modelContext != nil else { return nil }
        let lines = requirementLines(
            for: recipe,
            lyeCandidates: lyeCandidates,
            neutralizerCandidates: neutralizerCandidates
        )
        guard !lines.isEmpty else { return nil }

        let requirements = lines.map {
            BatchRequirement(
                id: $0.id,
                ingredient: $0.ingredient,
                required: $0.required,
                available: stock.totalRemaining($0.ingredient),
                unit: $0.unit
            )
        }
        let batches = requirements
            .map { Int(min(1e9, (($0.available + 1e-9) / $0.required).rounded(.down))) }
            .min() ?? 0
        let shortages = requirements.filter(\.isShort)
        return Coverage(batches: batches, shortages: shortages)
    }

    private func requirementLines(
        for recipe: Recipe,
        lyeCandidates: [Ingredient],
        neutralizerCandidates: [Ingredient]
    ) -> [RecipeRequirementLine] {
        let key = recipe.persistentModelID
        let fingerprint = RecipeCoverageFingerprint(
            recipe: recipe,
            lyeCandidates: lyeCandidates,
            neutralizerCandidates: neutralizerCandidates
        )
        if let entry = cache[key], entry.fingerprint == fingerprint {
            return entry.lines
        }
        let engine = RecipeRequirementLine.makeEngine(
            for: recipe,
            lyeCandidates: lyeCandidates,
            neutralizerCandidates: neutralizerCandidates
        )
        let lines = RecipeRequirementLine.lines(for: engine, batchCount: 1)
        computeCount += 1
        cache[key] = Entry(fingerprint: fingerprint, lines: lines)
        return lines
    }
}
