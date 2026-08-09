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

    var showsSapValue: Bool {
        selectedCategory?.showsSapValue ?? false
    }

    var showsDensity: Bool {
        selectedUnit == .milliliters || selectedUnit == .liters
    }

    private(set) var codeIsManuallyEdited: Bool = false

    let ingredient: Ingredient?

    private struct Snapshot {
        let name: String
        let code: String
        let unit: IngredientUnit?
        let category: IngredientCategory?
        let lowStockThreshold: String
        let sapValue: String
        let density: String
    }

    private var snapshot: Snapshot?

    init(ingredient: Ingredient? = nil, defaultCategory: IngredientCategory? = nil, prefilledName: String? = nil) {
        self.ingredient = ingredient
        selectedCategory = defaultCategory
        if let prefilledName {
            name = prefilledName
        }
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
        // A new ingredient gets a baseline too: without one an untouched
        // New Ingredient sheet would read as dirty and refuse to dismiss.
        captureSnapshot()
    }

    /// Records the current values as the clean baseline. Call again once any
    /// post-init derivation has run, so it doesn't count as a user edit.
    func captureSnapshot() {
        snapshot = Snapshot(
            name: name,
            code: code,
            unit: selectedUnit,
            category: selectedCategory,
            lowStockThreshold: lowStockThreshold,
            sapValue: sapValue,
            density: density
        )
    }

    /// Whether leaving the form now would lose work.
    var isDirty: Bool {
        guard let snapshot else { return false }
        return name != snapshot.name
            || code != snapshot.code
            || selectedUnit != snapshot.unit
            || selectedCategory !== snapshot.category
            || lowStockThreshold != snapshot.lowStockThreshold
            || sapValue != snapshot.sapValue
            || density != snapshot.density
    }

    var isEditing: Bool { ingredient != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        guard selectedUnit != nil || (isEditing && ingredient?.unit.isEmpty ?? false) else { return false }
        let code = trimmedCode
        if !code.isEmpty && code.count < 3 { return false }
        return true
    }

    func codeHasDuplicate(among ingredients: [Ingredient]) -> Bool {
        let code = trimmedCode
        guard !code.isEmpty else { return false }
        return ingredients.contains { $0 !== ingredient && $0.code.uppercased() == code }
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
            for character in (words.last?.uppercased() ?? "").dropFirst() {
                if candidate.count >= 3 && !normalised.contains(candidate) { return candidate }
                guard candidate.count < 6 else { break }
                candidate.append(character)
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
