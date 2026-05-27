import SwiftUI

struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CostBreakdownBarView: View {
    @Bindable var model: RecipeFormViewModel
    @Binding var isExpanded: Bool
    var availableHeight: CGFloat = 0
    @State private var isSwipeHintPresented = false
    @State private var visibleCardID: AnyHashable?
    @State private var keyboardVisible = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        return f
    }()

    var body: some View {
        let canExpand = model.hasIngredients
        let expanded = isExpanded && canExpand
        let cornerRadius: CGFloat = expanded ? 24 : 20
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            collapsedBar(canExpand: canExpand)

            if expanded {
                Divider().opacity(0.4)
                carousel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .glassEffectIOS26(in: shape)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    private func collapsedBar(canExpand: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eurosign.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cost breakdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(summaryText(canExpand: canExpand))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if canExpand && isExpanded {
                        Button {
                            isSwipeHintPresented = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isSwipeHintPresented) {
                            Text("Swipe left to add another product size.")
                                .font(.footnote)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: 240)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .presentationBackground(.clear)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
            Spacer()
            if canExpand {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
        }
    }

    private var carousel: some View {
        let fraction: CGFloat = keyboardVisible ? 0.3 : 0.4
        let maxHeight: CGFloat = availableHeight > 0 ? availableHeight * fraction : 350
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach($model.productDrafts) { $draft in
                    let breakdown = model.breakdownAndCost(for: draft)
                    ScrollView(.vertical, showsIndicators: false) {
                        RecipeProductCardView(
                            draft: $draft,
                            breakdown: breakdown,
                            availableUnits: ProductUnit.allCases
                        )
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(AnyHashable(draft.id))
                }
                AddProductCardView {
                    model.addProduct(defaultUnitSymbol: ProductUnit.grams.rawValue)
                    if let newID = model.productDrafts.last?.id {
                        withAnimation { visibleCardID = AnyHashable(newID) }
                    }
                }
                .containerRelativeFrame(.horizontal)
                .id(AnyHashable("addButton"))
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleCardID)
        .frame(maxHeight: maxHeight)
        .onAppear {
            if visibleCardID == nil, let firstID = model.productDrafts.first?.id {
                visibleCardID = AnyHashable(firstID)
            }
        }
    }

    private func summaryText(canExpand: Bool) -> String {
        let total = model.batchTotalCost
        let totalText = Self.currencyFormatter.string(from: NSNumber(value: total)) ?? "—"
        if !canExpand {
            return "\(totalText) · Add ingredients first"
        }
        if !model.productDrafts.isEmpty {
            return "\(totalText) · \(model.productDrafts.count) product\(model.productDrafts.count == 1 ? "" : "s")"
        }
        return totalText
    }
}
