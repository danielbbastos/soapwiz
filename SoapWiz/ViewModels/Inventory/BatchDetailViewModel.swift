import Foundation
import SwiftData

@MainActor
@Observable
final class BatchDetailViewModel {
    let batch: IngredientBatch
    var isEditingAmount: Bool = false
    var editingValue: String = ""
    private let originalAmount: Double

    init(batch: IngredientBatch) {
        self.batch = batch
        self.originalAmount = batch.remainingAmount
    }

    var isDirty: Bool { batch.remainingAmount != originalAmount }

    func undo() {
        batch.remainingAmount = originalAmount
    }

    func startEditing() {
        editingValue = batch.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))
        isEditingAmount = true
    }

    func adjust(by step: Double) {
        let newValue = (batch.remainingAmount + step).clamped(to: 0...batch.quantity)
        batch.remainingAmount = newValue
    }

    func commitEdit() {
        if let parsed = Double(editingValue.replacingOccurrences(of: ",", with: ".")) {
            batch.remainingAmount = parsed.clamped(to: 0...batch.quantity)
        }
        isEditingAmount = false
    }


}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
