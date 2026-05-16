import SwiftUI
import SwiftData

struct RecipeIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var percentage: String = ""
    var isLocked: Bool = false
}

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var ingredientDrafts: [RecipeIngredientDraft] = []

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

    private func redistributePercentages() {
        let lockedSum = ingredientDrafts
            .filter(\.isLocked)
            .compactMap { Double($0.percentage.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = ingredientDrafts.indices.filter { !ingredientDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = remaining / Double(unlockedIndices.count)
        for idx in unlockedIndices {
            ingredientDrafts[idx].percentage = formatPercentage(share)
        }
    }

    private static let percentageFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    private func formatPercentage(_ value: Double) -> String {
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
        return recipe
    }
}
