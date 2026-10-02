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

    @Test(arguments: [1.0, 0.5, 1.5, 2.5])
    func saveProducts_PartsOfBatchNotAWholeNumberOfTwoOrMore_IsNotStored(size: Double) throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: size, unitSymbol: ProductUnit.partsOfBatch.rawValue))
        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 1)
        #expect(stored.first?.unitSymbol == ProductUnit.wholeBatch.rawValue)
    }

    @Test(arguments: [2.0, 3.0])
    func saveProducts_PartsOfBatchWholeNumberOfTwoOrMore_IsStored(size: Double) throws {
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

        model.productDrafts[1].size = 3
        try model.saveProducts(context: ctx)

        let restored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(restored.count { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue && $0.size == 3 } == 1)
        #expect(restored.count == 2)
    }

    @Test func saveProducts_InvalidDraftBetweenDefaultAndNewSize_StampsTheRightDraft() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        model.productDrafts.append(RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue))
        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try #require(model.productDrafts.count == 3)

        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        let grams = try #require(stored.first { $0.unitSymbol == ProductUnit.grams.rawValue })
        #expect(model.productDrafts[2].modelID == grams.persistentModelID)
        #expect(model.productDrafts[1].modelID == nil)

        try model.saveProducts(context: ctx)

        let again = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(again.count { $0.unitSymbol == ProductUnit.grams.rawValue } == 1)
    }

    @Test(arguments: [(0.0, 2.0), (0.5, 2.0), (1.0, 2.0), (1.5, 2.0), (3.0, 3.0)])
    func selectUnit_PartsOfBatch_SnapsSizeToWholeNumberOfTwoOrMore(start: Double, expected: Double) {
        var draft = RecipeProductDraft(size: start, unitSymbol: ProductUnit.grams.rawValue)

        draft.selectUnit(.partsOfBatch)

        #expect(draft.unitSymbol == ProductUnit.partsOfBatch.rawValue)
        #expect(draft.size == expected)
    }

    @Test(arguments: [(0.0, 1.0), (250.0, 250.0)])
    func selectUnit_Grams_OnlyFillsAnEmptySize(start: Double, expected: Double) {
        var draft = RecipeProductDraft(size: start, unitSymbol: ProductUnit.partsOfBatch.rawValue)

        draft.selectUnit(.grams)

        #expect(draft.unitSymbol == ProductUnit.grams.rawValue)
        #expect(draft.size == expected)
    }
}
