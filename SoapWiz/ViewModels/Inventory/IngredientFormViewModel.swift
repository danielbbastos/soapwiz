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

    /// The display-sized photo, already downscaled by `PhotoField` before it
    /// lands here. The thumbnail is derived from it on save rather than carried
    /// alongside it, so the two can never disagree.
    var imageData: Data?

    var showsSapValue: Bool {
        selectedCategory?.showsSapValue ?? false
    }

    var showsDensity: Bool {
        selectedUnit == .milliliters || selectedUnit == .liters
    }

    private(set) var codeIsManuallyEdited: Bool = false

    let ingredient: Ingredient?

    /// The colour the form's avatar shows, and the one a new ingredient is saved
    /// with. Drawn once here rather than left to `Ingredient.init` so the well
    /// the user looked at while filling the form is the colour the row ends up
    /// wearing.
    let avatarColor: AvatarColor

    /// The initial the avatar draws, following the name as it is typed.
    var avatarLetter: String { name.avatarInitial }

    private struct Snapshot {
        let name: String
        let code: String
        let unit: IngredientUnit?
        let category: IngredientCategory?
        let lowStockThreshold: String
        let sapValue: String
        let density: String
        let imageData: Data?
    }

    private var snapshot: Snapshot?

    init(ingredient: Ingredient? = nil, defaultCategory: IngredientCategory? = nil, prefilledName: String? = nil) {
        self.ingredient = ingredient
        avatarColor = ingredient?.avatarColor ?? .random()
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
            imageData = ingredient.imageData
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
            density: density,
            imageData: imageData
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
            || imageData != snapshot.imageData
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
            // An ingredient that predates avatars has no stored colour and takes
            // one derived from its name, so renaming it would move it to a
            // different colour. Written down here, while the old name is still
            // in place, it keeps the colour the user has been looking at.
            if ingredient.avatarColorName.isEmpty {
                ingredient.avatarColorName = ingredient.avatarColor.rawValue
            }
            ingredient.name = trimmedName
            ingredient.code = savedCode
            ingredient.category = selectedCategory
            ingredient.unit = selectedUnit?.rawValue ?? ""
            ingredient.lowStockThreshold = parsedThreshold
            ingredient.sapValue = showsSapValue ? parsedSap : nil
            ingredient.density = showsDensity ? parsedDensity : nil
            applyImage(to: ingredient)
            return nil
        } else {
            let newIngredient = Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit?.rawValue ?? "")
            newIngredient.avatarColorName = avatarColor.rawValue
            newIngredient.code = savedCode
            newIngredient.lowStockThreshold = parsedThreshold
            newIngredient.sapValue = showsSapValue ? parsedSap : nil
            newIngredient.density = showsDensity ? parsedDensity : nil
            applyImage(to: newIngredient)
            context.insert(newIngredient)
            return newIngredient
        }
    }

    /// Writes the photo and the thumbnail derived from it. The two always move
    /// together: a stale thumbnail beside a replaced photo would show the old
    /// picture in the list and the new one on the detail screen, and a thumbnail
    /// left behind by a removed photo would show an ingredient that no longer
    /// has one.
    ///
    /// The image is only rewritten when it actually changed, so re-saving an
    /// untouched ingredient doesn't rewrite the external file and hand CloudKit
    /// an asset to re-upload.
    private func applyImage(to ingredient: Ingredient) {
        guard ingredient.imageData != imageData else { return }
        ingredient.imageData = imageData
        ingredient.thumbnailData = imageData.flatMap(ImageDownscaler.thumbnail(from:))
    }
}
