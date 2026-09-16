import Foundation
import SwiftData

/// Resolves an `Ingredient` a screen captured earlier back to the row that is
/// actually in the store.
///
/// `DuplicateMerger` deletes the losing copy of a duplicated library ingredient,
/// and a screen that captured that row before the merge ran still holds it. The
/// reference is then detached: `isDeleted` reads `false` on it, so a write site
/// cannot tell, and appending a child to it loses the child — the cascade on
/// `Ingredient.purchases` takes the new row down with the dead parent. That is
/// how SW-136 lost a purchase leaving no orphan behind.
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
        guard !slug.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.librarySlug == slug })
        let candidates = (try? context.fetch(descriptor)) ?? []
        // The merge keeps the lowest `uuid`, so resolving the same way lands on
        // the row it kept even when a later import has yet to be collapsed.
        return candidates.min { $0.uuid.uuidString < $1.uuid.uuidString }
    }
}
