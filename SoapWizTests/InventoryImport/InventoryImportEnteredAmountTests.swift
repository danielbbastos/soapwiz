import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportEnteredAmount", .serialized)
@MainActor
struct InventoryImportEnteredAmountTests {

    private typealias Support = InventoryImportTestSupport

    private func mismatchRow(totalPrice: Double? = 9) -> InventoryImportRow {
        InventoryImportRow(name: "Castor Oil", unit: .milliliters, quantity: 500, totalPrice: totalPrice)
    }

    private func mismatchPlan(
        _ rows: [InventoryImportRow]? = nil,
        inventory: [Ingredient]
    ) -> InventoryImportPlan {
        Support.plan(rows ?? [mismatchRow()], inventory: inventory)
    }

    private func firstLine(of plan: InventoryImportPlan) throws -> InventoryImportLine {
        try #require(plan.entries.first?.lines.first)
    }

    // MARK: - Eligibility

    @Test func canEnterQuantity_UnitMismatch_IsEligible() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let plan = mismatchPlan(inventory: [castor])

        let line = try firstLine(of: plan)

        #expect(line.canEnterQuantity)
        #expect(!line.isImportable)
    }

    @Test func canEnterQuantity_CountAgainstWeight_IsEligible() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", unit: .units, in: context)
        let plan = mismatchPlan([InventoryImportRow(name: "Castor Oil", unit: .grams, quantity: 5)], inventory: [castor])

        #expect(try firstLine(of: plan).canEnterQuantity)
    }

    @Test func canEnterQuantity_OtherBlockingIssues_IsNotEligible() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let rows = [
            InventoryImportRow(name: "", unit: .milliliters, quantity: 500),
            InventoryImportRow(name: "Castor Oil", unit: .milliliters, quantity: -1),
            InventoryImportRow(
                name: "Castor Oil", unit: .milliliters, quantity: 500,
                issues: [.conflictingUnits(quantityUnit: "ml", unitColumn: "g")]
            ),
            InventoryImportRow(name: "Castor Oil", unit: .milliliters, quantity: 500, issues: [.unknownUnit("bottle")]),
            InventoryImportRow(name: "Castor Oil")
        ]

        let plan = mismatchPlan(rows, inventory: [castor])
        let lines = plan.unnamed + plan.entries.flatMap(\.lines)

        #expect(lines.count == rows.count)
        #expect(lines.allSatisfy { !$0.canEnterQuantity })
    }

    @Test func canEnterQuantity_ImportableRow_IsNotEligible() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let plan = mismatchPlan([InventoryImportRow(name: "Castor Oil", unit: .grams, quantity: 500)], inventory: [castor])

        #expect(try !firstLine(of: plan).canEnterQuantity)
    }

    // MARK: - Entering

    @Test func enterQuantity_PositiveAmount_MakesTheRowImportable() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let id = try firstLine(of: plan).id

        plan.enterQuantity(460, forLine: id)

        let line = try firstLine(of: plan)
        #expect(line.isImportable)
        #expect(line.quantity == 460)
        #expect(line.enteredQuantity == 460)
        #expect(line.issues == [.enteredByHand(fileQuantity: 500, fileUnit: "ml")])
        #expect(line.canEnterQuantity)
        #expect(plan.importableCount == 1)
        #expect(plan.skippedCount == 0)
    }

    @Test(arguments: [0.0, -5, Double.nan, Double.infinity])
    func enterQuantity_InvalidAmount_DoesNothing(amount: Double) throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let id = try firstLine(of: plan).id

        plan.enterQuantity(amount, forLine: id)

        let line = try firstLine(of: plan)
        #expect(!line.isImportable)
        #expect(line.enteredQuantity == nil)
        #expect(plan.importableCount == 0)
    }

    @Test func enterQuantity_IneligibleRow_DoesNothing() throws {
        var plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: -1)], inventory: [])
        let id = try firstLine(of: plan).id

        plan.enterQuantity(5, forLine: id)

        let line = try firstLine(of: plan)
        #expect(line.enteredQuantity == nil)
        #expect(line.quantity == nil)
    }

    @Test func enterQuantity_Twice_ReplacesTheAmount() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let id = try firstLine(of: plan).id

        plan.enterQuantity(460, forLine: id)
        plan.enterQuantity(470, forLine: id)

        let line = try firstLine(of: plan)
        #expect(line.quantity == 470)
        #expect(line.issues == [.enteredByHand(fileQuantity: 500, fileUnit: "ml")])
    }

    @Test func enteredByHandReason_FormatsTheQuantityWithTheLocale() {
        let issue = InventoryImportIssue.enteredByHand(fileQuantity: 500, fileUnit: "ml")
        let expected = (500.0).formatted(.number.precision(.fractionLength(0...3)))

        #expect(issue.reason.contains(expected))
        #expect(issue.reason.contains("ml"))
        #expect(issue.severity == .warning)
    }

    // MARK: - Undo

    @Test func clearEnteredQuantity_ReturnsTheRowToBlocked() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let id = try firstLine(of: plan).id
        plan.enterQuantity(460, forLine: id)

        plan.clearEnteredQuantity(forLine: id)

        let line = try firstLine(of: plan)
        #expect(!line.isImportable)
        #expect(line.enteredQuantity == nil)
        #expect(line.quantity == nil)
        #expect(line.issues == [.unitMismatch(rowUnit: "ml", ingredientUnit: "g")])
        #expect(line.canEnterQuantity)
        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 1)
    }

    @Test func clearEnteredQuantity_WithoutAnEnteredAmount_ChangesNothing() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan([InventoryImportRow(name: "Castor Oil", unit: .grams, quantity: 500)], inventory: [castor])
        let id = try firstLine(of: plan).id

        plan.clearEnteredQuantity(forLine: id)

        #expect(try firstLine(of: plan).quantity == 500)
        #expect(plan.importableCount == 1)
    }

    @Test func turnedOffRow_StaysOffThroughEnterAndUndo() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan([mismatchRow(), InventoryImportRow(name: "Castor Oil", unit: .grams, quantity: 1)], inventory: [castor])
        let id = try #require(plan.entries.first?.lines.first?.id)
        let otherID = try #require(plan.entries.first?.lines.last?.id)
        plan.setIncluded(false, forLine: otherID)

        plan.enterQuantity(460, forLine: id)
        plan.setIncluded(false, forLine: id)
        #expect(plan.importableCount == 0)
        plan.clearEnteredQuantity(forLine: id)
        plan.enterQuantity(460, forLine: id)

        let lines = plan.entries[0].lines
        #expect(lines.allSatisfy { !$0.isIncluded })
        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 2)
    }

    // MARK: - Rematching

    @Test func rematch_DropsTheEnteredAmount() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let other = Support.insertIngredient("Other Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let entryID = try #require(plan.entries.first?.id)
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)

        plan.rematch(entry: entryID, to: other)

        let line = try firstLine(of: plan)
        #expect(line.enteredQuantity == nil)
        #expect(line.issues == [.unitMismatch(rowUnit: "ml", ingredientUnit: "g")])
    }

    @Test func resetMatch_DropsTheEnteredAmount() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        var plan = mismatchPlan(inventory: [castor])
        let entryID = try #require(plan.entries.first?.id)
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)

        plan.resetMatch(entry: entryID)

        let line = try firstLine(of: plan)
        #expect(line.enteredQuantity == nil)
        #expect(!line.isImportable)
    }

    // MARK: - View model

    @Test func viewModel_EnterAmount_MovesTheEntryToMatchedAndBack() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let model = InventoryImportReviewViewModel(plan: mismatchPlan(inventory: [castor]))
        let blocked = try #require(model.blockedLines.first)
        #expect(blocked.line.canEnterQuantity)
        #expect(model.matchedEntries.isEmpty)

        model.enterAmount("460", line: blocked.line.id)

        #expect(model.blockedLines.isEmpty)
        #expect(model.matchedEntries.count == 1)
        #expect(model.importableCount == 1)
        #expect(model.canConfirm)

        model.clearEnteredAmount(line: blocked.line.id)

        #expect(model.blockedLines.count == 1)
        #expect(model.matchedEntries.isEmpty)
        #expect(model.importableCount == 0)
        #expect(model.skippedCount == 1)
    }

    @Test(arguments: ["", "   ", "abc", "0", "-5", "1,2,3x"])
    func viewModel_EnterAmount_UnusableText_DoesNothing(text: String) throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let model = InventoryImportReviewViewModel(plan: mismatchPlan(inventory: [castor]))
        let id = try #require(model.blockedLines.first?.line.id)

        model.enterAmount(text, line: id)

        #expect(model.parsedAmount(text) == nil)
        #expect(model.blockedLines.count == 1)
        #expect(model.importableCount == 0)
    }

    @Test func viewModel_ParsedAmount_ReadsTheLocalesNumber() {
        let model = InventoryImportReviewViewModel(plan: InventoryImportPlan(entries: [], unnamed: []))

        #expect(model.parsedAmount("460") == 460)
        #expect(model.parsedAmount("0.5") == 0.5)
    }

    @Test func viewModel_FileQuantityNote_NamesTheFilesQuantityAndUnit() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", in: context)
        let model = InventoryImportReviewViewModel(plan: mismatchPlan(inventory: [castor]))
        let line = try #require(model.blockedLines.first?.line)

        let note = try #require(model.fileQuantityNote(line))

        #expect(note.contains((500.0).formatted(.number.precision(.fractionLength(0...3)))))
        #expect(note.contains("ml"))
    }

    @Test func viewModel_CanEnterAmount_UnnamedRow_IsFalse() throws {
        let model = InventoryImportReviewViewModel(plan: Support.plan([InventoryImportRow(name: "", quantity: 1)], inventory: []))

        #expect(try !#require(model.blockedLines.first?.line).canEnterQuantity)
    }

    // MARK: - Applier

    @Test func apply_EnteredAmount_SavesTheTypedQuantityAndFilePrice() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let castor = Support.insertIngredient("Castor Oil", unit: .grams, in: context)
        try context.save()
        var plan = mismatchPlan(inventory: [castor])
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)

        let result = try InventoryImportApplier.apply(plan, in: context)

        let purchase = try #require(castor.purchases.first)
        #expect(purchase.quantity == 460)
        #expect(purchase.totalPrice == 9)
        #expect(castor.unit == "g")
        #expect(castor.density == nil)
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 0, ingredientsCreated: 0, purchasesAdded: 1))
    }

    @Test func apply_EnteredAmountOnMergedSurvivor_ConvertsFromTheMatchedUnit() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Castor Oil", unit: .grams, slug: "castor-oil", in: context)
        let survivor = Support.insertIngredient("Castor Oil", unit: .kilograms, slug: "castor-oil", in: context)
        try context.save()
        var plan = mismatchPlan(inventory: [loser])
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)
        context.delete(loser)
        try context.save()

        let result = try InventoryImportApplier.apply(plan, in: context)

        let purchase = try #require(survivor.purchases.first)
        #expect(purchase.quantity == 0.46)
        #expect(purchase.totalPrice == 9)
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 0, ingredientsCreated: 0, purchasesAdded: 1))
    }

    @Test func apply_EnteredAmountOnMergedSurvivorWithSameUnit_KeepsTheAmount() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Castor Oil", unit: .grams, slug: "castor-oil", in: context)
        let survivor = Support.insertIngredient("Castor Oil", unit: .grams, slug: "castor-oil", in: context)
        try context.save()
        var plan = mismatchPlan(inventory: [loser])
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)
        context.delete(loser)
        try context.save()

        _ = try InventoryImportApplier.apply(plan, in: context)

        #expect(try #require(survivor.purchases.first).quantity == 460)
    }

    @Test func apply_EnteredAmountOnMergedSurvivorOfAnotherKind_SkipsTheRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Castor Oil", unit: .grams, slug: "castor-oil", in: context)
        let survivor = Support.insertIngredient("Castor Oil", unit: .milliliters, slug: "castor-oil", in: context)
        try context.save()
        var plan = mismatchPlan(inventory: [loser])
        plan.enterQuantity(460, forLine: try firstLine(of: plan).id)
        context.delete(loser)
        try context.save()

        let result = try InventoryImportApplier.apply(plan, in: context)

        #expect(survivor.purchases.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<IngredientPurchase>()) == 0)
        #expect(result == InventoryImportResult(importedRows: 0, skippedRows: 1, ingredientsCreated: 0, purchasesAdded: 0))
    }
}
