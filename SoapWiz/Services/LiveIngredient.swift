import Foundation
import SwiftData

/// Resolves an `Ingredient` a screen captured earlier back to the row that is
/// actually in the store.
///
/// `DuplicateMerger` deletes the losing copy of a duplicated library ingredient,
/// and a screen that captured that row before the merge ran still holds it. The
/// reference is then detached: `isDeleted` reads `false` on it, so a write site
/// cannot tell, and a child appended to it can't keep its link. In SW-136 the
/// then-cascading `Ingredient.purchases` took the new row down with the dead
/// parent, losing a purchase without leaving an orphan behind.
///
/// The key has to be captured while the row is still alive. Reading a stored
/// attribute off a detached model traps — the same hazard `RestoreCoordinator`
/// tears the interface down to avoid — so the caller records `librarySlug` when
/// it captures the ingredient and passes it back here. The only thing read off
/// the stale reference is `modelContext`, which, unlike `isDeleted`, is
/// truthful once the row is gone.
@MainActor
enum LiveIngredient {
    /// `captured` itself while it is still in a context, otherwise the surviving
    /// row carrying `slug`, or `nil` when neither is available.
    ///
    /// Only library rows are ever merged away: a user-created ingredient has no
    /// slug and `DuplicateMerger` leaves it alone, so an empty `slug` has nothing
    /// to resolve to and returns `nil` rather than guessing by name.
    ///
    /// A `nil` context also means "never inserted". That is safe here because
    /// every caller captures an ingredient that was already persisted when the
    /// screen opened.
    static func resolve(_ captured: Ingredient, slug: String, in context: ModelContext) -> Ingredient? {
        if captured.modelContext != nil { return captured }
        return survivor(slug: slug, excluding: captured, in: context)
    }

    /// The row stored under `id`, otherwise the survivor carrying `slug`, or
    /// `nil` when neither exists. For a caller that kept only an id: one taken
    /// from a row the merge has since deleted no longer fetches, and the slug
    /// recorded beside it finds the row that was kept instead.
    static func storedRow(id: PersistentIdentifier, slug: String, in context: ModelContext) -> Ingredient? {
        let byID = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.persistentModelID == id })
        if let row = try? context.fetch(byID).first { return row }
        guard !slug.isEmpty else { return nil }

        let bySlug = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.librarySlug == slug })
        return ((try? context.fetch(bySlug)) ?? []).min { $0.uuid.uuidString < $1.uuid.uuidString }
    }

    /// The row carrying `slug` other than `gone`, for a caller that already
    /// knows `gone` has left the store, however SwiftData reports it: a delete
    /// synced from another device isn't certain to detach the instance, and
    /// `resolve` trusts any instance still in a context. `nil` when no other
    /// row carries the slug, which means `gone` was deleted outright.
    static func survivor(slug: String, excluding gone: Ingredient, in context: ModelContext) -> Ingredient? {
        guard !slug.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.librarySlug == slug })
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter { $0 !== gone && !$0.isDeleted }
        // The merge keeps the lowest `uuid`, so resolving the same way lands on
        // the row it kept even when a later import has yet to be collapsed.
        return candidates.min { $0.uuid.uuidString < $1.uuid.uuidString }
    }
}
