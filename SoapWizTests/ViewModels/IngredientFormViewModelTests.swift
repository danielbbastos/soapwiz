import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientFormViewModel", .serialized)
@MainActor
struct IngredientFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func emptyNameInvalid() {
        let model = IngredientFormViewModel()
        #expect(!model.isValid)
    }

    @Test func requiresNameAndUnit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        #expect(!model.isValid)
        model.name = "Olive Oil"
        #expect(!model.isValid)
        model.selectedUnit = gram
        #expect(model.isValid)
    }

    @Test func whitespaceOnlyNameInvalid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "   "
        model.selectedUnit = gram
        #expect(!model.isValid)
    }

    @Test func saveInsertsTrimmedFields() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cat = IngredientCategory(name: "Oils")
        ctx.insert(cat)
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "  Olive Oil  "
        model.selectedUnit = gram
        model.selectedCategory = cat
        let returned = model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.name == "Olive Oil")
        #expect(fetched.first?.unit === gram)
        #expect(fetched.first?.category === cat)
        #expect(returned === fetched.first)
    }

    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.name = "Coconut Oil"
        let returned = model.save(context: ctx)
        #expect(existing.name == "Coconut Oil")
        #expect(returned == nil)
    }

    @Test func saveStoresThreshold() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.lowStockThreshold = "100"
        let ingredient = model.save(context: ctx)
        #expect(ingredient?.lowStockThreshold == 100)
    }

    @Test func saveClearsThresholdWhenEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 50
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.lowStockThreshold = ""
        model.save(context: ctx)
        #expect(existing.lowStockThreshold == nil)
    }

    @Test func populatesThresholdWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 75.5
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        let parsed = Double(model.lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        #expect(parsed == 75.5)
    }

    // MARK: - suggestCode

    @Test func suggestCode_EmptyName_ReturnsEmpty() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "", existingCodes: []) == "")
    }

    @Test func suggestCode_SingleWord_ReturnsFirstThreeCharsUppercased() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "Glycerin", existingCodes: []) == "GLY")
    }

    @Test func suggestCode_SingleWord_ShortWord_ReturnsFullUppercase() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "Lye", existingCodes: []) == "LYE")
    }

    @Test func suggestCode_SingleWord_TwoChars_ReturnsFullUppercase() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "AB", existingCodes: []) == "AB")
    }

    @Test func suggestCode_SingleWord_ConflictAtThree_ExtendsToFour() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "Glycerin", existingCodes: ["GLY"]) == "GLYC")
    }

    @Test func suggestCode_SingleWord_ConflictAtThreeAndFour_ExtendsToFive() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "Glycerin", existingCodes: ["GLY", "GLYC"]) == "GLYCE")
    }

    @Test func suggestCode_SingleWord_ConflictsUpToFive_ExtendsToSix() {
        let model = IngredientFormViewModel()
        #expect(model.suggestCode(for: "Glycerin", existingCodes: ["GLY", "GLYC", "GLYCE"]) == "GLYCER")
    }

    @Test func suggestCode_MultiWord_TwoWords_InitialsAtLeastThree_ReturnsInitials() {
        let model = IngredientFormViewModel()
        // "Soy Bean Oil" → 3 initials → "SBO"
        #expect(model.suggestCode(for: "Soy Bean Oil", existingCodes: []) == "SBO")
    }

    @Test func suggestCode_MultiWord_TwoWords_InitialsFewerThanThree_PadsFromLastWord() {
        let model = IngredientFormViewModel()
        // "Coconut Oil" → initials "CO" (2 chars) → pad with "I" from "OIL" → "COI"
        #expect(model.suggestCode(for: "Coconut Oil", existingCodes: []) == "COI")
    }

    @Test func suggestCode_MultiWord_TwoWords_InitialsOneChar_PadsFromLastWord() {
        let model = IngredientFormViewModel()
        // "Sodium Hydroxide" → initials "SH" → pad with "Y" from "HYDROXIDE" → "SHY"
        #expect(model.suggestCode(for: "Sodium Hydroxide", existingCodes: []) == "SHY")
    }

    @Test func suggestCode_MultiWord_ConflictOnInitials_ExtendsFromLastWord() {
        let model = IngredientFormViewModel()
        // "Coconut Oil" → "COI"; if "COI" taken, extend with "L" from "OIL" → "COIL"
        #expect(model.suggestCode(for: "Coconut Oil", existingCodes: ["COI"]) == "COIL")
    }

    @Test func suggestCode_MultiWord_ThreeInitialsConflict_ExtendsFromLastWord() {
        let model = IngredientFormViewModel()
        // "Soy Bean Oil" → "SBO"; if taken, extend with "I" from "OIL" → "SBOI"
        #expect(model.suggestCode(for: "Soy Bean Oil", existingCodes: ["SBO"]) == "SBOI")
    }

    @Test func suggestCode_MultiWord_StripsDiacritics() {
        let model = IngredientFormViewModel()
        // "Óleo de Alecrim" → strip accents → "Oleo de Alecrim" → initials "ODA"
        #expect(model.suggestCode(for: "Óleo de Alecrim", existingCodes: []) == "ODA")
    }

    @Test func suggestCode_SingleWord_StripsDiacritics() {
        let model = IngredientFormViewModel()
        // "Óleo" → strip accents → "Oleo" → first 3 → "OLE"
        #expect(model.suggestCode(for: "Óleo", existingCodes: []) == "OLE")
    }

    // MARK: - Code validation

    @Test func isValid_EmptyCode_DoesNotBlockSave() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.code = ""
        #expect(model.isValid)
    }

    @Test func isValid_CodeTwoChars_Invalid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.code = "OO"
        #expect(!model.isValid)
    }

    @Test func isValid_CodeThreeChars_Valid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.code = "OOI"
        #expect(model.isValid)
    }

    @Test func codeHasDuplicate_SameCodeOtherIngredient_ReturnsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let other = Ingredient(name: "Olive Oil")
        other.code = "COI"
        ctx.insert(other)

        let model = IngredientFormViewModel()
        model.code = "COI"
        #expect(model.codeHasDuplicate(among: [other]))
    }

    @Test func codeHasDuplicate_SameCodeSelf_ReturnsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Coconut Oil")
        existing.code = "COI"
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.code = "COI"
        #expect(!model.codeHasDuplicate(among: [existing]))
    }

    @Test func codeHasDuplicate_EmptyCode_ReturnsFalse() {
        let other = Ingredient(name: "Olive Oil")
        other.code = "COI"

        let model = IngredientFormViewModel()
        model.code = ""
        #expect(!model.codeHasDuplicate(among: [other]))
    }

    // MARK: - Auto-fill behaviour

    @Test func applyNameChange_NotManuallyEdited_UpdatesCode() {
        let model = IngredientFormViewModel()
        model.name = "Glycerin"
        model.applyNameChange(existingCodes: [])
        #expect(model.code == "GLY")
    }

    @Test func applyNameChange_ManuallyEdited_DoesNotOverride() {
        let model = IngredientFormViewModel()
        model.code = "MY"
        model.markCodeEdited()
        model.name = "Glycerin"
        model.applyNameChange(existingCodes: [])
        #expect(model.code == "MY")
    }

    @Test func markCodeEdited_DuringAutoFill_DoesNotSetFlag() {
        let model = IngredientFormViewModel()
        model.name = "Glycerin"
        model.applyNameChange(existingCodes: [])
        // Flag should still be false — the auto-fill must not set codeIsManuallyEdited
        #expect(!model.codeIsManuallyEdited)
    }

    // MARK: - Save persists code

    @Test func save_PersistsCodeUppercasedAndTrimmed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.code = " ooi "
        model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.code == "OOI")
    }

    @Test func save_UpdatesCodeOnExistingIngredient() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.code = "OOI"
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.code = "OO2"
        model.save(context: ctx)
        #expect(existing.code == "OO2")
    }

    @Test func populatesCodeWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.code = "OOI"
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        #expect(model.code == "OOI")
    }
}
