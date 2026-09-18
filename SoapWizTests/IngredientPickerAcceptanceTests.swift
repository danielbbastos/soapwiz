import Testing
@testable import SoapWiz

@Suite
struct IngredientPickerAcceptanceTests {

    // A general recipe's merged Ingredients section: oils, additives, and the
    // role-less "Others" bucket — but not fragrances, which keep their own section.
    private let generalRoles: Set<RecipeIngredientRole> = [.oil, .additive]

    @Test func accepts_GeneralMerged_OffersOthers() {
        #expect(IngredientPickerView.accepts(role: nil, allowedRoles: generalRoles, includesUnroled: true))
    }

    @Test func accepts_GeneralMerged_OffersOilAndAdditive() {
        #expect(IngredientPickerView.accepts(role: .oil, allowedRoles: generalRoles, includesUnroled: true))
        #expect(IngredientPickerView.accepts(role: .additive, allowedRoles: generalRoles, includesUnroled: true))
    }

    @Test func accepts_GeneralMerged_ExcludesFragrance() {
        #expect(!IngredientPickerView.accepts(role: .fragrance, allowedRoles: generalRoles, includesUnroled: true))
    }

    @Test func accepts_SoapOils_DoesNotOfferOthers() {
        #expect(!IngredientPickerView.accepts(role: nil, allowedRoles: [.oil], includesUnroled: false))
    }

    @Test func accepts_SoapOils_OffersOilOnly() {
        #expect(IngredientPickerView.accepts(role: .oil, allowedRoles: [.oil], includesUnroled: false))
        #expect(!IngredientPickerView.accepts(role: .additive, allowedRoles: [.oil], includesUnroled: false))
    }

    @Test func accepts_NoAllowedRoles_OffersEveryRoleIncludingOthers() {
        #expect(IngredientPickerView.accepts(role: nil, allowedRoles: nil, includesUnroled: false))
        #expect(IngredientPickerView.accepts(role: .fragrance, allowedRoles: nil, includesUnroled: false))
    }
}
