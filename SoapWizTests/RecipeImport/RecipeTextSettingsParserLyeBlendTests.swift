import Testing
import Foundation
@testable import SoapWiz

/// A share written beside each lye of a blend is not a purity. Read as one it
/// makes the form weigh more lye than the recipe needs.
@Suite("Recipe text settings parser, lye blend shares")
struct RecipeTextSettingsParserLyeBlendTests {

    @Test(arguments: [
        "75% NaOH, 25% KOH",
        "90% NaOH / 10% KOH",
        "NaOH 60% / KOH 40%",
        "80% KOH 20% NaOH"
    ])
    func lyePurity_BlendShares_AreNotAPurity(_ text: String) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == nil)
    }

    @Test(arguments: [
        "90% NaOH, KOH for the rest",
        "85% NaOH, 15% potash",
        "90% NaOH / 10% potassium lye",
        "75% NaOH, 90% pure KOH",
        "purity: 98%\nNaOH and KOH blend",
        "98% pure NaOH, 90% pure KOH"
    ])
    func lyePurity_BothLyesNamed_IsNilHoweverWorded(_ text: String) {
        #expect(RecipeTextSettingsParser.lyePurity(in: text) == nil)
    }

    @Test func lyePurity_PotashAloneWithoutSodiumLye_IsNotABlend() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "90% potash") == nil)
        #expect(RecipeTextSettingsParser.lyePurity(in: "90% KOH") == 90)
    }

    @Test func lyePurity_SingleLyeWithPercentage_IsStillRead() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "98% NaOH") == 98)
        #expect(RecipeTextSettingsParser.lyePurity(in: "KOH (90%)") == 90)
        #expect(RecipeTextSettingsParser.lyePurity(in: "100% pure NaOH") == 100)
    }

    @Test func lyePurity_BelowTheRange_IsNil() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "75% purity NaOH") == nil)
        #expect(RecipeTextSettingsParser.lyePurity(in: "NaOH 79%") == nil)
    }

    @Test func lyePurity_AtTheLowEdgeOfTheRange_IsRead() {
        #expect(RecipeTextSettingsParser.lyePurity(in: "80% purity KOH") == 80)
    }

    @Test func parse_SoapmakingFriendHybrid_KeepsTheSharesAndEachPurity() {
        let text = """
            NaOH Weight at 99 % Purity\t0.63 oz\t17.91 g
            KOH Weight at 90 % Purity\t2.95 oz\t83.76 g
            NaOH / KOH Ratio\t\t25 % / 75 %
            """

        let settings = RecipeTextSettingsParser.parse(text)

        #expect(settings.kohPercentage == 75)
        #expect(settings.naohPurity == 99)
        #expect(settings.kohPurity == 90)
        #expect(settings.lyePurity == nil)
    }

    @Test func checked_BlendShares_LeaveThePurityNil() {
        let draft = RecipeImportDraft.mock(lyeType: "NaOH")

        let checked = RecipeImportDraftChecker.checked(draft, against: "Olive Oil 500 g\n75% NaOH, 25% KOH")

        #expect(checked.lyePurity == nil)
    }
}
