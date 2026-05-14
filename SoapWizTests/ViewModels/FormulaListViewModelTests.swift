import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

@Suite("FormulaListViewModel")
@MainActor
struct FormulaListViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Formula.self, FormulaIngredient.self, ProductVariant.self,
            ProductionRun.self, ProductionIngredientDeduction.self,
            Ingredient.self, IngredientBatch.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    // MARK: - filtered

    @Test func filtered_EmptySearch_ReturnsAll() throws {
        let sut = FormulaListViewModel()
        let formulas = [Formula.mock(name: "Bar Soap"), Formula.mock(name: "Shampoo")]
        #expect(sut.filtered(formulas).count == 2)
    }

    @Test func filtered_MatchingSearch_ReturnsSubset() throws {
        let sut = FormulaListViewModel()
        sut.searchText = "soap"
        let formulas = [Formula.mock(name: "Bar Soap"), Formula.mock(name: "Shampoo")]
        let result = sut.filtered(formulas)
        #expect(result.count == 1)
        #expect(result.first?.name == "Bar Soap")
    }

    @Test func filtered_CaseInsensitiveSearch() throws {
        let sut = FormulaListViewModel()
        sut.searchText = "SOAP"
        let formulas = [Formula.mock(name: "Bar Soap")]
        #expect(sut.filtered(formulas).count == 1)
    }

    @Test func filtered_NoMatch_ReturnsEmpty() throws {
        let sut = FormulaListViewModel()
        sut.searchText = "zzz"
        let formulas = [Formula.mock(name: "Bar Soap"), Formula.mock(name: "Shampoo")]
        #expect(sut.filtered(formulas).isEmpty)
    }

    @Test func filtered_EmptyCollection_ReturnsEmpty() throws {
        let sut = FormulaListViewModel()
        sut.searchText = "soap"
        #expect(sut.filtered([]).isEmpty)
    }

    // MARK: - delete

    @Test func delete_FormulaWithNoChildren_DeletesImmediately() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.delete(formula, context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Formula>())
        #expect(remaining.isEmpty)
        #expect(sut.confirmingDelete.isEmpty)
    }

    @Test func delete_FormulaWithIngredients_SetsConfirmingDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        let fi = FormulaIngredient(percentage: 30)
        ctx.insert(fi)
        formula.ingredients.append(fi)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.delete(formula, context: ctx)

        #expect(sut.confirmingDelete.count == 1)
        #expect(sut.confirmingDelete.first === formula)
        let remaining = try ctx.fetch(FetchDescriptor<Formula>())
        #expect(remaining.count == 1)
    }

    @Test func delete_FormulaWithVariants_SetsConfirmingDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        let variant = ProductVariant(name: "100g", size: 100)
        ctx.insert(variant)
        formula.variants.append(variant)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.delete(formula, context: ctx)

        #expect(sut.confirmingDelete.count == 1)
    }

    @Test func delete_FormulaWithRuns_SetsConfirmingDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        let run = ProductionRun(quantity: 10, lossPercentage: 5)
        ctx.insert(run)
        formula.runs.append(run)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.delete(formula, context: ctx)

        #expect(sut.confirmingDelete.count == 1)
    }

    // MARK: - deleteSelected

    @Test func deleteSelected_NoChildren_DeletesAndResetsState() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.editMode = .active
        sut.selection = [formula.persistentModelID]
        sut.deleteSelected(in: [formula], context: ctx)

        #expect(sut.selection.isEmpty)
        #expect(sut.editMode == .inactive)
        #expect(sut.confirmingDelete.isEmpty)
    }

    @Test func deleteSelected_WithChildren_SetsConfirmingDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        let fi = FormulaIngredient(percentage: 50)
        ctx.insert(fi)
        formula.ingredients.append(fi)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.editMode = .active
        sut.selection = [formula.persistentModelID]
        sut.deleteSelected(in: [formula], context: ctx)

        #expect(sut.confirmingDelete.count == 1)
        #expect(sut.editMode == .active)
    }

    // MARK: - confirmDelete

    @Test func confirmDelete_DeletesAndResetsState() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let formula = Formula(name: "Bar Soap")
        ctx.insert(formula)
        try ctx.save()

        let sut = FormulaListViewModel()
        sut.editMode = .active
        sut.selection = [formula.persistentModelID]
        sut.confirmingDelete = [formula]
        sut.confirmDelete(context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Formula>())
        #expect(remaining.isEmpty)
        #expect(sut.confirmingDelete.isEmpty)
        #expect(sut.selection.isEmpty)
        #expect(sut.editMode == .inactive)
    }
}

// MARK: - Mocks

extension Formula {
    static func mock(name: String = "Bar Soap", lossPercentage: Double? = nil) -> Formula {
        Formula(name: name, lossPercentage: lossPercentage)
    }
}
