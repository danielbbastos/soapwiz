import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe text numbers")
struct RecipeTextNumbersTests {

    @Test(arguments: [
        ("Use 4.5 oz lye", 4.5),
        ("Sodium Lactate 4,5 g", 4.5),
        ("Batch size: 1,000 g", 1_000),
        ("Batch size: 1.000 g", 1_000),
        ("Olive Oil 45%", 45),
        ("½ tsp salt", 0.5),
        ("1 1/2 tbsp honey", 1.5),
        ("1/2 cup oatmeal", 0.5),
        ("2¼ oz shea", 2.25),
        ("water:lye 2:1", 2)
    ])
    func contains_WrittenNumber_IsFound(_ text: String, _ value: Double) {
        #expect(RecipeTextNumbers.contains(value, in: RecipeTextNumbers.values(in: text)))
    }

    @Test func contains_NumberNotInText_IsNotFound() {
        let values = RecipeTextNumbers.values(in: "Oils:\nOlive oil\nCoconut oil")
        #expect(!RecipeTextNumbers.contains(200, in: values))
    }

    @Test func values_TextWithoutNumbers_IsEmpty() {
        #expect(RecipeTextNumbers.values(in: "Olive oil, coconut oil").isEmpty)
    }

    @Test func contains_DifferentDecimal_IsNotFound() {
        let values = RecipeTextNumbers.values(in: "Superfat 4.5%")
        #expect(!RecipeTextNumbers.contains(4.6, in: values))
    }

    @Test(arguments: [("4.5", 4.5), ("4,5", 4.5), ("12", 12.0)])
    func decimal_DotOrCommaSeparator_Reads(_ token: String, _ expected: Double) {
        #expect(RecipeTextNumbers.decimal(Substring(token)) == expected)
    }
}
