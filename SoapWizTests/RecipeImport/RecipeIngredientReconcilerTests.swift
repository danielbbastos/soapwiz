import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeIngredientReconciler", .serialized)
@MainActor
struct RecipeIngredientReconcilerTests: RecipeImportTestHelpers {

    @Test func reconcile_ExactName_Matches() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        let row = try #require(rows.first)
        #expect(row.ingredient?.name == "Olive Oil")
        #expect(row.isResolved)
    }

    @Test(arguments: ["OLIVE OIL", "olive oil", "  Olive Oil  ", "Olive  Oil"])
    func reconcile_NameVariations_AllMatchTheSameIngredient(_ written: String) throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: written, amount: 70, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.first?.ingredient?.name == "Olive Oil")
    }

    @Test func reconcile_DiacriticVariation_Matches() throws {
        let (container, context) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        context.insert(oils)
        let ingredient = makeOil(name: "Óleo de Oliva", sap: 0.1345, category: oils, context: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "OLEO DE OLIVA", amount: 100, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [ingredient])

        #expect(rows.first?.ingredient === ingredient)
    }

    /// The safety-critical case. "Olive Pomace Oil" is a different oil with a
    /// different SAP value; matching it to "Olive Oil" would put a wrong number
    /// into the lye calculation with nothing to reveal it.
    @Test func reconcile_NearMiss_StaysUnmatched() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Pomace Oil", amount: 70, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.first?.resolution == .unmatched)
        #expect(rows.first?.ingredient == nil)
    }

    @Test func reconcile_EmptyInventory_LeavesEverythingUnmatched() {
        let draft = RecipeImportDraft.mock()
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.resolution == .unmatched })
    }

    @Test func reconcile_EmptyDraft_ProducesNoRows() {
        let draft = RecipeImportDraft.mock(oils: [])
        #expect(RecipeIngredientReconciler.reconcile(draft, against: []).isEmpty)
    }

    @Test func reconcile_AssignsARolePerSection() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)],
            additives: [ImportedIngredient(name: "Kaolin Clay", amount: 10, unit: "g")],
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "%")]
        )
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.filter { $0.role == .oil }.count == 1)
        #expect(rows.filter { $0.role == .additive }.count == 1)
        #expect(rows.filter { $0.role == .fragrance }.count == 1)
    }

    @Test func suggestedCategoryName_FollowsTheRow() {
        let imported = ImportedIngredient(name: "Kaolin Clay", amount: 10, unit: "g")
        #expect(RecipeImportRow(imported: imported, role: .oil, resolution: .unmatched)
            .suggestedCategoryName == IngredientCategory.Name.oils)
        #expect(RecipeImportRow(imported: imported, role: .additive, resolution: .unmatched)
            .suggestedCategoryName == IngredientCategory.Name.additives)
        #expect(RecipeImportRow(imported: imported, role: .fragrance, resolution: .unmatched)
            .suggestedCategoryName == IngredientCategory.Name.fragrances)
    }

    // MARK: - Re-resolution

    @Test func resolveUnmatched_AfterTheIngredientExists_Matches() throws {
        let (container, context) = try makeContext()
        _ = container

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Babassu Oil", amount: 100, unit: nil)])
        var rows = RecipeIngredientReconciler.reconcile(draft, against: [])
        #expect(rows[0].resolution == .unmatched)

        let created = makeOil(name: "Babassu Oil", sap: 0.175, category: nil, context: context)
        rows = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: [created])

        #expect(rows[0].ingredient === created)
    }

    @Test func resolveUnmatched_SkippedRow_KeepsItsDecision() throws {
        let (container, context) = try makeContext()
        _ = container

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Babassu Oil", amount: 100, unit: nil)])
        var rows = RecipeIngredientReconciler.reconcile(draft, against: [])
        rows[0].resolution = .skipped

        let created = makeOil(name: "Babassu Oil", sap: 0.175, category: nil, context: context)
        rows = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: [created])

        #expect(rows[0].resolution == .skipped)
    }

    @Test func resolveUnmatched_MatchedRow_IsNotReassigned() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)
        let originalMatch = try #require(rows.first?.ingredient)

        let refreshed = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: inventory)
        #expect(refreshed.first?.ingredient === originalMatch)
    }

    /// CloudKit can leave two ingredients with the same name in flight. The one
    /// with a saponification value is the one a recipe can be calculated from,
    /// and it must win whichever order `@Query` returns them in.
    @Test func reconcile_DuplicateNames_PrefersTheOneWithASapValue() throws {
        let (container, context) = try makeContext()
        _ = container
        let withSap = makeOil(name: "Olive Oil", sap: 0.1345, category: nil, context: context)
        let withoutSap = Ingredient(name: "Olive Oil", unit: "g")
        context.insert(withoutSap)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)])
        let forward = RecipeIngredientReconciler.reconcile(draft, against: [withSap, withoutSap])
        let reversed = RecipeIngredientReconciler.reconcile(draft, against: [withoutSap, withSap])

        #expect(forward.first?.ingredient === withSap)
        #expect(reversed.first?.ingredient === withSap)
    }

    @Test func reconcile_UnnamedInventoryEntry_IsIgnored() throws {
        let (container, context) = try makeContext()
        _ = container
        let blank = Ingredient(name: "", unit: "g")
        context.insert(blank)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "", amount: 100, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [blank])

        #expect(rows.first?.resolution == .unmatched)
    }
}
