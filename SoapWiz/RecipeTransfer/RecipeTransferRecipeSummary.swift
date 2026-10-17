import Foundation

/// One incoming recipe, as the review screen lists it.
@MainActor
struct RecipeTransferRecipeSummary: Identifiable {
    let id: Int
    let recipe: RecipeTransferRecipe

    /// The name it will actually be saved under, which differs from the one it
    /// arrived with when the library already has that name.
    let resolvedName: String

    /// The identity it will actually be saved under: the sender's when it is
    /// new here, a fresh one when the library already holds it. Decided once
    /// when the plan is built, so the screen and the importer cannot disagree
    /// about which recipe was written.
    let resolvedUUID: UUID

    /// The library recipe this one *is*, matched on the payload's uuid, or
    /// `nil` when it is new here or arrived without an identity.
    let knownRecipe: Recipe?

    /// Whether the library has seen this exact recipe before.
    var isKnownRecipe: Bool { knownRecipe != nil }

    /// What the user's own copy is called now, which is the name they will
    /// recognise — the payload's name may be the one the sender changed.
    var knownRecipeName: String {
        guard let name = knownRecipe?.name.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return "Untitled Recipe"
        }
        return name
    }

    /// Whether it had to be renamed to avoid colliding with a recipe the user
    /// already has.
    var isRenamed: Bool {
        resolvedName.lookupKey != recipe.name.trimmingCharacters(in: .whitespaces).lookupKey
    }

    var displayName: String {
        resolvedName.isEmpty ? "Untitled Recipe" : resolvedName
    }

    /// What the sender called it, for the line explaining the rename.
    var incomingName: String {
        let name = recipe.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled Recipe" : name
    }

    /// Kind and size, so a list of fifteen is scannable and a non-soap recipe
    /// is recognisable as one before it is imported.
    var detail: String {
        let kind = recipe.kind == .soap ? "Soap" : "Non-soap"
        let count = recipe.ingredients.count
        return "\(kind) · \(count) \(count == 1 ? "ingredient" : "ingredients")"
    }
}
