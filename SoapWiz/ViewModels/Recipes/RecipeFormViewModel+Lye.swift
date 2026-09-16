import Foundation
import SwiftData

/// Choosing the lye: the single/hybrid split, the purities that come with each
/// lye type, and resolving the ingredient rows the lye is drawn from. Kept apart
/// from the view-model's live editing state, like the persistence and dirty-state
/// halves. The amounts themselves are `LyeCalculator`'s.
extension RecipeFormViewModel {

    /// Standard single-lye purities: NaOH ships near-anhydrous (~99%), KOH is
    /// hygroscopic and sold at ~90%.
    static let defaultNaOHPurity = 99.0
    static let defaultKOHPurity = 90.0

    /// Switches the single lye type, moving `lyePurity` to the new lye's standard
    /// default — but only when it still holds the other lye's default, so a value
    /// the user set deliberately is preserved.
    func setLyeType(_ type: String) {
        if type == "KOH", lyePurity == Self.defaultNaOHPurity {
            lyePurity = Self.defaultKOHPurity
        } else if type == "NaOH", lyePurity == Self.defaultKOHPurity {
            lyePurity = Self.defaultNaOHPurity
        }
        lyeType = type
    }

    /// Sets the KOH share (clamped 0–100) and keeps NaOH as the complement so the
    /// split always sums to 100.
    func setKOHPercentage(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        kohPercentage = clamped
        naohPercentage = 100 - clamped
    }

    /// Sets the NaOH share (clamped 0–100), keeping KOH as the complement.
    func setNaOHPercentage(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        naohPercentage = clamped
        kohPercentage = 100 - clamped
    }

    /// The lye rows a recipe may pick from: the visible ones, plus whichever lye the
    /// recipe already uses, even when that one has since been hidden.
    ///
    /// Hiding a lye says "I don't use this" and rightly takes it out of the choices,
    /// but it must never strip the lye out of a recipe already built on it — the
    /// batch sheet still has to offer it, or that recipe silently stops producing.
    static func lyeCandidates(visible: [Ingredient], keeping current: [Ingredient?]) -> [Ingredient] {
        var seen: Set<PersistentIdentifier> = []
        return (visible + current.compactMap { $0 })
            .filter { seen.insert($0.persistentModelID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func resolveDefaultLyeIngredient(from inventory: [Ingredient]) {
        let candidates = inventory.filter { $0.category?.name == IngredientCategory.Name.lyes }
        guard !candidates.isEmpty else { return }

        func match(_ name: String) -> Ingredient? {
            candidates.first { $0.name.lowercased().contains(name) }
        }

        // Resolving only ever fills a blank, so the baseline moves with it — a
        // lye ingredient arriving late from CloudKit isn't a user edit.
        if lyeIngredient == nil {
            // Single lye is currently always NaOH; the hybrid path's NaOH portion
            // shares this ingredient.
            lyeIngredient = match("sodium hydroxide") ?? candidates.first
            snapshot?.lyeIngredient = lyeIngredient
        }
        if kohLyeIngredient == nil {
            kohLyeIngredient = match("potassium hydroxide") ?? candidates.first
            snapshot?.kohLyeIngredient = kohLyeIngredient
        }
    }
}
