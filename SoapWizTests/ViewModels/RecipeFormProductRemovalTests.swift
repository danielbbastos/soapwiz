import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – removing a size", .serialized)
@MainActor
struct RecipeFormProductRemovalTests: RecipeFormTestHelpers {

    /// The whole-batch default followed by one gram size per entry.
    private func makeModel(sizes: [Double]) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.productDrafts = [.wholeBatch()] + sizes.map {
            RecipeProductDraft(size: $0, unitSymbol: ProductUnit.grams.rawValue)
        }
        return model
    }

    @Test func removeProduct_MiddleCard_ReturnsPreviousID() {
        let model = makeModel(sizes: [100, 200, 300])
        let ids = model.productDrafts.map(\.id)

        let result = model.removeProduct(id: ids[2])

        #expect(result == ids[1])
        #expect(model.productDrafts.map(\.id) == [ids[0], ids[1], ids[3]])
    }

    @Test func removeProduct_LastCard_ReturnsPreviousID() {
        let model = makeModel(sizes: [100, 200, 300])
        let ids = model.productDrafts.map(\.id)

        let result = model.removeProduct(id: ids[3])

        #expect(result == ids[2])
        #expect(model.productDrafts.count == 3)
    }

    @Test func removeProduct_OnlyNonDefaultCard_ReturnsDefaultID() {
        let model = makeModel(sizes: [100])
        let ids = model.productDrafts.map(\.id)

        let result = model.removeProduct(id: ids[1])

        #expect(result == ids[0])
        #expect(model.productDrafts.map(\.id) == [ids[0]])
    }

    @Test func removeProduct_DefaultCard_IsRefused() {
        let model = makeModel(sizes: [100])
        let before = model.productDrafts.map(\.id)

        let result = model.removeProduct(id: before[0])

        #expect(result == nil)
        #expect(model.productDrafts.map(\.id) == before)
    }

    @Test func removeProduct_UnknownID_IsNoOp() {
        let model = makeModel(sizes: [100, 200])
        let before = model.productDrafts.map(\.id)

        let result = model.removeProduct(id: UUID())

        #expect(result == nil)
        #expect(model.productDrafts.map(\.id) == before)
    }

    @Test func removeProduct_SeparateSize_DropsSeparateCount() throws {
        let model = makeModel(sizes: [100, 200])
        #expect(model.productDrafts.count(where: \.isSeparateFromBatch) == 2)
        let id = try #require(model.productDrafts.last?.id)

        model.removeProduct(id: id)

        #expect(model.productDrafts.count(where: \.isSeparateFromBatch) == 1)
    }

    @Test func removeProduct_ThenSave_DeletesStoredProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let source = makeModel(sizes: [100, 200])
        source.name = "Test Recipe"
        let recipe = source.save(context: ctx)
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        let removedID = try #require(model.productDrafts.first { $0.size == 100 }?.id)
        model.removeProduct(id: removedID)
        model.save(context: ctx)
        try ctx.save()

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 2)
        #expect(stored.contains { $0.unitSymbol == ProductUnit.wholeBatch.rawValue })
        #expect(stored.contains { $0.size == 200 })
        #expect(!stored.contains { $0.size == 100 })
    }
}
