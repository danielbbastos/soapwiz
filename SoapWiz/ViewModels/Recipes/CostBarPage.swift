import Foundation

/// A page of the cost breakdown bar's carousel: one per size, the whole-batch
/// default first, then the page that adds a size.
enum CostBarPage: Hashable {
    case product(UUID)
    case addSize

    /// The scroll id of the add-size page; a size's page uses its draft id.
    static let addSizeID: AnyHashable = "addButton"
}

extension RecipeFormViewModel {
    var costBarPages: [CostBarPage] {
        productDrafts.map { .product($0.id) } + [.addSize]
    }

    /// The page the carousel is showing for its scroll position: the first
    /// size until the carousel has settled on one, or when the id is gone.
    func costBarPage(for scrollID: AnyHashable?) -> CostBarPage {
        if scrollID == CostBarPage.addSizeID { return .addSize }
        if let draft = productDrafts.first(where: { AnyHashable($0.id) == scrollID }) {
            return .product(draft.id)
        }
        return productDrafts.first.map { .product($0.id) } ?? .addSize
    }

    /// The collapsed bar's one line: the batch cost and what it should sell for.
    func costBarSummary(pvpFactor: Double, currencyCode: String) -> String {
        let total = wholeBatchBreakdown.total
        let totalText = total.formatted(.currency(code: currencyCode))
        guard hasIngredients else {
            return String(localized: "\(totalText) · Add ingredients first")
        }
        let rrpText = (total * pvpFactor).formatted(.currency(code: currencyCode))
        return String(localized: "Batch \(totalText) · RRP \(rrpText)")
    }
}
