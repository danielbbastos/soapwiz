import Foundation
import SwiftData

@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var code: String = ""
    var selectedUnit: IngredientUnit?
    var selectedCategory: IngredientCategory?
    var lowStockThreshold: String = ""
    var sapValue: String = ""
    var density: String = ""

    private static let oilCategoryNames: Set<String> = ["Oils", "Waxes", "Fats"]

    var showsSapValue: Bool {
        selectedCategory.map { Self.oilCategoryNames.contains($0.name) } ?? false
    }

    var showsDensity: Bool {
        selectedUnit == .milliliters || selectedUnit == .liters
    }

    private(set) var codeIsManuallyEdited: Bool = false

    let ingredient: Ingredient?

    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        if let ingredient {
            name = ingredient.name
            code = ingredient.code
            selectedUnit = IngredientUnit(rawValue: ingredient.unit)
            selectedCategory = ingredient.category
            if let threshold = ingredient.lowStockThreshold {
                lowStockThreshold = threshold.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
            if let sap = ingredient.sapValue {
                sapValue = sap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
            }
            if let dens = ingredient.density {
                density = dens.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
            }
        }
    }

    var isEditing: Bool { ingredient != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        guard selectedUnit != nil || (isEditing && ingredient?.unit.isEmpty ?? false) else { return false }
        let c = trimmedCode
        if !c.isEmpty && c.count < 3 { return false }
        return true
    }

    func codeHasDuplicate(among ingredients: [Ingredient]) -> Bool {
        let c = trimmedCode
        guard !c.isEmpty else { return false }
        return ingredients.contains { $0 !== ingredient && $0.code.uppercased() == c }
    }

    func applyNameChange(existingCodes: [String]) {
        guard !codeIsManuallyEdited else { return }
        code = suggestCode(for: trimmedName, existingCodes: existingCodes)
    }

    func markCodeEdited() {
        codeIsManuallyEdited = true
    }

    func suggestCode(for name: String, existingCodes: [String]) -> String {
        let normalised = existingCodes.map { $0.uppercased() }
        let stripped = name.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let words = stripped.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }

        if words.count > 1 {
            let initials = words.map { String($0.prefix(1)).uppercased() }.joined()
            var candidate = initials
            for ch in (words.last?.uppercased() ?? "").dropFirst() {
                if candidate.count >= 3 && !normalised.contains(candidate) { return candidate }
                guard candidate.count < 6 else { break }
                candidate.append(ch)
            }
            return candidate
        } else {
            // Single word — take first 3 chars, extend if not unique
            let upper = words[0].uppercased()
            for length in 3...6 {
                guard length <= upper.count else { break }
                let candidate = String(upper.prefix(length))
                if !normalised.contains(candidate) { return candidate }
            }
            // Return best-effort (may still conflict if word is very short)
            return String(upper.prefix(min(6, upper.count)))
        }
    }

    @discardableResult
    func save(context: ModelContext) -> Ingredient? {
        let parsedThreshold = Double(lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        let parsedSap = Double(sapValue.replacingOccurrences(of: ",", with: "."))
        let parsedDensity = Double(density.replacingOccurrences(of: ",", with: "."))
        let savedCode = trimmedCode
        if let ingredient {
            ingredient.name = trimmedName
            ingredient.code = savedCode
            ingredient.category = selectedCategory
            ingredient.unit = selectedUnit?.rawValue ?? ""
            ingredient.lowStockThreshold = parsedThreshold
            ingredient.sapValue = showsSapValue ? parsedSap : nil
            ingredient.density = showsDensity ? parsedDensity : nil
            return nil
        } else {
            let newIngredient = Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit?.rawValue ?? "")
            newIngredient.code = savedCode
            newIngredient.lowStockThreshold = parsedThreshold
            newIngredient.sapValue = showsSapValue ? parsedSap : nil
            newIngredient.density = showsDensity ? parsedDensity : nil
            context.insert(newIngredient)
            return newIngredient
        }
    }
}
