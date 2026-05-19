import SwiftUI
import SwiftData

struct RecipeIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var percentage: String = ""
    var isLocked: Bool = false
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

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var ingredientDrafts: [RecipeIngredientDraft] = []
    var productDrafts: [RecipeProductDraft] = []

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var totalPercentage: Double {
        ingredientDrafts
            .compactMap { Double($0.percentage.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    func addIngredient(_ ingredient: Ingredient) {
        guard !ingredientDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        ingredientDrafts.append(RecipeIngredientDraft(ingredient: ingredient))
        redistributePercentages()
    }

    func removeIngredient(at offsets: IndexSet) {
        ingredientDrafts.remove(atOffsets: offsets)
        redistributePercentages()
    }

    func userEdited(id: UUID, percentage: String) {
        guard let idx = ingredientDrafts.firstIndex(where: { $0.id == id }) else { return }
        ingredientDrafts[idx].percentage = percentage
        ingredientDrafts[idx].isLocked = true
        redistributePercentages()
    }

    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> (breakdown: [IngredientProductBreakdown], total: Double) {
        let size = Double(product.size.replacingOccurrences(of: ",", with: ".")) ?? 0
        let breakdown = ingredientDrafts.map { draft in
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
        let lockedSum = ingredientDrafts
            .filter(\.isLocked)
            .compactMap { Double($0.percentage.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = ingredientDrafts.indices.filter { !ingredientDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = remaining / Double(unlockedIndices.count)
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast()
                    .compactMap { Double(ingredientDrafts[$0].percentage.replacingOccurrences(of: ",", with: ".")) }
                    .reduce(0, +)
                ingredientDrafts[idx].percentage = formatPercentage(max(0, remaining - assignedSum))
            } else {
                ingredientDrafts[idx].percentage = formatPercentage(share)
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
        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            desc: desc.trimmingCharacters(in: .whitespaces)
        )
        context.insert(recipe)
        for draft in ingredientDrafts {
            let pct = Double(draft.percentage.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: pct)
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in productDrafts {
            let size = Double(draft.size.replacingOccurrences(of: ",", with: ".")) ?? 0
            let rp = RecipeProduct(size: size, unitSymbol: draft.unitSymbol)
            rp.recipe = recipe
            context.insert(rp)
        }
        return recipe
    }
}
