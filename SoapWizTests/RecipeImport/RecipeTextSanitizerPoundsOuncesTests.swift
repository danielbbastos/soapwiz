import Testing
import Foundation
@testable import SoapWiz

@Suite("RecipeTextSanitizer pounds and ounces")
struct RecipeTextSanitizerPoundsOuncesTests {

    @Test(arguments: [
        ("1 lb 4 oz tallow", "20 oz tallow"),
        ("2 lbs 3.5 oz olive oil", "35.5 oz olive oil"),
        ("1 pound 4 ounces lard", "20 oz lard"),
        ("1 lb and 4 oz tallow", "20 oz tallow"),
        ("1 lb, 4 oz tallow", "20 oz tallow"),
        ("1 lb. 4 oz. tallow", "20 oz. tallow"),
        ("1lb 4oz tallow", "20 oz tallow"),
        ("2 LBS 8 OZ shea", "40 oz shea"),
        ("1,5 lb 2 oz coconut", "26 oz coconut")
    ])
    func cleanedLines_PoundsAndOunces_AreCombinedIntoOunces(_ line: String, _ expected: String) {
        #expect(RecipeTextSanitizer.cleanedLines(from: line) == [expected])
    }

    @Test(arguments: ["2 lb olive oil", "8 oz coconut oil", "1 lb of lard, 4 oz of tallow"])
    func cleanedLines_LoneUnit_IsUntouched(_ line: String) {
        #expect(RecipeTextSanitizer.cleanedLines(from: line) == [line])
    }

    @Test func sanitize_ForumPost_SendsTheCombinedAmountToTheModel() {
        let result = RecipeTextSanitizer.sanitize("1 lb 4 oz tallow\n8 oz coconut oil\n4 oz olive oil")

        #expect(result.text.contains("20 oz tallow"))
        #expect(!result.text.contains("lb"))
    }
}
