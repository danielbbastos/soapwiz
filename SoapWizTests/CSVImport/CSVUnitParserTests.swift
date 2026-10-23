import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVUnitParserTests {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test(arguments: [
        ("g", IngredientUnit.grams), ("gr", .grams), ("grs", .grams), ("gram", .grams), ("grams", .grams),
        ("gramme", .grams), ("grammes", .grams),
        ("kg", .kilograms), ("kgs", .kilograms), ("kilo", .kilograms), ("kilos", .kilograms),
        ("kilogram", .kilograms), ("kilograms", .kilograms), ("kilogramme", .kilograms), ("kilogrammes", .kilograms),
        ("oz", .ounces), ("ounce", .ounces), ("ounces", .ounces),
        ("lb", .pounds), ("lbs", .pounds), ("pound", .pounds), ("pounds", .pounds),
        ("ml", .milliliters), ("millilitre", .milliliters), ("millilitres", .milliliters),
        ("milliliter", .milliliters), ("milliliters", .milliliters),
        ("l", .liters), ("lt", .liters), ("ltr", .liters), ("litre", .liters), ("litres", .liters),
        ("liter", .liters), ("liters", .liters),
        ("un", .units), ("unit", .units), ("units", .units), ("pc", .units), ("pcs", .units),
        ("piece", .units), ("pieces", .units), ("ea", .units), ("each", .units)
    ])
    func unit_Synonym_ReturnsUnit(text: String, expected: IngredientUnit) {
        #expect(CSVUnitParser.unit(text) == expected)
    }

    @Test(arguments: [
        ("KG", IngredientUnit.kilograms), ("Grams", .grams), ("  g  ", .grams), ("g.", .grams), ("Lbs.", .pounds),
        ("L", .liters), ("ML", .milliliters), ("Óz", .ounces), ("Pcs.", .units)
    ])
    func unit_CaseSpacingAndTrailingPoint_AreTolerated(text: String, expected: IngredientUnit) {
        #expect(CSVUnitParser.unit(text) == expected)
    }

    @Test(arguments: ["fl oz", "FL OZ", "fl. oz", "floz", "", "  ", ".", "widgets", "gg", "g.."])
    func unit_UnknownOrAmbiguous_ReturnsNil(text: String) {
        #expect(CSVUnitParser.unit(text) == nil)
    }

    @Test func quantities_NumberAndUnitWithSpace_Splits() {
        let result = CSVUnitParser.quantities(in: ["500 g", "2 lbs"], locale: us)
        #expect(result == [CSVQuantity(amount: 500, unit: .grams), CSVQuantity(amount: 2, unit: .pounds)])
    }

    @Test func quantities_NumberAndUnitWithoutSpace_Splits() {
        #expect(CSVUnitParser.quantities(in: ["1,5kg"], locale: german) == [CSVQuantity(amount: 1.5, unit: .kilograms)])
        #expect(CSVUnitParser.quantities(in: ["0.5L"], locale: us) == [CSVQuantity(amount: 0.5, unit: .liters)])
    }

    @Test func quantities_NumberOnly_HasNoUnit() {
        let result = CSVUnitParser.quantities(in: ["12", "  12  "], locale: us)
        #expect(result == [CSVQuantity(amount: 12, unit: nil), CSVQuantity(amount: 12, unit: nil)])
    }

    @Test func quantities_GroupedNumber_UsesTheLocale() {
        #expect(CSVUnitParser.quantities(in: ["1,000 g"], locale: us) == [CSVQuantity(amount: 1000, unit: .grams)])
        #expect(CSVUnitParser.quantities(in: ["1.000 g"], locale: german) == [CSVQuantity(amount: 1000, unit: .grams)])
    }

    @Test(arguments: [Locale(identifier: "en_US"), Locale(identifier: "de_DE")])
    func quantities_ColumnWithCommaDecimal_ReadsAmbiguousCellAsDecimal(locale: Locale) {
        let result = CSVUnitParser.quantities(in: ["1,000 g", "2,5 kg"], locale: locale)
        #expect(result == [CSVQuantity(amount: 1, unit: .grams), CSVQuantity(amount: 2.5, unit: .kilograms)])
    }

    @Test(arguments: [" ", "\u{00A0}", "\u{202F}"])
    func quantities_SpaceGroupedNumber_ReadsWholeNumber(space: String) {
        let result = CSVUnitParser.quantities(in: ["1\(space)234 g", "1\(space)234,5 kg"], locale: us)
        #expect(result == [CSVQuantity(amount: 1234, unit: .grams), CSVQuantity(amount: 1234.5, unit: .kilograms)])
    }

    @Test func quantities_SpaceGroupedAndCommaDecimalInOneColumn_ReadEach() {
        let result = CSVUnitParser.quantities(in: ["1 234 g", "2,5 kg"], locale: us)
        #expect(result == [CSVQuantity(amount: 1234, unit: .grams), CSVQuantity(amount: 2.5, unit: .kilograms)])
    }

    @Test func quantities_OnlyOneCellHasUnit_OthersHaveNone() {
        let result = CSVUnitParser.quantities(in: ["500 g", "250", "1,5"], locale: us)
        #expect(result == [
            CSVQuantity(amount: 500, unit: .grams),
            CSVQuantity(amount: 250, unit: nil),
            CSVQuantity(amount: 1.5, unit: nil)
        ])
    }

    @Test func quantities_TrailingPointOnUnit_IsTolerated() {
        #expect(CSVUnitParser.quantities(in: ["500 g."], locale: us) == [CSVQuantity(amount: 500, unit: .grams)])
    }

    @Test func quantities_PreservesCountAndOrder() {
        let result = CSVUnitParser.quantities(in: ["1 g", "x", "2 kg"], locale: us)
        #expect(result == [CSVQuantity(amount: 1, unit: .grams), nil, CSVQuantity(amount: 2, unit: .kilograms)])
        #expect(CSVUnitParser.quantities(in: [], locale: us).isEmpty)
    }

    @Test(arguments: ["", "   ", "abc", "g", "kg 5", "-5 g", "5 widgets", "5 fl oz", "5 g extra"])
    func quantities_UnreadableNumberOrUnknownUnit_ReturnsNil(text: String) {
        #expect(CSVUnitParser.quantities(in: [text], locale: us) == [nil])
    }
}
