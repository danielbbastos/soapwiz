import Testing
@testable import SoapWiz

@Suite
struct RecipeImportSettingRowsTests {

    @Test func statedLyeSettingRows_NothingStated_ReturnsNoRows() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: nil, waterParts: nil)

        #expect(draft.statedLyeSettingRows.isEmpty)
    }

    @Test func statedLyeSettingRows_AllStated_ListsLyeSuperFatThenWater() {
        let draft = RecipeImportDraft.mock(lyeType: "NaOH", superFat: 5, waterParts: 2.5)

        let rows = draft.statedLyeSettingRows

        #expect(rows == [
            RecipeImportSettingRow(title: "Lye", value: "NaOH"),
            RecipeImportSettingRow(title: "Super Fat", value: "\(PercentageFormatter.string(5))%"),
            RecipeImportSettingRow(title: "Water : Lye", value: "\(PercentageFormatter.string(2.5)) : 1")
        ])
    }

    @Test func statedLyeSettingRows_OnlySuperFatStated_ClaimsNoLye() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: 7, waterParts: nil)

        let rows = draft.statedLyeSettingRows

        #expect(rows.map(\.title) == ["Super Fat"])
    }

    @Test func statedLyeSettingRows_ZeroSuperFat_StillListed() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: 0, waterParts: nil)

        let rows = draft.statedLyeSettingRows

        #expect(rows == [RecipeImportSettingRow(title: "Super Fat", value: "\(PercentageFormatter.string(0))%")])
    }

    @Test func statedLyeSettingRows_OnlyFragranceStated_ReturnsNoRows() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: nil, waterParts: nil, fragrancePercentage: 3)

        #expect(draft.statedLyeSettingRows.isEmpty)
    }
}
