import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Two stores and the trip between them: a sender's library, a recipient's, and
/// the export/import that carries a recipe from one to the other.
///
/// Shared by the round-trip suites, which are split by what they assert rather
/// than by how they get there. Both need the same journey, and two copies of it
/// would be two things to keep in step.
@MainActor
struct RecipeTransferRoundTripHarness {
    let source: RecipeTransferFixture
    let destination: RecipeTransferFixture

    init() throws {
        source = try RecipeTransferFixture()
        destination = try RecipeTransferFixture()
    }

    /// Exports from the sender's store and imports into the recipient's,
    /// through the file transport.
    @discardableResult
    func roundTrip(_ recipes: [Recipe], collections: [RecipeCollection] = []) throws -> [Recipe] {
        source.context.processPendingChanges()
        let data = try RecipeTransferEncoder.fileData(for: recipes)
        let payload = try RecipeTransferDecoder.payload(fromFile: data)
        return try importIntoDestination(payload, collections: collections)
    }

    /// The receiving half on its own, for a test that built its payload some
    /// other way — over the clipboard, or by hand.
    @discardableResult
    func importIntoDestination(
        _ payload: RecipeTransferData,
        collections: [RecipeCollection] = []
    ) throws -> [Recipe] {
        let inventory = try destination.context.fetch(FetchDescriptor<Ingredient>())
        let categories = try destination.context.fetch(FetchDescriptor<IngredientCategory>())
        let existing = try destination.context.fetch(FetchDescriptor<Recipe>())
        let plan = RecipeTransferPlan(
            payload: payload,
            inventory: inventory,
            collections: collections,
            recipes: existing
        )
        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: categories)
        destination.context.processPendingChanges()
        return imported
    }

    /// Everything in the recipient's store of one kind, for asserting what an
    /// import created or left alone.
    func received<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try destination.context.fetch(FetchDescriptor<T>())
    }
}

extension RecipeTransferFixture {
    /// The payload for these recipes, with the store settled first so every
    /// line item and product is visible to the encoder.
    func payload(_ recipes: [Recipe]) -> RecipeTransferData {
        context.processPendingChanges()
        return RecipeTransferEncoder.payload(for: recipes)
    }

    /// The fixture's own ingredients, for a test that needs the language-model
    /// path to have something to reconcile against.
    func inventoryForImport() -> [Ingredient] {
        (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
    }
}
