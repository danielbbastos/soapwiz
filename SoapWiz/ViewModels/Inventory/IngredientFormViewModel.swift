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
    var kohSapValue: String = ""
    var density: String = ""

    /// The oil's fatty-acid make-up. Held as a value, edited in place by the
    /// profile editor; `.zero` means unspecified and is saved as `nil`.
    var fattyAcidProfile: FattyAcidProfile = .zero

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

    /// The edited ingredient's merge key, read in `init` while the row is
    /// certainly still in the store — it cannot be recovered later, because
    /// reading a stored attribute off a detached model is not safe. Empty when
    /// creating, which has no row to go stale. See `LiveIngredient`.
    private let ingredientSlug: String

    /// Whether the edited row's stored unit was blank, read in `init` for the
    /// same reason as `ingredientSlug`. `isValid` drives the Save button, so it
    /// runs on every render — including after the merge deleted the row this
    /// sheet was opened on, where reading `unit` off the captured reference
    /// would trap.
    private let capturedUnitIsEmpty: Bool

    /// The edited row's stored chemistry and library standing, captured in `init`
    /// for the same reason as `ingredientSlug`. `changesLibraryChemistry` is read
    /// while the Save button is being drawn, so it cannot go to the model for them.
    private let capturedIsLibraryInstalled: Bool
    private let capturedSapValue: Double?
    private let capturedKohSapValue: Double?
    private let capturedDensity: Double?
    private let capturedFattyAcidProfile: FattyAcidProfile?

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
        let kohSapValue: String
        let density: String
        let fattyAcidProfile: FattyAcidProfile
        let imageData: Data?
    }

    private var snapshot: Snapshot?

    init(ingredient: Ingredient? = nil, defaultCategory: IngredientCategory? = nil, prefilledName: String? = nil) {
        self.ingredient = ingredient
        self.ingredientSlug = ingredient?.librarySlug ?? ""
        self.capturedUnitIsEmpty = ingredient?.unit.isEmpty ?? false
        self.capturedIsLibraryInstalled = ingredient?.isLibraryInstalled ?? false
        self.capturedSapValue = ingredient?.sapValue
        self.capturedKohSapValue = ingredient?.kohSapValue
        self.capturedDensity = ingredient?.density
        self.capturedFattyAcidProfile = ingredient?.fattyAcidProfile
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
            if let kohSap = ingredient.kohSapValue {
                kohSapValue = kohSap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
            }
            if let dens = ingredient.density {
                density = dens.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
            }
            if let profile = ingredient.fattyAcidProfile {
                fattyAcidProfile = profile
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
            kohSapValue: kohSapValue,
            density: density,
            fattyAcidProfile: fattyAcidProfile,
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
            || kohSapValue != snapshot.kohSapValue
            || density != snapshot.density
            || fattyAcidProfile != snapshot.fattyAcidProfile
            || imageData != snapshot.imageData
    }

    var isEditing: Bool { ingredient != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        guard selectedUnit != nil || (isEditing && capturedUnitIsEmpty) else { return false }
        let code = trimmedCode
        if !code.isEmpty && code.count < 3 { return false }
        return true
    }

    /// Excludes the row being edited by slug as well as by identity. The merge
    /// replaces that row with a different object, and an identity check against
    /// the copy it deleted would read the survivor's own code as somebody else's
    /// — reporting a duplicate of itself and disabling Save with no way out.
    func codeHasDuplicate(among ingredients: [Ingredient]) -> Bool {
        let code = trimmedCode
        guard !code.isEmpty else { return false }
        return ingredients.contains { candidate in
            guard candidate !== ingredient else { return false }
            // Only library rows are ever merged away, so a blank slug has no
            // twin to stand in for it and falls back to identity alone.
            guard ingredientSlug.isEmpty || candidate.librarySlug != ingredientSlug else { return false }
            return candidate.code.uppercased() == code
        }
    }

    func applyNameChange(existingCodes: [String]) {
        guard !codeIsManuallyEdited else { return }
        code = suggestCode(for: trimmedName, existingCodes: existingCodes)
    }

    func markCodeEdited() {
        codeIsManuallyEdited = true
    }

    func suggestCode(for name: String, existingCodes: [String]) -> String {
        IngredientCodeSuggester.suggest(for: name, existingCodes: existingCodes)
    }

    /// The SAP value this save would write: the parsed field while it is on screen,
    /// and the stored value left untouched while it isn't.
    ///
    /// Preserving rather than nulling is what stops a unit or category edit quietly
    /// dropping chemistry. Density in particular belongs to the substance, not to the
    /// unit it happens to be bought in, so moving an oil from ml to g must not erase
    /// it.
    private var sapValueToSave: Double? {
        guard showsSapValue else { return capturedSapValue }
        return Double(sapValue.replacingOccurrences(of: ",", with: "."))
    }

    /// The KOH SAP value this save would write. Preserved when off-screen, for the
    /// same reason as `sapValueToSave`: a non-oil edit must not drop it.
    private var kohSapValueToSave: Double? {
        guard showsSapValue else { return capturedKohSapValue }
        return Double(kohSapValue.replacingOccurrences(of: ",", with: "."))
    }

    private var densityToSave: Double? {
        guard showsDensity else { return capturedDensity }
        return Double(density.replacingOccurrences(of: ",", with: "."))
    }

    /// The profile this save would write. Preserved when off-screen; an unspecified
    /// (all-zero) profile is stored as `nil` so a recipe's completeness check can
    /// tell "no data" from a real oil.
    private var fattyAcidProfileToSave: FattyAcidProfile? {
        guard showsSapValue else { return capturedFattyAcidProfile }
        return fattyAcidProfile.isEmpty ? nil : fattyAcidProfile
    }

    /// Whether saving would change a library ingredient's chemistry, which is what
    /// makes it a custom one. Weighs every editable chemistry field; name, code,
    /// category and unit edits are excluded by construction — they reach chemistry
    /// only through the `…ToSave` values, which preserve it.
    var changesLibraryChemistry: Bool {
        guard capturedIsLibraryInstalled else { return false }
        return sapValueToSave != capturedSapValue
            || kohSapValueToSave != capturedKohSapValue
            || densityToSave != capturedDensity
            || fattyAcidProfileToSave != capturedFattyAcidProfile
    }

    @discardableResult
    func save(context: ModelContext) -> Ingredient? {
        let parsedThreshold = Double(lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        let savedSap = sapValueToSave
        let savedKohSap = kohSapValueToSave
        let savedDensity = densityToSave
        let savedProfile = fattyAcidProfileToSave
        let becomesCustom = changesLibraryChemistry
        let savedCode = trimmedCode
        if let captured = ingredient {
            // The merge can delete the row this sheet was opened on while it is
            // still up, and writing to the detached reference would drop the edit
            // with no trace at all. The write follows the merge onto the survivor
            // instead. A row deleted outright has no survivor to find, and
            // falling back to the captured reference leaves that case as it was.
            let ingredient = LiveIngredient.resolve(captured, slug: ingredientSlug, in: context) ?? captured

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
            ingredient.sapValue = savedSap
            ingredient.kohSapValue = savedKohSap
            ingredient.density = savedDensity
            ingredient.fattyAcidProfile = savedProfile
            // Never cleared here: a row the user has taken over stays theirs, even
            // if a later edit happens to land back on the bundled values.
            if becomesCustom {
                ingredient.hasCustomChemistry = true
            }
            applyImage(to: ingredient)
            return nil
        } else {
            let newIngredient = Ingredient(name: trimmedName, category: selectedCategory, unit: selectedUnit?.rawValue ?? "")
            newIngredient.avatarColorName = avatarColor.rawValue
            newIngredient.code = savedCode
            newIngredient.lowStockThreshold = parsedThreshold
            newIngredient.sapValue = savedSap
            newIngredient.kohSapValue = savedKohSap
            newIngredient.density = savedDensity
            newIngredient.fattyAcidProfile = savedProfile
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
