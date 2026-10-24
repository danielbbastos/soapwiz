import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportPlan", .serialized)
@MainActor
struct InventoryImportPlanTests {

    private typealias Support = InventoryImportTestSupport

    @Test func counts_AreInRowsNotEntries() throws {
        let rows = [
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 2),
            InventoryImportRow(name: "Zzyzx Butter", quantity: -3),
            InventoryImportRow(name: "", quantity: 1)
        ]

        let plan = Support.plan(rows, inventory: [])

        #expect(plan.rowCount == 4)
        #expect(plan.importableCount == 2)
        #expect(plan.skippedCount == 2)
    }

    @Test func setIncluded_Line_TurnsItOffAndOn() throws {
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)], inventory: [])
        let id = try #require(plan.entries.first?.lines.first?.id)

        plan.setIncluded(false, forLine: id)
        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 1)

        plan.setIncluded(true, forLine: id)
        #expect(plan.importableCount == 1)
    }

    @Test func setIncluded_BlockedLine_StaysOff() throws {
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: -1)], inventory: [])
        let id = try #require(plan.entries.first?.lines.first?.id)

        plan.setIncluded(true, forLine: id)

        #expect(plan.entries[0].lines[0].isIncluded == false)
        #expect(plan.importableCount == 0)
    }

    @Test func setIncluded_Entry_LeavesBlockedRowsOff() throws {
        var plan = Support.plan(
            [InventoryImportRow(name: "Zzyzx Butter", quantity: 1), InventoryImportRow(name: "Zzyzx Butter", quantity: -1)],
            inventory: []
        )
        let id = try #require(plan.entries.first?.id)

        plan.setIncluded(false, forEntry: id)
        #expect(plan.importableCount == 0)

        plan.setIncluded(true, forEntry: id)
        #expect(plan.entries[0].lines.map(\.isIncluded) == [true, false])
        #expect(plan.importableCount == 1)
    }

    @Test func setCategory_NewIngredient_ChangesAndClears() throws {
        var plan = Support.plan([InventoryImportRow(name: "Sweet Almond Oil", quantity: 1)], inventory: [])
        let id = try #require(plan.entries.first?.id)

        plan.setCategory("Carriers", forEntry: id)
        guard case .newIngredient(let changed) = plan.entries[0].resolution else {
            Issue.record("Expected a new ingredient")
            return
        }
        #expect(changed.categoryName == "Carriers")

        plan.setCategory("  ", forEntry: id)
        guard case .newIngredient(let cleared) = plan.entries[0].resolution else {
            Issue.record("Expected a new ingredient")
            return
        }
        #expect(cleared.categoryName == nil)
    }

    @Test func setCategory_MatchedIngredient_DoesNothing() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Olive Oil", quantity: 1)], inventory: [olive])
        let id = try #require(plan.entries.first?.id)

        plan.setCategory("Carriers", forEntry: id)

        #expect(!plan.entries[0].isNew)
        #expect(olive.category == nil)
    }

    @Test func rematch_NewIngredientToExisting_ConvertsIntoItsUnit() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", unit: .kilograms, in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 500)], inventory: [])
        let id = try #require(plan.entries.first?.id)
        #expect(plan.entries[0].isNew)

        plan.rematch(entry: id, to: butter)

        let entry = plan.entries[0]
        #expect(!entry.isNew)
        #expect(entry.name == "Shea Butter")
        #expect(entry.unit == "kg")
        #expect(entry.lines[0].quantity == 0.5)
    }

    @Test func rematch_ToIncompatibleUnit_BlocksTheRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 500)], inventory: [])
        let id = try #require(plan.entries.first?.id)

        plan.rematch(entry: id, to: box)

        #expect(plan.entries[0].lines[0].issues == [.unitMismatch(rowUnit: "g", ingredientUnit: "un")])
        #expect(plan.importableCount == 0)
    }

    @Test func rematch_FromBlockedToCompatible_IncludesTheRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Soap Box", unit: .grams, quantity: 500)], inventory: [box])
        let id = try #require(plan.entries.first?.id)
        #expect(plan.importableCount == 0)

        plan.rematch(entry: id, to: butter)

        #expect(plan.importableCount == 1)
    }

    @Test func rematch_KeepsARowTheUserTurnedOff() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], inventory: [])
        let entryID = try #require(plan.entries.first?.id)
        let lineID = try #require(plan.entries.first?.lines.first?.id)
        plan.setIncluded(false, forLine: lineID)

        plan.rematch(entry: entryID, to: butter)

        #expect(plan.importableCount == 0)
    }

    @Test func rematch_ToHiddenIngredient_IsAllowedAndFlagged() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let hidden = Support.insertIngredient("Shea Butter", isHidden: true, in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], inventory: [])
        let id = try #require(plan.entries.first?.id)

        plan.rematch(entry: id, to: hidden)

        #expect(plan.entries[0].isHidden)
    }

    @Test func rematch_NoQuantity_BecomesBlockedAndSkipped() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter")], inventory: [])
        let id = try #require(plan.entries.first?.id)
        #expect(plan.entries[0].lines[0].issues.isEmpty)
        #expect(plan.importableCount == 1)

        plan.rematch(entry: id, to: butter)

        #expect(plan.entries[0].lines[0].issues == [.nothingToAdd])
        #expect(!plan.entries[0].lines[0].isIncluded)
        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 1)
    }

    // MARK: - resetMatch

    @Test func isRematched_ChangesOnlyWithTheIngredient() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Olive Oil", quantity: 1)], inventory: [olive, butter])
        let id = try #require(plan.entries.first?.id)
        #expect(!plan.entries[0].isRematched)

        plan.rematch(entry: id, to: olive)
        #expect(!plan.entries[0].isRematched)

        plan.rematch(entry: id, to: butter)
        #expect(plan.entries[0].isRematched)
        #expect(!plan.entries[0].startedAsNew)
    }

    @Test func setCategory_DoesNotCountAsRematch() throws {
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)], inventory: [])
        let id = try #require(plan.entries.first?.id)

        plan.setCategory("Butters", forEntry: id)

        #expect(!plan.entries[0].isRematched)
        #expect(plan.entries[0].startedAsNew)
    }

    @Test func resetMatch_NewIngredient_RestoresResolutionAndPlacements() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", unit: .kilograms, quantity: 2)], inventory: [])
        let id = try #require(plan.entries.first?.id)
        plan.rematch(entry: id, to: box)
        #expect(plan.importableCount == 0)

        plan.resetMatch(entry: id)

        let entry = plan.entries[0]
        #expect(entry.isNew)
        #expect(!entry.isRematched)
        #expect(entry.name == "Zzyzx Butter")
        #expect(entry.unit == "kg")
        #expect(entry.lines[0].quantity == 2)
        #expect(entry.lines[0].issues.isEmpty)
        #expect(plan.importableCount == 1)
    }

    @Test func resetMatch_RestoresTheOriginalCategory() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", categoryName: "Butters", quantity: 1)], inventory: [])
        let id = try #require(plan.entries.first?.id)
        plan.setCategory("Carriers", forEntry: id)
        plan.rematch(entry: id, to: butter)

        plan.resetMatch(entry: id)

        guard case .newIngredient(let new) = plan.entries[0].resolution else {
            Issue.record("Expected a new ingredient")
            return
        }
        #expect(new.categoryName == "Butters")
    }

    @Test func resetMatch_ExistingMatch_ReturnsToIt() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", unit: .kilograms, in: context)
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Olive Oil", unit: .grams, quantity: 500)], inventory: [olive, butter])
        let id = try #require(plan.entries.first?.id)
        plan.rematch(entry: id, to: butter)
        #expect(plan.entries[0].lines[0].quantity == 500)

        plan.resetMatch(entry: id)

        let entry = plan.entries[0]
        #expect(entry.name == "Olive Oil")
        #expect(entry.unit == "kg")
        #expect(entry.lines[0].quantity == 0.5)
        #expect(!entry.isRematched)
    }

    @Test func resetMatch_KeepsARowTheUserTurnedOff() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let butter = Support.insertIngredient("Shea Butter", in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], inventory: [])
        let entryID = try #require(plan.entries.first?.id)
        let lineID = try #require(plan.entries.first?.lines.first?.id)
        plan.rematch(entry: entryID, to: butter)
        plan.setIncluded(false, forLine: lineID)

        plan.resetMatch(entry: entryID)

        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 1)
    }

    @Test func resetMatch_RowTurnedOffThenBlocked_StaysOffAfterUnblocking() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 5)], inventory: [])
        let entryID = try #require(plan.entries.first?.id)
        let lineID = try #require(plan.entries.first?.lines.first?.id)
        plan.setIncluded(false, forLine: lineID)
        plan.rematch(entry: entryID, to: box)
        #expect(!plan.entries[0].lines[0].isImportable)

        plan.resetMatch(entry: entryID)

        #expect(plan.entries[0].lines[0].isImportable)
        #expect(!plan.entries[0].lines[0].isIncluded)
        #expect(plan.importableCount == 0)
    }

    @Test func resetMatch_UnrematchedEntry_ChangesNothing() throws {
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], inventory: [])
        let id = try #require(plan.entries.first?.id)

        plan.resetMatch(entry: id)

        #expect(plan.entries[0].isNew)
        #expect(plan.importableCount == 1)
    }
}
