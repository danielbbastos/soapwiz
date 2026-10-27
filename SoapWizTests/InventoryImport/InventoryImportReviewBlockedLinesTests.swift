import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportReviewViewModel blocked lines", .serialized)
@MainActor
struct InventoryImportReviewBlockedLinesTests {

    private typealias Support = InventoryImportTestSupport

    private func makeModel(
        _ rows: [InventoryImportRow],
        inventory: [Ingredient] = []
    ) -> InventoryImportReviewViewModel {
        InventoryImportReviewViewModel(plan: Support.plan(rows, inventory: inventory))
    }

    @Test func rematch_ToIncompatibleUnit_CanBeUndoneFromBlocked() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 250),
            InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 100)
        ])
        let entryID = try #require(model.newEntries.first?.id)

        model.rematch(entry: entryID, to: box)

        #expect(model.newEntries.isEmpty)
        #expect(model.matchedEntries.isEmpty)
        #expect(model.blockedLines.count == 2)
        let rematchedFlags = model.blockedLines.map { $0.entry?.isRematched }
        #expect(rematchedFlags == [true, true])
        #expect(model.blockedLines.filter(\.offersMatchActions).count == 1)
        let blockedEntry = try #require(model.blockedLines.first?.entry)
        #expect(model.canResetToNew(blockedEntry))

        model.resetMatch(entry: entryID)

        #expect(model.blockedLines.isEmpty)
        let restored = try #require(model.newEntries.first)
        #expect(restored.lines.count == 2)
        #expect(restored.lines.map(\.isIncluded) == [true, true])
        #expect(model.importableCount == 2)
    }

    @Test func blockedLines_RematchedEntryWithAnImportableRow_OffersNoMatchActions() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", unit: .kilograms, in: context)
        let model = makeModel([
            InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 250),
            InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: -1)
        ])
        let entryID = try #require(model.newEntries.first?.id)

        model.rematch(entry: entryID, to: butter)

        #expect(model.matchedEntries.count == 1)
        #expect(model.blockedLines.count == 1)
        #expect(model.blockedLines.map(\.offersMatchActions) == [false])
    }

    @Test func blockedLines_MatchedEntryBlockedByUnitMismatch_OffersActionsOnceAndCanBeRematched() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        let butter = Support.insertIngredient("Shea Butter", in: context)
        let model = makeModel([
            InventoryImportRow(name: "Soap Box", unit: .grams, quantity: 5),
            InventoryImportRow(name: "Soap Box", unit: .grams, quantity: 6)
        ], inventory: [box, butter])

        #expect(model.matchedEntries.isEmpty)
        #expect(model.blockedLines.map(\.offersMatchActions) == [true, false])
        let entry = try #require(model.blockedLines.first?.entry)
        #expect(!model.canResetMatch(entry))

        model.rematch(entry: entry.id, to: butter)

        #expect(model.blockedLines.isEmpty)
        let moved = try #require(model.matchedEntries.first)
        #expect(moved.name == "Shea Butter")
        let includedFlags = moved.lines.map(\.isIncluded)
        #expect(includedFlags == [true, true])
    }

    @Test func blockedLines_EntryBlockedByItsOwnRowIssue_OffersNoMatchActions() {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: -1)])

        #expect(model.blockedLines.count == 1)
        #expect(model.blockedLines.map(\.offersMatchActions) == [false])
    }

    @Test func blockedLines_NeverRematchedEntry_OffersNoMatchActions() {
        let model = makeModel([InventoryImportRow(name: "Zzyzx Butter", quantity: -1), InventoryImportRow(name: "", quantity: 1)])

        #expect(model.blockedLines.count == 2)
        #expect(model.blockedLines.map(\.offersMatchActions) == [false, false])
    }
}
