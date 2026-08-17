import Testing
import Foundation
@testable import SoapWiz

@Suite("Avatar colours")
@MainActor
struct AvatarColorTests {

    // MARK: - Assignment

    @Test func init_NewIngredient_StoresAColourFromThePalette() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")

        #expect(AvatarColor(rawValue: ingredient.avatarColorName) != nil)
    }

    /// The colour is what tells two ingredients apart in a list sorted by name,
    /// so it has to actually vary. One draw could legitimately repeat; twenty
    /// landing on the same colour means it isn't being drawn at all.
    @Test func init_ManyIngredients_DrawsMoreThanOneColour() {
        let colours = Set((0..<20).map { Ingredient(name: "Oil \($0)", unit: "g").avatarColorName })

        #expect(colours.count > 1)
    }

    // MARK: - Resolution

    @Test func avatarColor_StoredValue_ResolvesToIt() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.avatarColorName = AvatarColor.teal.rawValue

        #expect(ingredient.avatarColor == .teal)
    }

    /// A row written before this attribute existed, or arriving from a device on
    /// an older build. It must still render a colour rather than nothing.
    @Test func avatarColor_NotStored_FallsBackToOneDerivedFromTheName() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.avatarColorName = ""

        #expect(ingredient.avatarColor == AvatarColor.derived(from: "Olive Oil"))
    }

    /// A value from a newer build that added a colour this one doesn't know.
    @Test func avatarColor_UnknownValue_FallsBackToOneDerivedFromTheName() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.avatarColorName = "chartreuse"

        #expect(ingredient.avatarColor == AvatarColor.derived(from: "Olive Oil"))
    }

    // MARK: - Derivation

    @Test func derived_SameName_IsStable() {
        #expect(AvatarColor.derived(from: "Coconut Oil") == AvatarColor.derived(from: "Coconut Oil"))
    }

    /// Folded through `lookupKey`, so correcting the capitalisation or the
    /// accents on a name doesn't change the colour the user already knows it by.
    @Test func derived_NameDifferingOnlyInCaseOrAccents_IsTheSame() {
        #expect(AvatarColor.derived(from: "  ÓLEO de oliva ") == AvatarColor.derived(from: "oleo de oliva"))
    }

    @Test func derived_DifferentNames_DoNotAllCollapseToOneColour() {
        let names = ["Olive Oil", "Coconut Oil", "Castor Oil", "Shea Butter", "Lye", "Lavender", "Beeswax"]

        #expect(Set(names.map(AvatarColor.derived(from:))).count > 1)
    }

    @Test func derived_EmptyName_StillReturnsAColour() {
        #expect(AvatarColor.allCases.contains(AvatarColor.derived(from: "")))
    }

    // MARK: - Letter

    @Test func avatarLetter_Name_IsItsUppercasedInitial() {
        #expect(Ingredient(name: "olive oil", unit: "g").avatarLetter == "O")
    }

    @Test func avatarLetter_NameWithLeadingWhitespace_SkipsIt() {
        #expect(Ingredient(name: "   shea butter", unit: "g").avatarLetter == "S")
    }

    @Test func avatarLetter_AccentedName_KeepsTheAccent() {
        #expect(Ingredient(name: "Óleo de Coco", unit: "g").avatarLetter == "Ó")
    }

    @Test func avatarLetter_EmptyName_IsEmpty() {
        #expect(Ingredient(name: "", unit: "g").avatarLetter.isEmpty)
    }

    @Test func avatarLetter_WhitespaceOnlyName_IsEmpty() {
        #expect(Ingredient(name: "   ", unit: "g").avatarLetter.isEmpty)
    }
}
