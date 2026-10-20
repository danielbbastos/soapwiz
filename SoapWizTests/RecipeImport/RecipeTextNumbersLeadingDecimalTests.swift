import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe text numbers, decimals without a leading zero")
struct RecipeTextNumbersLeadingDecimalTests {

    @Test(arguments: [
        ("Canola .5 oz", 0.5),
        (".5 oz canola", 0.5),
        ("Canola ,5 oz", 0.5),
        ("Canola (.25 oz)", 0.25),
        ("Olive 10 oz\nCanola .75 oz", 0.75)
    ])
    func contains_LeadingDecimal_IsReadAsLessThanOne(_ text: String, _ value: Double) {
        #expect(RecipeTextNumbers.contains(value, in: RecipeTextNumbers.values(in: text)))
    }

    @Test func contains_LeadingDecimal_IsNotAlsoReadAsAWholeNumber() {
        let values = RecipeTextNumbers.values(in: "Canola .5 oz")

        #expect(!RecipeTextNumbers.contains(5, in: values))
    }

    @Test(arguments: [("Use 1.5 oz", 1.5), ("Batch 1,000 g", 1_000), ("1 1/2 tbsp", 1.5), ("Olive 4.5 oz", 4.5)])
    func contains_ExistingReadings_AreUnchanged(_ text: String, _ value: Double) {
        #expect(RecipeTextNumbers.contains(value, in: RecipeTextNumbers.values(in: text)))
    }

    @Test func contains_PointAfterAWord_IsNotALeadingDecimal() {
        let values = RecipeTextNumbers.values(in: "mix well.5 minutes")

        #expect(!RecipeTextNumbers.contains(0.5, in: values))
        #expect(RecipeTextNumbers.contains(5, in: values))
    }
}
