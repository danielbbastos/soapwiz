import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportReviewViewModel", .serialized)
@MainActor
struct InventoryImportReviewViewModelTests {

    private typealias Support = InventoryImportTestSupport

    private func makeModel(
        _ rows: [InventoryImportRow],
        inventory: [Ingredient] = []
    ) -> InventoryImportReviewViewModel {
        InventoryImportReviewViewModel(plan: Support.plan(rows, inventory: inventory))
    }

    private func ingredients(in context: ModelContext) throws -> [Ingredient] {
        try context.fetch(FetchDescriptor<Ingredient>())
    }

    private func purchaseCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<IngredientPurchase>())
    }

    // MARK: - Sections

    @Test func sections_SplitByWhatTheImportWillDo() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        let model = makeModel([
            InventoryImportRow(name: "Olive Oil", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Olive Oil", quantity: -1),
            InventoryImportRow(name: "", quantity: 1)
        ], inventory: [olive])

        #expect(model.matchedEntries.count == 1)
        #expect(model.newEntries.count == 1)
        #expect(model.blockedLines.count == 2)
        #expect(model.blockedLines.map(\.entryName) == ["Olive Oil", nil])
    }

    @Test func sections_EntryWithOnlyBlockedRows_AppearsOnlyInBlocked() {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: -2)])

        #expect(model.newEntries.isEmpty)
        #expect(model.matchedEntries.isEmpty)
        #expect(model.blockedLines.count == 1)
    }

    @Test func sections_TurnedOffEntry_StaysInItsSection() {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)])
        model.setIncluded(false, entry: model.newEntries[0].id)

        #expect(model.newEntries.count == 1)
        #expect(model.blockedLines.count == 0)
    }

    // MARK: - Toggling

    @Test func setIncluded_Line_ChangesCountsAndWhatIsSaved() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 2)
        ])
        let lineID = try #require(model.newEntries.first?.lines.first?.id)

        model.setIncluded(false, line: lineID)
        #expect(model.importableCount == 1)
        #expect(model.skippedCount == 1)

        model.confirm(in: context)

        let created = try #require(try ingredients(in: context).first)
        #expect(created.purchases.count == 1)
        #expect(model.result?.importedRows == 1)
        #expect(model.result?.skippedRows == 1)
    }

    @Test func setIncluded_Entry_TurnsEveryRowOffAndOn() throws {
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 2)
        ])
        let entry = try #require(model.newEntries.first)
        #expect(model.isIncluded(entry))

        model.setIncluded(false, entry: entry.id)
        #expect(model.importableCount == 0)
        #expect(!model.isIncluded(model.newEntries[0]))

        model.setIncluded(true, entry: entry.id)
        #expect(model.importableCount == 2)
        #expect(model.isIncluded(model.newEntries[0]))
    }

    // MARK: - Rematching

    @Test func rematch_NewToExisting_MovesTheEntryAndAddsPurchasesWithoutCreatingAnIngredient() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 250)])
        let entryID = try #require(model.newEntries.first?.id)

        model.rematch(entry: entryID, to: butter)

        #expect(model.newEntries.isEmpty)
        #expect(model.matchedEntries.map(\.name) == ["Shea Butter"])

        model.confirm(in: context)

        #expect(try ingredients(in: context).count == 1)
        #expect(butter.purchases.count == 1)
        #expect(model.result?.ingredientsCreated == 0)
    }

    @Test func rematch_ToHiddenIngredient_FlagsTheEntryAndLeavesItHidden() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let hidden = Support.insertIngredient("Shea Butter", isHidden: true, in: context)
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 250)])
        let entryID = try #require(model.newEntries.first?.id)

        model.rematch(entry: entryID, to: hidden)

        #expect(model.matchedEntries.first?.isHidden == true)

        model.confirm(in: context)

        #expect(hidden.isHidden)
        #expect(hidden.purchases.count == 1)
    }

    @Test func rematch_ToIncompatibleUnit_MovesTheRowsToBlocked() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 250)])
        let entryID = try #require(model.newEntries.first?.id)

        model.rematch(entry: entryID, to: box)

        #expect(model.matchedEntries.isEmpty)
        #expect(model.blockedLines.count == 1)
        #expect(model.blockedLines.first?.entryName == "Soap Box")
        #expect(model.confirmBlocker != nil)
    }

    @Test func resetMatch_BackToNew_CreatesTheIngredient() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 250)])
        let entryID = try #require(model.newEntries.first?.id)
        model.rematch(entry: entryID, to: butter)
        let rematched = try #require(model.matchedEntries.first)
        #expect(model.canResetToNew(rematched))
        #expect(!model.canResetMatch(rematched))

        model.resetMatch(entry: entryID)
        #expect(model.newEntries.map(\.name) == ["Zzyzx Butter"])
        #expect(!model.canResetToNew(model.newEntries[0]))

        model.confirm(in: context)

        let all = try ingredients(in: context)
        #expect(all.count == 2)
        #expect(all.contains { $0.name == "Zzyzx Butter" })
        #expect(butter.purchases.isEmpty)
    }

    @Test func resetMatch_FromExisting_RestoresTheOriginalMatch() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        let butter = Support.insertIngredient("Shea Butter", in: context)
        let model = makeModel([InventoryImportRow(name: "Olive Oil", quantity: 5)], inventory: [olive, butter])
        let entryID = try #require(model.matchedEntries.first?.id)
        #expect(!model.canResetMatch(model.matchedEntries[0]))

        model.rematch(entry: entryID, to: butter)
        #expect(model.canResetMatch(model.matchedEntries[0]))
        #expect(!model.canResetToNew(model.matchedEntries[0]))

        model.resetMatch(entry: entryID)

        #expect(model.matchedEntries.map(\.name) == ["Olive Oil"])
        #expect(!model.canResetMatch(model.matchedEntries[0]))
    }

    // MARK: - Category

    @Test func setCategory_NewEntry_LandsOnTheCreatedIngredient() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)])
        let entryID = try #require(model.newEntries.first?.id)

        model.setCategory("Butters", entry: entryID)
        #expect(model.categoryName(of: model.newEntries[0]) == "Butters")

        model.confirm(in: context)

        let created = try #require(try ingredients(in: context).first)
        #expect(created.category?.name == "Butters")
    }

    @Test func categoryName_OthersOrNone_IsNil() throws {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", categoryName: "others", quantity: 1)])
        let entry = try #require(model.newEntries.first)

        #expect(model.categoryName(of: entry) == nil)
    }

    @Test func categoryOptions_ListExistingAndTheFilesOwnOnce() throws {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", categoryName: "Butters", quantity: 1)])
        let entry = try #require(model.newEntries.first)

        let withFile = model.categoryOptions(for: entry, existing: ["Oils", "Others"])
        #expect(withFile == ["Oils", "Butters"])

        let alreadyThere = model.categoryOptions(for: entry, existing: ["Oils", "butters"])
        #expect(alreadyThere == ["Oils", "butters"])
    }

    // MARK: - Confirming

    @Test func confirm_NothingImportable_HasABlockerAndWritesNothing() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", quantity: -1),
            InventoryImportRow(name: "", quantity: 1)
        ])

        #expect(model.confirmBlocker != nil)
        #expect(!model.canConfirm)

        model.confirm(in: context)

        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
        #expect(try ingredients(in: context).isEmpty)
        #expect(try purchaseCount(in: context) == 0)
    }

    @Test func confirm_EverythingTurnedOff_HasADifferentBlockerAndWritesNothing() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let nothingImportable = makeModel([InventoryImportRow(name: "", quantity: 1)])
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)])
        model.setIncluded(false, entry: model.newEntries[0].id)

        #expect(model.confirmBlocker != nil)
        #expect(model.confirmBlocker != nothingImportable.confirmBlocker)
        #expect(!model.canConfirm)

        model.confirm(in: context)

        #expect(model.result == nil)
        #expect(try ingredients(in: context).isEmpty)
    }

    @Test func confirm_Partial_ReportsImportedAndSkippedExactly() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 2),
            InventoryImportRow(name: "Zzyzx Butter", quantity: -1),
            InventoryImportRow(name: "", quantity: 1)
        ])
        model.setIncluded(false, line: model.newEntries[0].lines[1].id)

        model.confirm(in: context)

        let result = try #require(model.result)
        #expect(result.importedRows == 1)
        #expect(result.skippedRows == 3)
        #expect(result.purchasesAdded == 1)
        #expect(model.resultSummary != nil)
    }

    @Test func confirm_Twice_DoesNotImportAgain() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)])

        model.confirm(in: context)
        #expect(!model.canConfirm)
        model.confirm(in: context)

        #expect(try ingredients(in: context).count == 1)
        #expect(try purchaseCount(in: context) == 1)
    }

    @Test func confirm_MatchDeletedMeanwhile_IsAnErrorNotASuccess() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        try context.save()
        let model = makeModel([InventoryImportRow(name: "Shea Butter", quantity: 5)], inventory: [butter])
        context.delete(butter)
        try context.save()

        model.confirm(in: context)

        #expect(model.result == nil)
        #expect(model.errorMessage != nil)
        #expect(try purchaseCount(in: context) == 0)
    }

    @Test func resultSummary_BeforeConfirm_IsNil() {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)])

        #expect(model.resultSummary == nil)
    }
}
