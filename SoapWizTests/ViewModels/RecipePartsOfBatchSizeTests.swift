import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A "parts of batch" size has to be more than one part, or it is not stored.
@Suite("RecipeForm – parts of batch size rule", .serialized)
@MainActor
struct RecipePartsOfBatchSizeTests: RecipeFormTestHelpers {

    private func makeLoadedModel(ctx: ModelContext, storedParts: Double? = nil) throws -> RecipeFormViewModel {
        let recipe = Recipe(name: "Parts", desc: "")
        ctx.insert(recipe)
        if let storedParts {
            let product = RecipeProduct(size: storedParts, unitSymbol: ProductUnit.partsOfBatch.rawValue)
            product.recipe = recipe
            ctx.insert(product)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        return model
    }

    @Test(arguments: [1.0, 0.5])
    func saveProducts_PartsOfBatchAtOrBelowOne_IsNotStored(size: Double) throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: size, unitSymbol: ProductUnit.partsOfBatch.rawValue))
        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 1)
        #expect(stored.first?.unitSymbol == ProductUnit.wholeBatch.rawValue)
    }

    @Test(arguments: [1.5, 2.0])
    func saveProducts_PartsOfBatchAboveOne_IsStored(size: Double) throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: size, unitSymbol: ProductUnit.partsOfBatch.rawValue))
        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 2)
        #expect(stored.contains { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue && $0.size == size })
    }

    @Test func saveProducts_StoredPartsRowEditedToOne_IsDeleted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx, storedParts: 3)
        try #require(model.productDrafts.count == 2)

        model.productDrafts[1].size = 1
        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 1)
        #expect(stored.first?.unitSymbol == ProductUnit.wholeBatch.rawValue)
    }
}
