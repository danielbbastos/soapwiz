import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// How the reconciler reads a name as written: shortened spellings it undoes,
/// and the section a row lands in.
@Suite("RecipeIngredientReconciler names and sections", .serialized)
@MainActor
struct RecipeIngredientReconcilerNameTests: RecipeImportTestHelpers {

    // MARK: - Shortened names

    @Test(arguments: [
        ("Palm Oil (RSPO)", "Palm Oil"),
        ("olive oil (pomace is fine)", "Olive Oil"),
        ("Tea Tree EO", "Tea Tree Essential Oil"),
        ("Sweet Orange FO", "Sweet Orange Fragrance Oil"),
        ("castor", "Castor Oil")
    ])
    func reconcile_ShortenedName_MatchesTheFullName(_ written: String, _ expected: String) throws {
        let (container, context) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        context.insert(oils)
        let ingredient = makeOil(name: expected, sap: 0.14, category: oils, context: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: written, amount: 10, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [ingredient])

        #expect(rows.first?.ingredient === ingredient)
        #expect(rows.first?.imported.name == written)
    }

    @Test func reconcile_ShortenedNameViaCatalogAlias_MatchesTheInstalledRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        context.insert(fragrances)
        let teaTree = Ingredient(name: "Melaleuca", category: fragrances, unit: "g")
        teaTree.librarySlug = "tea-tree-essential-oil"
        context.insert(teaTree)

        let draft = RecipeImportDraft.mock(
            oils: [],
            fragrances: [ImportedIngredient(name: "Tea Tree EO", amount: 15, unit: "g")]
        )
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [teaTree])

        #expect(rows.first?.ingredient === teaTree)
    }

    /// A fragrance written as "Coconut" must not become Coconut Oil: matching
    /// would move it into the oils and the lye calculation.
    @Test(arguments: [RecipeIngredientRole.fragrance, .additive])
    func reconcile_ShortNameOutsideTheOils_IsNotExtendedWithOil(_ reportedRole: RecipeIngredientRole) throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)
        let coconut = [ImportedIngredient(name: "Coconut", amount: 3, unit: "%")]
        let draft = RecipeImportDraft.mock(
            oils: [],
            additives: reportedRole == .additive ? coconut : [],
            fragrances: reportedRole == .fragrance ? coconut : []
        )

        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        let row = try #require(rows.first)
        #expect(row.resolution == .unmatched)
        #expect(row.role == reportedRole)
    }

    @Test func resolveUnmatched_ShortName_IsNotExtendedWithOil() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Castor", amount: 5, unit: "%")])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [])

        let refreshed = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: inventory)

        #expect(refreshed.first?.resolution == .unmatched)
    }

    /// Appending " Oil" only undoes a shortening; a name that already ends in
    /// "oil" stays exactly as written, so the near miss still doesn't match.
    @Test func reconcile_BareOil_StaysUnmatched() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Oil", amount: 100, unit: "g")])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.first?.resolution == .unmatched)
    }

    @Test(arguments: [
        ("Kaolin Clay", RecipeIngredientRole?.some(.additive)),
        ("Dead Sea Salt", .additive),
        ("Goat Milk", .additive),
        ("Sodium Lactate", .additive),
        ("Lavender Essential Oil", .fragrance),
        ("Tea Tree EO", .fragrance),
        ("Oatmeal Milk & Honey Fragrance Oil", .fragrance),
        ("Milk Thistle Oil", nil),
        ("Honey Butter", nil),
        ("Lavender", nil),
        ("Sugar solution", .additive)
    ])
    func evidentRole_Name_IsReadFromItsWording(_ name: String, _ expected: RecipeIngredientRole?) {
        #expect(ImportedIngredientName.evidentRole(of: name) == expected)
    }

    /// "Fragrance" plus " Oil" would reach a real "Fragrance Oil" row and show
    /// a header as a confident match.
    @Test(arguments: ["Fragrance", "Additives", "Lye"])
    func reconcile_SectionWord_IsNotExtendedWithOil(_ written: String) throws {
        let (container, context) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        context.insert(oils)
        let inventory = ["Fragrance Oil", "Additives Oil", "Lye Oil"].map {
            makeOil(name: $0, sap: 0.14, category: oils, context: context)
        }

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: written, amount: 10, unit: "g")])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.first?.resolution == .unmatched)
    }

    // MARK: - Sections from categories

    @Test func reconcile_MatchedIngredient_TakesItsCategorysSection() throws {
        let (container, context) = try makeContext()
        _ = container
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        context.insert(additives)
        let honey = Ingredient(name: "Honey", category: additives, unit: "g")
        context.insert(honey)

        let draft = RecipeImportDraft.mock(
            oils: [],
            fragrances: [ImportedIngredient(name: "honey", amount: 1, unit: "tsp")]
        )
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [honey])

        let row = try #require(rows.first)
        #expect(row.role == .additive)
        #expect(row.ingredient === honey)
    }

    /// The model placed "Clay" under Additives on one run and Oils on the next.
    @Test(arguments: [RecipeIngredientRole.oil, .fragrance, .additive])
    func reconcile_UnmatchedClay_IsAlwaysAnAdditive(_ reportedRole: RecipeIngredientRole) throws {
        let clay = [ImportedIngredient(name: "Clay", amount: 0, unit: nil)]
        let draft = RecipeImportDraft.mock(
            oils: reportedRole == .oil ? clay : [],
            additives: reportedRole == .additive ? clay : [],
            fragrances: reportedRole == .fragrance ? clay : []
        )

        let rows = RecipeIngredientReconciler.reconcile(draft, against: [])

        let row = try #require(rows.first)
        #expect(row.role == .additive)
        #expect(row.suggestedCategoryName == IngredientCategory.Name.additives)
    }

    @Test func reconcile_UnmatchedEssentialOilListedAsAnOil_IsAFragrance() throws {
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Yuzu Essential Oil", amount: 5, unit: "g")])

        let rows = RecipeIngredientReconciler.reconcile(draft, against: [])

        #expect(rows.first?.role == .fragrance)
    }

    @Test func reconcile_UnmatchedIngredient_KeepsTheModelsSection() throws {
        let draft = RecipeImportDraft.mock(
            oils: [],
            fragrances: [ImportedIngredient(name: "Yuzu Absolute", amount: 1, unit: "g")]
        )
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [])

        #expect(rows.first?.role == .fragrance)
    }

    @Test func reconcile_MatchedIngredientWithoutCategory_KeepsTheModelsSection() throws {
        let (container, context) = try makeContext()
        _ = container
        let uncategorised = Ingredient(name: "Silk Peptide", unit: "g")
        context.insert(uncategorised)

        let draft = RecipeImportDraft.mock(
            oils: [],
            fragrances: [ImportedIngredient(name: "Silk Peptide", amount: 1, unit: "g")]
        )
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [uncategorised])

        #expect(rows.first?.role == .fragrance)
    }

    /// A lye the user created under a name the checker doesn't know is still
    /// a lye: counted among the oils it would throw off the lye weight.
    @Test func reconcile_MatchInTheLyesCategory_ProducesNoRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        context.insert(lyes)
        let flakes = Ingredient(name: "Caustic Flakes", category: lyes, unit: "g")
        context.insert(flakes)
        let inventory = makeInventory(in: context) + [flakes]

        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 700, unit: "g"),
            ImportedIngredient(name: "Caustic Flakes", amount: 131, unit: "g")
        ])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)

        #expect(rows.map(\.imported.name) == ["Olive Oil"])
    }
}
