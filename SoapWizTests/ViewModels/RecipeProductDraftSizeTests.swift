import Testing
@testable import SoapWiz

/// Which product sizes the cost screens list and count separately from the
/// whole-batch total.
@Suite("RecipeProductDraft – separate from batch")
struct RecipeProductDraftSizeTests {

    @Test func isSeparateFromBatch_WholeBatch_IsFalse() {
        #expect(!RecipeProductDraft(size: 1, unitSymbol: ProductUnit.wholeBatch.rawValue).isSeparateFromBatch)
    }

    @Test func isSeparateFromBatch_OnePartOfBatch_IsFalse() {
        #expect(!RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue).isSeparateFromBatch)
    }

    @Test func isSeparateFromBatch_SeededPlaceholder_IsFalse() {
        #expect(!RecipeProductDraft.seededPlaceholder().isSeparateFromBatch)
    }

    @Test func isSeparateFromBatch_SeveralPartsOfBatch_IsTrue() {
        #expect(RecipeProductDraft(size: 4, unitSymbol: ProductUnit.partsOfBatch.rawValue).isSeparateFromBatch)
    }

    @Test func isSeparateFromBatch_WeightSize_IsTrue() {
        #expect(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue).isSeparateFromBatch)
    }

    @Test func isSeparateFromBatch_UnknownUnit_IsTrue() {
        #expect(RecipeProductDraft(size: 100, unitSymbol: "bar").isSeparateFromBatch)
    }
}
