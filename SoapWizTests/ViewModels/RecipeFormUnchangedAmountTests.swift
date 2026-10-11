import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// An amount field writes its value back every time editing ends, changed or
/// not. Those unchanged commits must not lock a row or move the others.
@Suite("Unchanged amount commits", .serialized)
@MainActor
struct RecipeFormUnchangedAmountTests: RecipeFormTestHelpers {

    private func makeThreeOilModel() -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))
        model.addOil(Ingredient(name: "Coconut Oil"))
        model.addOil(Ingredient(name: "Castor Oil"))
        return model
    }

    private func makeGeneralModelWithAdditive(_ ctx: ModelContext) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        let base = Ingredient(name: "Apricot Kernel Oil", unit: "g")
        ctx.insert(base)
        model.addOil(base)
        let additive = Ingredient(name: "Charcoal", unit: "g")
        ctx.insert(additive)
        model.addAdditive(additive)
        return model
    }

    // MARK: - Oils

    @Test func userEdited_CurrentAmount_LeavesRowUnlockedAndAmountsUntouched() {
        let model = makeThreeOilModel()
        let before = model.oilDrafts.map(\.amount)

        model.userEdited(id: model.oilDrafts[0].id, amount: model.oilDrafts[0].amount)

        #expect(model.oilDrafts.map(\.isLocked) == [false, false, false])
        #expect(model.oilDrafts.map(\.amount) == before)
    }

    @Test func userEdited_AfterUnchangedCommit_StillRedistributesAcrossBothOthers() {
        let model = makeThreeOilModel()
        model.userEdited(id: model.oilDrafts[0].id, amount: model.oilDrafts[0].amount)

        model.userEdited(id: model.oilDrafts[2].id, amount: 50)

        #expect(model.oilDrafts[2].isLocked)
        #expect(model.oilDrafts[0].amount == 25)
        #expect(model.oilDrafts[1].amount == 25)
        #expect(!model.oilDrafts[0].isLocked)
        #expect(!model.oilDrafts[1].isLocked)
    }

    @Test func userEdited_RemainderCommittedAsDisplayedValue_IsUnchanged() {
        let model = makeThreeOilModel()
        let last = model.oilDrafts[2]
        #expect(abs(last.amount - 33.4) < 1e-9)

        model.userEdited(id: last.id, amount: 33.4)

        #expect(!model.oilDrafts[2].isLocked)
        #expect(model.oilDrafts[2].amount == last.amount)
    }

    @Test func userEdited_StoredMoreDecimalsThanDisplayed_IsUnchangedAndKeepsStoredValue() {
        let model = makeThreeOilModel()
        model.oilDrafts[0].amount = 33.33

        model.userEdited(id: model.oilDrafts[0].id, amount: 33.3)

        #expect(!model.oilDrafts[0].isLocked)
        #expect(model.oilDrafts[0].amount == 33.33)
    }

    @Test func userEdited_ChangedAmount_LocksAndRedistributes() {
        let model = makeThreeOilModel()

        model.userEdited(id: model.oilDrafts[0].id, amount: 50)

        #expect(model.oilDrafts[0].isLocked)
        #expect(model.oilDrafts[0].amount == 50)
        #expect(model.oilDrafts[1].amount == 25)
        #expect(model.oilDrafts[2].amount == 25)
    }

    @Test func userEdited_UnknownId_DoesNothing() {
        let model = makeThreeOilModel()
        let before = model.oilDrafts.map(\.amount)

        model.userEdited(id: UUID(), amount: 50)

        #expect(model.oilDrafts.map(\.amount) == before)
    }

    // MARK: - Import path

    @Test func setOilAmount_AmountEqualToCurrentShare_StillLocks() {
        let model = makeThreeOilModel()

        model.setOilAmount(id: model.oilDrafts[0].id, amount: model.oilDrafts[0].amount)

        #expect(model.oilDrafts[0].isLocked)
    }

    @Test func setOilAmount_LockedRowSurvivesALaterImportedRow() {
        let model = makeThreeOilModel()
        model.setOilAmount(id: model.oilDrafts[0].id, amount: 33.3)

        model.setOilAmount(id: model.oilDrafts[1].id, amount: 50)

        #expect(model.oilDrafts[0].amount == 33.3)
        #expect(model.oilDrafts[1].amount == 50)
    }

    // MARK: - Fragrances

    private func makeFragranceBlendModel() -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))
        model.setFragranceUnit(.percentOfFragrances)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Cedarwood EO"))
        return model
    }

    @Test func userEditedFragrance_CurrentAmount_DoesNotLockOrMoveOthers() {
        let model = makeFragranceBlendModel()
        let before = model.fragranceDrafts.map(\.amount)

        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: model.fragranceDrafts[0].amount)

        #expect(model.fragranceDrafts.map(\.isLocked) == [false, false])
        #expect(model.fragranceDrafts.map(\.amount) == before)
    }

    @Test func userEditedFragrance_ChangedAmount_LocksAndRedistributes() {
        let model = makeFragranceBlendModel()

        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 60)

        #expect(model.fragranceDrafts[0].isLocked)
        #expect(model.fragranceDrafts.map(\.amount) == [60, 40])
    }

    @Test func setFragranceAmount_AmountEqualToCurrentShare_StillLocks() {
        let model = makeFragranceBlendModel()

        model.setFragranceAmount(id: model.fragranceDrafts[0].id, amount: model.fragranceDrafts[0].amount)

        #expect(model.fragranceDrafts[0].isLocked)
    }

    // MARK: - Additives

    @Test func updateAdditive_UnchangedAmountAndUnit_DoesNotRebalanceBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModelWithAdditive(ctx)
        model.oilDrafts[0].amount = 80
        let additive = model.additiveDrafts[0]

        model.updateAdditive(id: additive.id, amount: additive.amount, unit: additive.unit)

        #expect(model.oilDrafts[0].amount == 80)
    }

    @Test func updateAdditive_AmountWithinDisplayedPrecision_DoesNotRebalanceBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModelWithAdditive(ctx)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5)
        model.oilDrafts[0].amount = 80

        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5.0000001)

        #expect(model.oilDrafts[0].amount == 80)
    }

    @Test func updateAdditive_ChangedAmount_StillRebalancesBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModelWithAdditive(ctx)
        model.oilDrafts[0].amount = 80

        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5)

        #expect(model.additiveDrafts[0].amount == 5)
        #expect(model.oilDrafts[0].amount == 95)
    }

    // MARK: - Helper

    @Test func matches_RoundsBothSidesToTheDisplayedPrecision() {
        #expect(33.400000000000006.matches(33.4, fractionDigits: 1))
        #expect(33.33.matches(33.3, fractionDigits: 1))
        #expect(!33.3.matches(33.4, fractionDigits: 1))
        #expect(!1.0004.matches(1.0006, fractionDigits: 3))
    }
}
