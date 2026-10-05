import Foundation
import SwiftData

/// Moving an open form off rows the duplicate merge deleted.
///
/// The form reads its rows through the ingredients and collections it holds,
/// so one of them merged away is a crash on the next redraw — reading a stored
/// attribute off a detached model traps. See `LiveIngredient`.
extension RecipeFormViewModel {
    /// Puts every draft, the lye and neutraliser rows and the selected
    /// collections on the row the merge kept. An ingredient row with nothing
    /// left to move onto is dropped: the line item it came from lost its
    /// ingredient too, and `load(from:)` counts those into
    /// `unresolvedLineItemCount`.
    ///
    /// The baseline moves the same way, so a merge isn't mistaken for an edit.
    func resolveMergedRows(in context: ModelContext) {
        let capturedLye = lyeIngredient
        let capturedKOHLye = kohLyeIngredient
        let capturedNeutralizer = neutralizerIngredient
        let lye = capturedLye.flatMap { LiveIngredient.resolve($0, slug: lyeIngredientSlug, in: context) }
        let kohLye = capturedKOHLye.flatMap { LiveIngredient.resolve($0, slug: kohLyeIngredientSlug, in: context) }
        let neutralizer = capturedNeutralizer.flatMap {
            LiveIngredient.resolve($0, slug: neutralizerIngredientSlug, in: context)
        }
        let collections = storedCollections(in: context)

        oilDrafts = oilDrafts.compactMap { $0.resolved(in: context) }
        additiveDrafts = additiveDrafts.compactMap { $0.resolved(in: context) }
        fragranceDrafts = fragranceDrafts.compactMap { $0.resolved(in: context) }
        lyeIngredient = lye
        kohLyeIngredient = kohLye
        neutralizerIngredient = neutralizer
        selectedCollections = resolved(selectedCollections, among: collections)

        guard var baseline = snapshot else { return }
        baseline.oilDrafts = baseline.oilDrafts.compactMap { $0.resolved(in: context) }
        baseline.additiveDrafts = baseline.additiveDrafts.compactMap { $0.resolved(in: context) }
        baseline.fragranceDrafts = baseline.fragranceDrafts.compactMap { $0.resolved(in: context) }
        baseline.lyeIngredient = Self.baselineRow(baseline.lyeIngredient, captured: capturedLye, resolved: lye)
        baseline.kohLyeIngredient = Self.baselineRow(
            baseline.kohLyeIngredient, captured: capturedKOHLye, resolved: kohLye
        )
        baseline.neutralizerIngredient = Self.baselineRow(
            baseline.neutralizerIngredient, captured: capturedNeutralizer, resolved: neutralizer
        )
        baseline.selectedCollections = resolved(baseline.selectedCollections, among: collections)
        snapshot = baseline
    }

    /// The baseline's row once the form's own has been resolved. The common case
    /// is the same row, which follows it. One the user has since replaced has no
    /// slug recorded to resolve by, so if it was merged away it is cleared — the
    /// form already differs from the baseline there, so it stays dirty either way.
    private static func baselineRow(_ row: Ingredient?, captured: Ingredient?, resolved: Ingredient?) -> Ingredient? {
        guard let row else { return nil }
        if row === captured { return resolved }
        return row.modelContext == nil ? nil : row
    }

    // MARK: - Collections

    private func storedCollections(in context: ModelContext) -> [RecipeCollection] {
        (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? []
    }

    /// `selection` with each merged-away collection replaced by the one the
    /// merge kept for its name — the lowest `uuid`, as the merge decides. The
    /// survivor may already be selected, so it is only listed once.
    private func resolved(_ selection: [RecipeCollection], among stored: [RecipeCollection]) -> [RecipeCollection] {
        var result: [RecipeCollection] = []
        for collection in selection {
            let live: RecipeCollection? = if collection.modelContext != nil {
                collection
            } else {
                collectionMergeKeys[ObjectIdentifier(collection)].flatMap { key in
                    stored.filter { $0.name.lookupKey == key }.min { $0.uuid.uuidString < $1.uuid.uuidString }
                }
            }
            if let live, !result.contains(where: { $0 === live }) {
                result.append(live)
            }
        }
        return result.sortedByName
    }
}
