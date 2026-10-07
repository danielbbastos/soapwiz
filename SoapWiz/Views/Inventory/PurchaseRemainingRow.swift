import SwiftUI

/// The purchase detail's Remaining row: a figure that opens for typing, with
/// steppers either side and an undo while the amount differs from where it began.
/// At zero the figure turns `danger` and an Out stamp sits under the label.
/// At accessibility text sizes the controls move under the label.
struct PurchaseRemainingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let purchase: IngredientPurchase
    let unit: String
    @Bindable var model: PurchaseDetailViewModel

    @FocusState private var amountFocused: Bool

    private var isOut: Bool { purchase.remainingAmount <= 0 }

    private func figure(_ amount: Double) -> Text {
        Text.honeyLedgerFigure(
            amount.formatted(.number.precision(.fractionLength(0...2))),
            unit: unit,
            numberColor: isOut ? .danger : .ink
        )
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    label
                    controls
                }
            } else {
                HStack {
                    label
                        .layoutPriority(1)
                    if !model.isEditingAmount {
                        Spacer()
                    }
                    controls
                }
            }
        }
        .onChange(of: model.isEditingAmount) {
            if model.isEditingAmount { amountFocused = true }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Remaining")
                .font(.body)
                .foregroundStyle(Color.ink)
            if isOut && !model.isEditingAmount {
                let out = IngredientStockStamp.out
                StatusStamp(word: out.word, tone: out.tone, glyph: out.glyph)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if model.isEditingAmount {
            HStack(spacing: 8) {
                TextField("Amount", text: $model.editingValue.decimalOnly())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .tint(Color.amber)
                    .frame(minWidth: 80, maxWidth: .infinity)
                    .focused($amountFocused)
                    .onSubmit { model.commitEdit() }
                Button("Done") { model.commitEdit() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amberText)
            }
        } else {
            HStack(spacing: 8) {
                if model.isDirty {
                    Button { model.undo() } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.amberText)
                    .accessibilityLabel("Undo")
                }

                Button { model.adjust(by: -10) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.inkSoft)
                .accessibilityLabel("Decrease")

                Button { model.startEditing() } label: {
                    ZStack {
                        figure(purchase.quantity)
                            .hidden()
                        figure(purchase.remainingAmount)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)

                Button { model.adjust(by: 10) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.inkSoft)
                .accessibilityLabel("Increase")
            }
        }
    }
}
