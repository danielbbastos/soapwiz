import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientIndex", .serialized)
@MainActor
struct IngredientIndexTests {

    @Test func named_IgnoresCaseAndDiacritics() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let oliva = InventoryImportTestSupport.insertIngredient("Óleo de Oliva", in: context)

        let index = IngredientIndex([oliva])

        #expect(index.ingredient(named: "OLEO DE OLIVA") === oliva)
        #expect(index.ingredient(named: "Olive Oil") == nil)
    }

    @Test func named_TwoCopies_PrefersTheOneWithASapValue() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let bare = InventoryImportTestSupport.insertIngredient("Olive Oil", in: context)
        let calculable = InventoryImportTestSupport.insertIngredient("Olive Oil", in: context)
        calculable.sapValue = 0.135

        #expect(IngredientIndex([bare, calculable]).ingredient(named: "olive oil") === calculable)
        #expect(IngredientIndex([calculable, bare]).ingredient(named: "olive oil") === calculable)
    }

    @Test func named_TwoCopiesWithoutSapValue_KeepsTheFirst() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let first = InventoryImportTestSupport.insertIngredient("Honey", in: context)
        let second = InventoryImportTestSupport.insertIngredient("Honey", in: context)

        #expect(IngredientIndex([first, second]).ingredient(named: "Honey") === first)
    }

    @Test func named_BlankName_IsNeverIndexed() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let blank = InventoryImportTestSupport.insertIngredient("  ", in: context)

        #expect(IngredientIndex([blank]).ingredient(named: "") == nil)
    }

    @Test func slug_TwoCopies_PrefersTheOneWithASapValue() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let bare = InventoryImportTestSupport.insertIngredient("Olive Oil", slug: "olive-oil", in: context)
        let calculable = InventoryImportTestSupport.insertIngredient("Olive", slug: "olive-oil", in: context)
        calculable.sapValue = 0.135

        #expect(IngredientIndex([bare, calculable]).ingredient(slug: "olive-oil") === calculable)
    }

    @Test func slug_EmptySlug_IsNeverIndexed() throws {
        let (container, context) = try InventoryImportTestSupport.makeContext()
        _ = container
        let custom = InventoryImportTestSupport.insertIngredient("Custom", in: context)

        #expect(IngredientIndex([custom]).ingredient(slug: "") == nil)
    }
}
