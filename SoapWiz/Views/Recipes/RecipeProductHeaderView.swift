import SwiftUI

/// A size's own header, shown in the cost breakdown bar while its page is
/// showing: the size, its unit, its warnings and the swipe hint, with delete
/// on the trailing edge for any size but the whole-batch default.
struct RecipeProductHeaderView: View {
    @Binding var draft: RecipeProductDraft
    let breakdown: ProductCostBreakdown
    let availableUnits: [ProductUnit]
    var isDefault = false
    var onDelete: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isUnitPickerPresented = false

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var headerFont: Font { isRegular ? .body : .subheadline }
    private var badgeFont: Font { isRegular ? .caption : .caption2 }
    private var sizeFieldWidth: CGFloat { isRegular ? 70 : 56 }

    private var displayedUnitLabel: String {
        if selectedUnit == .wholeBatch { return "Whole batch" }
        return draft.unitSymbol.isEmpty ? "—" : draft.unitSymbol
    }

    private var selectedUnit: ProductUnit? {
        ProductUnit(rawValue: draft.unitSymbol)
    }

    var body: some View {
        HStack(spacing: 8) {
            if !isDefault, selectedUnit?.requiresSize ?? true {
                NumericTextField(
                    prompt: "Size", value: $draft.size, width: sizeFieldWidth, alignment: .center,
                    allowsDecimals: selectedUnit != .partsOfBatch
                )
                    .font(headerFont.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .tint(Color.amber)
                    // Drawn below the text rather than padded in, so a size's
                    // header is exactly as tall as the whole batch's and the bar
                    // keeps its height while paging.
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.ruleStrong)
                            .frame(height: 1)
                            .offset(y: 2)
                    }
            }

            if isDefault {
                Text(displayedUnitLabel)
                    .font(headerFont.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .allowsHitTesting(false)
            } else {
                unitMenu
            }

            if breakdown.exceedsBatchWeight {
                warning("over batch")
            }

            if selectedUnit == .partsOfBatch, !draft.isSeparateFromBatch {
                warning("More than 1 part")
            }

            InfoPopoverIcon(text: "Swipe left to add another size.")
                .padding(.vertical, -6)

            Spacer(minLength: 0)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(headerFont)
                        .foregroundStyle(Color.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -8)
                .padding(.vertical, -6)
                .accessibilityLabel("Delete size")
            }
        }
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(badgeFont.weight(.semibold))
            .foregroundStyle(Color.warning)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .allowsHitTesting(false)
    }

    private var unitMenu: some View {
        Button {
            isUnitPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(displayedUnitLabel)
                    .font(headerFont.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.inkSoft)
            }
            .foregroundStyle(Color.ink)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isUnitPickerPresented) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(availableUnits, id: \.rawValue) { unit in
                    Button {
                        draft.selectUnit(unit)
                        isUnitPickerPresented = false
                    } label: {
                        HStack {
                            Text(unit.rawValue)
                                .font(headerFont)
                            Spacer()
                            if draft.unitSymbol == unit.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.amberText)
                            }
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(minWidth: 160)
            .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
            .shadow(color: Color.shadow.opacity(0.15), radius: 12, y: 6)
            .presentationBackground(.clear)
            .presentationCompactAdaptation(.popover)
        }
    }
}
