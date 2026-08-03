import Testing
import Foundation
@testable import SoapWiz

@Suite("RecipeTextSanitizer")
struct RecipeTextSanitizerTests {

    // MARK: - Markup

    @Test func stripMarkup_HTMLTags_KeepsOnlyText() {
        let html = "<div class=\"recipe\"><p>Olive Oil 70%</p><p>Coconut Oil 30%</p></div>"
        let result = RecipeTextMarkupStripper.stripMarkup(html)
        #expect(result.contains("Olive Oil 70%"))
        #expect(result.contains("Coconut Oil 30%"))
        #expect(!result.contains("<"))
        #expect(!result.contains("class="))
    }

    @Test func stripMarkup_ScriptAndStyleBlocks_RemovesContentsToo() {
        let html = "<style>.a { color: red }</style><script>track('x')</script><p>Olive Oil 70%</p>"
        let result = RecipeTextMarkupStripper.stripMarkup(html)
        #expect(result.contains("Olive Oil"))
        #expect(!result.contains("color"))
        #expect(!result.contains("track"))
    }

    @Test func stripMarkup_BlockTags_BecomeLineBreaks() {
        let result = RecipeTextMarkupStripper.stripMarkup("<li>Olive Oil</li><li>Coconut Oil</li>")
        let lines = RecipeTextSanitizer.cleanedLines(from: result)
        #expect(lines.count == 2)
    }

    @Test func decodeEntities_NamedAndNumeric_AreDecoded() {
        let result = RecipeTextMarkupStripper.decodeEntities("Shea&nbsp;Butter &amp; Cocoa &#8212; &frac12; oz &#x41;")
        #expect(result.contains("Shea Butter & Cocoa"))
        #expect(result.contains("\u{2014}"))
        #expect(result.contains("1/2 oz"))
        #expect(result.contains("A"))
        #expect(!result.contains("&nbsp;"))
        #expect(!result.contains("&#"))
    }

    @Test func decodeEntities_NoAmpersand_ReturnsInputUnchanged() {
        let input = "Olive Oil 70%"
        #expect(RecipeTextMarkupStripper.decodeEntities(input) == input)
    }

    @Test func stripMarkdown_TableRows_LoseTheirPipes() {
        let markdown = "| Oil | Percent |\n|-----|---------|\n| Olive Oil | 70% |"
        let result = RecipeTextMarkupStripper.stripMarkdown(markdown)
        #expect(!result.contains("|"))
        #expect(result.contains("Olive Oil"))
        #expect(result.contains("70%"))
    }

    @Test func stripMarkdown_HeadingsLinksAndEmphasis_AreFlattened() {
        let markdown = "## **My Recipe**\nSee [the calculator](https://soapcalc.net) for more"
        let result = RecipeTextMarkupStripper.stripMarkdown(markdown)
        #expect(result.contains("My Recipe"))
        #expect(!result.contains("#"))
        #expect(!result.contains("**"))
        #expect(result.contains("the calculator"))
        #expect(!result.contains("soapcalc.net"))
    }

    // MARK: - Noise

    @Test func cleanedLines_Boilerplate_IsDropped() {
        let text = "Share this:\nOlive Oil 70%\nLeave a comment\nCoconut Oil 30%\n***"
        let lines = RecipeTextSanitizer.cleanedLines(from: text)
        #expect(lines == ["Olive Oil 70%", "Coconut Oil 30%"])
    }

    @Test func isBoilerplate_LongSentenceContainingAPhrase_IsKept() {
        let sentence = "Subscribe to the idea that a longer cure produces a much harder and milder bar of soap"
        #expect(!RecipeTextMarkupStripper.isBoilerplate(sentence))
    }

    @Test func cleanedLines_URLs_AreRemovedButTheLineSurvives() {
        let lines = RecipeTextSanitizer.cleanedLines(from: "Recipe from https://example.com/soap called Castile")
        #expect(lines == ["Recipe from called Castile"])
    }

    @Test func cleanedLines_BlankRunsAndPadding_AreCollapsed() {
        let lines = RecipeTextSanitizer.cleanedLines(from: "  Olive   Oil  70%  \n\n\n\n   \nCoconut Oil 30%")
        #expect(lines == ["Olive Oil 70%", "Coconut Oil 30%"])
    }

    @Test func cleanedLines_EmptyInput_ReturnsEmpty() {
        #expect(RecipeTextSanitizer.cleanedLines(from: "").isEmpty)
        #expect(RecipeTextSanitizer.cleanedLines(from: "   \n\n  \t ").isEmpty)
    }

    // MARK: - Scoring

    @Test func score_QuantityWithUnit_ScoresAboveBareProse() {
        let vocabulary = RecipeTextSanitizer.oilVocabulary(addingNames: [])
        let recipeLine = RecipeTextSanitizer.score("Coconut Oil 250 g", vocabulary: vocabulary)
        let proseLine = RecipeTextSanitizer.score("I have been making soap for many years now", vocabulary: vocabulary)
        #expect(recipeLine > proseLine)
    }

    @Test func score_ConfigurationKeyword_Scores() {
        let vocabulary = RecipeTextSanitizer.oilVocabulary(addingNames: [])
        #expect(RecipeTextSanitizer.score("Superfat: 5%", vocabulary: vocabulary) > 0)
        #expect(RecipeTextSanitizer.score("Sodium hydroxide", vocabulary: vocabulary) > 0)
    }

    @Test func oilVocabulary_UsesInventoryNames_AndDropsShortOnes() {
        let vocabulary = RecipeTextSanitizer.oilVocabulary(addingNames: ["Babassu Oil", "AB"])
        #expect(vocabulary.contains("babassu oil"))
        #expect(!vocabulary.contains("ab"))
    }

    @Test func score_InventoryName_LiftsALineWithNoUnits() {
        let plain = RecipeTextSanitizer.oilVocabulary(addingNames: [])
        let withInventory = RecipeTextSanitizer.oilVocabulary(addingNames: ["Kombo Butter"])
        let line = "Kombo Butter"
        #expect(RecipeTextSanitizer.score(line, vocabulary: withInventory) >
                RecipeTextSanitizer.score(line, vocabulary: plain))
    }

    // MARK: - Windowing

    @Test func densestWindow_EverythingFits_KeepsEveryLine() {
        let lines = ["Olive Oil 70%", "Coconut Oil 30%"]
        let scores = [3, 3]
        #expect(RecipeTextSanitizer.densestWindow(of: lines, scores: scores, characterBudget: 1_000) == lines)
    }

    @Test func densestWindow_OverBudget_KeepsTheHighestScoringRun() {
        let filler = Array(repeating: "some ordinary prose about soap", count: 10)
        let recipe = ["Olive Oil 700 g", "Coconut Oil 300 g"]
        let lines = filler + recipe + filler
        let scores = lines.map { $0.contains("Oil") ? 7 : 0 }
        let budget = lines.prefix(4).reduce(0) { $0 + $1.count + 1 }

        let kept = RecipeTextSanitizer.densestWindow(of: lines, scores: scores, characterBudget: budget)

        #expect(kept.contains("Olive Oil 700 g"))
        #expect(kept.contains("Coconut Oil 300 g"))
        #expect(kept.count < lines.count)
    }

    @Test func densestWindow_EmptyInput_ReturnsEmpty() {
        #expect(RecipeTextSanitizer.densestWindow(of: [], scores: [], characterBudget: 100).isEmpty)
    }

    // MARK: - End to end

    @Test func sanitize_ShortRecipe_PassesThroughUntrimmed() {
        let recipe = "Castile Bar\nOlive Oil 70%\nCoconut Oil 30%\nSuperfat 5%\nWater:Lye 2:1"
        let result = RecipeTextSanitizer.sanitize(recipe)
        #expect(!result.wasTrimmed)
        #expect(result.text.contains("Olive Oil 70%"))
        #expect(result.text.contains("Superfat 5%"))
    }

    /// The recipe survives intact and the comment section goes. The preamble is
    /// allowed to come along when it fits — inside the budget, extra context is
    /// free, and cutting it would risk cutting a recipe line that scored low.
    @Test func sanitize_BlogPost_KeepsTheWholeRecipeAndDropsTheComments() {
        let result = RecipeTextSanitizer.sanitize(Self.blogPost, characterBudget: 700)

        #expect(result.wasTrimmed)
        #expect(result.text.contains("Olive Oil 70%"))
        #expect(result.text.contains("Coconut Oil 25%"))
        #expect(result.text.contains("Castor Oil 5%"))
        #expect(result.text.contains("Superfat 5%"))
        #expect(result.text.contains("Water : Lye ratio 2:1"))
        #expect(result.text.contains("Lavender Essential Oil 3%"))
        #expect(!result.text.contains("Great recipe, thanks"))
        #expect(!result.text.contains("double batch"))
    }

    /// When the budget forces a choice, the recipe beats the personal story.
    @Test func sanitize_TightBudget_DropsThePreambleForTheRecipe() {
        let result = RecipeTextSanitizer.sanitize(Self.blogPost, characterBudget: 200)

        #expect(result.text.contains("Olive Oil 70%"))
        #expect(!result.text.lowercased().contains("grandmother would make soap"))
        #expect(!result.text.contains("Great recipe, thanks"))
    }

    @Test func sanitize_RespectsTheCharacterBudget() {
        let result = RecipeTextSanitizer.sanitize(Self.blogPost, characterBudget: 700)
        #expect(result.text.count <= 700)
    }

    @Test func sanitize_ReportsWhatItRemoved() {
        let html = "<p>Olive Oil 70%</p><p>Coconut Oil 30%</p>"
        let result = RecipeTextSanitizer.sanitize(html)
        #expect(result.originalLength == html.count)
        #expect(result.text.count < html.count)
    }

    @Test func sanitize_EmptyInput_ProducesEmptyResult() {
        let result = RecipeTextSanitizer.sanitize("")
        #expect(result.isEmpty)
        #expect(!result.wasTrimmed)
    }

    @Test func sanitize_WhitespaceOnly_IsTreatedAsTrimmedAway() {
        let result = RecipeTextSanitizer.sanitize("   \n\n\t  ")
        #expect(result.isEmpty)
        #expect(result.wasTrimmed)
    }

    @Test func sanitize_OneEnormousParagraph_IsSplitAndBudgeted() {
        let paragraph = Array(repeating: "words about soap making", count: 400).joined(separator: " ")
        let result = RecipeTextSanitizer.sanitize(paragraph + " Olive Oil 700 g Coconut Oil 300 g", characterBudget: 500)
        #expect(result.text.count <= 500)
        #expect(!result.isEmpty)
    }

    // MARK: - Fixtures

    /// A recipe the way it actually arrives: a personal preamble, the recipe,
    /// then instructions and a comment section.
    private static let blogPost = """
        <h1>My Grandmother's Castile Soap</h1>
        <p>Every summer my grandmother would make soap on the back porch, and the smell of it \
        still takes me straight back to that house. I have been meaning to write this one down \
        for years, and a few of you have asked, so here it finally is. Do read the safety notes \
        before you start, especially if this is your first batch.</p>
        <p>Share this:</p>
        <h2>The Recipe</h2>
        <ul>
        <li>Olive Oil 70%</li>
        <li>Coconut Oil 25%</li>
        <li>Castor Oil 5%</li>
        </ul>
        <p>Superfat 5%</p>
        <p>Water : Lye ratio 2:1</p>
        <p>Sodium hydroxide, 1000 g total oils</p>
        <p>Lavender Essential Oil 3%</p>
        <h2>Comments</h2>
        <p>Great recipe, thanks for sharing! I made a double batch last weekend and it came out \
        beautifully, though I did have to soap a little cooler than usual because my kitchen was \
        so warm. Looking forward to trying it with a bit of clay next time around.</p>
        """
}
