import SwiftUI
import SwiftData

struct OilIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var percentage: String = ""
    var isLocked: Bool = false
}

struct AdditiveIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: String = ""
    var unit: String = "g"
}

struct FragranceIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: String = ""
    var unit: String = "ml"
}

struct RecipeProductDraft: Identifiable {
    let id = UUID()
    var size: String = ""
    var unitSymbol: String = ""
}

struct IngredientProductBreakdown {
    let ingredient: Ingredient
    let ingredientAmount: Double
    let cost: Double
}

struct OilAmountCalculation: Identifiable {
    let id: UUID
    let ingredient: Ingredient
    let weightGrams: Double
    let lyeGrams: Double
}

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var weightUnit: String = "g"
    var totalOilWeight: String = ""
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: String = "99"
    var waterParts: String = "2"
    var lyeParts: String = "1"
    var superFat: String = "5"
    var oilDrafts: [OilIngredientDraft] = []
    var additiveDrafts: [AdditiveIngredientDraft] = []
    var fragranceDrafts: [FragranceIngredientDraft] = []
    var productDrafts: [RecipeProductDraft] = []

    @ObservationIgnored
    private var editingRecipe: Recipe?

    var weightUnitIsPercentage: Bool { weightUnit == "%" }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var totalPercentage: Double {
        oilDrafts
            .compactMap { Double($0.percentage.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    private var totalOilWeightInGrams: Double {
        let weight = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
        switch oilWeightUnit {
        case "kg": return weight * 1000
        case "oz": return weight * 28.3495
        case "lb": return weight * 453.592
        default: return weight
        }
    }

    var oilAmountCalculations: [OilAmountCalculation]? {
        guard weightUnitIsPercentage, !oilDrafts.isEmpty else { return nil }
        let totalWeight = totalOilWeightInGrams
        guard totalWeight > 0 else { return nil }
        let purity = Double(lyePurity.replacingOccurrences(of: ",", with: ".")) ?? 99
        let sf = Double(superFat.replacingOccurrences(of: ",", with: ".")) ?? 5

        return oilDrafts.map { draft in
            let pct = Double(draft.percentage.replacingOccurrences(of: ",", with: ".")) ?? 0
            let oilWeight = totalWeight * (pct / 100)
            let sap = draft.ingredient.sapValue ?? 0
            let lye = oilWeight * sap * (1 - sf / 100) / (purity / 100)
            return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weightGrams: oilWeight, lyeGrams: lye)
        }
    }

    var calculatedLyeAmount: Double? {
        oilAmountCalculations.map { $0.reduce(0) { $0 + $1.lyeGrams } }
    }

    var calculatedWaterAmount: Double? {
        guard let lye = calculatedLyeAmount else { return nil }
        let water = Double(waterParts.replacingOccurrences(of: ",", with: ".")) ?? 2
        let lp = Double(lyeParts.replacingOccurrences(of: ",", with: ".")) ?? 1
        return lye * (water / lp)
    }

    func load(from recipe: Recipe) {
        editingRecipe = recipe
        name = recipe.name
        desc = recipe.desc
        weightUnit = recipe.weightUnit
        totalOilWeight = recipe.totalOilWeight > 0 ? format(recipe.totalOilWeight) : ""
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = format(recipe.lyePurity)
        waterParts = format(recipe.waterParts)
        lyeParts = format(recipe.lyeParts)
        superFat = format(recipe.superFat)

        oilDrafts = recipe.ingredients
            .filter { $0.role == "oil" }
            .map { OilIngredientDraft(ingredient: $0.ingredient, percentage: formatPercentage($0.percentage), isLocked: true) }
        additiveDrafts = recipe.ingredients
            .filter { $0.role == "additive" }
            .map { AdditiveIngredientDraft(ingredient: $0.ingredient, amount: format($0.additiveAmount), unit: $0.additiveUnit) }
        fragranceDrafts = recipe.ingredients
            .filter { $0.role == "fragrance" }
            .map { FragranceIngredientDraft(ingredient: $0.ingredient, amount: format($0.additiveAmount), unit: $0.additiveUnit) }

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: format($0.size), unitSymbol: $0.unitSymbol)
        }
    }

    func addOil(_ ingredient: Ingredient) {
        guard !oilDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        oilDrafts.append(OilIngredientDraft(ingredient: ingredient))
        redistributePercentages()
    }

    func removeOil(at offsets: IndexSet) {
        oilDrafts.remove(atOffsets: offsets)
        redistributePercentages()
    }

    func userEdited(id: UUID, percentage: String) {
        guard let idx = oilDrafts.firstIndex(where: { $0.id == id }) else { return }
        oilDrafts[idx].percentage = percentage
        oilDrafts[idx].isLocked = true
        redistributePercentages()
    }

    func addAdditive(_ ingredient: Ingredient) {
        guard !additiveDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        additiveDrafts.append(AdditiveIngredientDraft(ingredient: ingredient))
    }

    func removeAdditive(at offsets: IndexSet) {
        additiveDrafts.remove(atOffsets: offsets)
    }

    func updateAdditive(id: UUID, amount: String? = nil, unit: String? = nil) {
        guard let idx = additiveDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { additiveDrafts[idx].amount = amount }
        if let unit { additiveDrafts[idx].unit = unit }
    }

    func addFragrance(_ ingredient: Ingredient) {
        guard !fragranceDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        fragranceDrafts.append(FragranceIngredientDraft(ingredient: ingredient))
    }

    func removeFragrance(at offsets: IndexSet) {
        fragranceDrafts.remove(atOffsets: offsets)
    }

    func updateFragrance(id: UUID, amount: String? = nil, unit: String? = nil) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { fragranceDrafts[idx].amount = amount }
        if let unit { fragranceDrafts[idx].unit = unit }
    }

    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> (breakdown: [IngredientProductBreakdown], total: Double) {
        let size = Double(product.size.replacingOccurrences(of: ",", with: ".")) ?? 0
        let breakdown = oilDrafts.map { draft in
            let pct = Double(draft.percentage.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ingredientAmount = size * (pct / 100)
            let costPer = weightedCostPerUnit(for: draft.ingredient)
            return IngredientProductBreakdown(
                ingredient: draft.ingredient,
                ingredientAmount: ingredientAmount,
                cost: ingredientAmount * costPer
            )
        }
        return (breakdown, breakdown.reduce(0) { $0 + $1.cost })
    }

    private func weightedCostPerUnit(for ingredient: Ingredient) -> Double {
        let batches = ingredient.batches.filter { $0.quantity > 0 }
        guard !batches.isEmpty else { return 0 }
        let totalCost = batches.reduce(0.0) { $0 + $1.totalPrice }
        let totalQty = batches.reduce(0.0) { $0 + $1.quantity }
        return totalQty > 0 ? totalCost / totalQty : 0
    }

    private func redistributePercentages() {
        let lockedSum = oilDrafts
            .filter(\.isLocked)
            .compactMap { Double($0.percentage.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = oilDrafts.indices.filter { !oilDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = remaining / Double(unlockedIndices.count)
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast()
                    .compactMap { Double(oilDrafts[$0].percentage.replacingOccurrences(of: ",", with: ".")) }
                    .reduce(0, +)
                oilDrafts[idx].percentage = formatPercentage(max(0, remaining - assignedSum))
            } else {
                oilDrafts[idx].percentage = formatPercentage(share)
            }
        }
    }

    private static let percentageFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .autoupdatingCurrent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    func formatPercentage(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return Self.percentageFormatter.string(from: NSNumber(value: rounded)) ?? "0"
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe: Recipe
        if let existing = editingRecipe {
            recipe = existing
        } else {
            recipe = Recipe(name: "", desc: "")
            context.insert(recipe)
        }
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.desc = desc.trimmingCharacters(in: .whitespaces)
        recipe.weightUnit = weightUnit
        recipe.totalOilWeight = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = Double(lyePurity.replacingOccurrences(of: ",", with: ".")) ?? 99
        recipe.waterParts = Double(waterParts.replacingOccurrences(of: ",", with: ".")) ?? 2
        recipe.lyeParts = Double(lyeParts.replacingOccurrences(of: ",", with: ".")) ?? 1
        recipe.superFat = Double(superFat.replacingOccurrences(of: ",", with: ".")) ?? 5

        recipe.ingredients.forEach { context.delete($0) }

        for draft in oilDrafts {
            let pct = Double(draft.percentage.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: pct, role: "oil")
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in additiveDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: "additive")
            ri.additiveAmount = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in fragranceDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: "fragrance")
            ri.additiveAmount = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }

        recipe.products.forEach { context.delete($0) }
        for draft in productDrafts {
            let size = Double(draft.size.replacingOccurrences(of: ",", with: ".")) ?? 0
            let rp = RecipeProduct(size: size, unitSymbol: draft.unitSymbol)
            rp.recipe = recipe
            context.insert(rp)
        }
        return recipe
    }

    private func format(_ value: Double) -> String {
        Self.percentageFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
