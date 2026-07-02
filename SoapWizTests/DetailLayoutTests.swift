import Testing
import SwiftUI
@testable import SoapWiz

@Suite("DetailLayout")
struct DetailLayoutTests {

    @Test func init_RegularSizeClass_IsTwoColumn() {
        #expect(DetailLayout(sizeClass: .regular) == .twoColumn)
    }

    @Test func init_CompactSizeClass_IsSingle() {
        #expect(DetailLayout(sizeClass: .compact) == .single)
    }

    @Test func init_NilSizeClass_IsSingle() {
        #expect(DetailLayout(sizeClass: nil) == .single)
    }
}

@Suite("RecipeDetailLayout")
struct RecipeDetailLayoutTests {

    // MARK: Compact always stacks, regardless of width

    @Test func init_CompactSizeClass_IsStacked() {
        #expect(RecipeDetailLayout(sizeClass: .compact, width: 1200) == .stacked)
    }

    @Test func init_NilSizeClass_IsStacked() {
        #expect(RecipeDetailLayout(sizeClass: nil, width: 1200) == .stacked)
    }

    // MARK: Regular picks by measured width

    @Test func init_RegularSqueezedBySidebarInPortrait_IsStacked() {
        // iPad Air 11" portrait with the sidebar open: detail ≈ 500 pt.
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 500) == .stacked)
    }

    @Test func init_RegularPortraitFullWidth_IsSideBySideTop() {
        // iPad Air 11" portrait, sidebar collapsed: detail ≈ 820 pt.
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 820) == .sideBySideTop)
    }

    @Test func init_RegularLandscapeWithSidebar_IsSideBySideTop() {
        // iPad Air 11" landscape with the sidebar open: detail ≈ 860 pt.
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 860) == .sideBySideTop)
    }

    @Test func init_RegularLandscapeFullWidth_IsWide() {
        // iPad Air 11" landscape, sidebar collapsed: detail ≈ 1180 pt.
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 1180) == .wide)
    }

    // MARK: Boundaries

    @Test func init_RegularJustBelowSideBySideThreshold_IsStacked() {
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 699) == .stacked)
    }

    @Test func init_RegularAtSideBySideThreshold_IsSideBySideTop() {
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 700) == .sideBySideTop)
    }

    @Test func init_RegularJustBelowWideThreshold_IsSideBySideTop() {
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 999) == .sideBySideTop)
    }

    @Test func init_RegularAtWideThreshold_IsWide() {
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 1000) == .wide)
    }

    @Test func init_RegularZeroWidthBeforeFirstLayout_IsStacked() {
        #expect(RecipeDetailLayout(sizeClass: .regular, width: 0) == .stacked)
    }
}
