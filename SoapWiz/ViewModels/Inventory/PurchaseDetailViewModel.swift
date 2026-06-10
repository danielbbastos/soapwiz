import Foundation
import SwiftData

@MainActor
@Observable
final class PurchaseDetailViewModel {
    let purchase: IngredientPurchase
    var isEditingAmount: Bool = false
    var editingValue: String = ""
    private let originalAmount: Double
    private let originalOpeningDate: Date?

    init(purchase: IngredientPurchase) {
        self.purchase = purchase
        self.originalAmount = purchase.remainingAmount
        self.originalOpeningDate = purchase.openingDate
    }

    var isDirty: Bool {
        purchase.remainingAmount != originalAmount || purchase.openingDate != originalOpeningDate
    }

    var usageEntries: [UsageEntry] {
        UsageHistory.entries(for: purchase)
    }

    func undo() {
        purchase.remainingAmount = originalAmount
        purchase.openingDate = originalOpeningDate
    }

    func startEditing() {
        editingValue = purchase.remainingAmount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        isEditingAmount = true
    }

    func adjust(by step: Double) {
        let newValue = (purchase.remainingAmount + step).clamped(to: 0...purchase.quantity)
        purchase.remainingAmount = newValue
        autoSetOpeningDateIfNeeded()
    }

    func commitEdit() {
        if let parsed = Double(editingValue.replacingOccurrences(of: ",", with: ".")) {
            purchase.remainingAmount = parsed.clamped(to: 0...purchase.quantity)
            autoSetOpeningDateIfNeeded()
        }
        isEditingAmount = false
    }

    private func autoSetOpeningDateIfNeeded() {
        if purchase.openingDate == nil && purchase.remainingAmount < purchase.quantity {
            purchase.openingDate = Date.now
        }
    }


}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
