import SwiftUI
import SwiftData

struct CostBreakdownBarView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var model: RecipeFormViewModel
    @Binding var isExpanded: Bool
    var availableHeight: CGFloat = 0
    @Query private var settingsRecords: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @State private var visibleCardID: AnyHashable?
    @State private var keyboardVisible = false

    private var headlineFont: Font { horizontalSizeClass == .regular ? .body : .subheadline }
    private var captionFont: Font { horizontalSizeClass == .regular ? .footnote : .caption }
    private var totalsFont: Font { horizontalSizeClass == .regular ? .body : .caption }

    private var pvpFactor: Double { AppSettings.canonical(from: settingsRecords)?.pvpFactor ?? 4.0 }

    var body: some View {
        let batch = model.wholeBatchBreakdown
        let canExpand = model.hasIngredients
        let expanded = isExpanded && canExpand
        let cornerRadius: CGFloat = expanded ? 24 : 20
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            collapsedBar(canExpand: canExpand, expanded: expanded, batchTotal: batch.total)

            if expanded {
                carousel(batch: batch)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .glassEffectIOS26(in: shape)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .frame(maxWidth: ReadableWidth.maximum)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    private func collapsedBar(canExpand: Bool, expanded: Bool, batchTotal: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eurosign.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                if !expanded {
                    Text("Cost breakdown")
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                HStack(spacing: 6) {
                    Text(summaryText(canExpand: canExpand, batchTotal: batchTotal))
                        .font(headlineFont.weight(.semibold))
                        .monospacedDigit()
                    if expanded {
                        swipeHintButton
                    }
                }
            }
            Spacer()
            if canExpand {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
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

    private var swipeHintButton: some View {
        InfoPopoverIcon(text: "Swipe left to add another size.")
    }

    private func carousel(batch: ProductCostBreakdown) -> some View {
        let fraction: CGFloat = keyboardVisible ? 0.3 : 0.4
        let maxHeight: CGFloat = availableHeight > 0 ? availableHeight * fraction : 350
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach($model.productDrafts) { $draft in
                        productColumn(draft: $draft, batch: batch)
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                // The cards resize with the width but the offset keeps its old
                // point value, leaving two half pages after a rotation.
                Task {
                    guard let id = visibleCardID else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(id, anchor: .leading)
                    }
                }
            }
            .onAppear {
                if visibleCardID == nil, let firstID = model.productDrafts.first?.id {
                    visibleCardID = AnyHashable(firstID)
                }
            }
        }
    }

    private func productColumn(draft: Binding<RecipeProductDraft>, batch: ProductCostBreakdown) -> some View {
        let breakdown = model.breakdownAndCost(for: draft.wrappedValue, batch: batch)
        let draftID = draft.wrappedValue.id
        let isDefault = model.productDrafts.first?.id == draftID
        let onDelete: (() -> Void)? = isDefault ? nil : { deleteProduct(id: draftID) }
        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                RecipeProductCardView(
                    draft: draft,
                    breakdown: breakdown,
                    availableUnits: ProductUnit.allCases.filter { $0 != .wholeBatch },
                    model: model,
                    isDefault: isDefault,
                    onDelete: onDelete
                )
            }
            if breakdown.total > 0 {
                Divider().opacity(0.4)
                productTotals(breakdown)
            }
        }
    }

    /// The next card slides into the deleted card's slot at once, since the
    /// offset stays put; the carousel then glides back to the previous card.
    private func deleteProduct(id: UUID) {
        guard let index = model.productDrafts.firstIndex(where: { $0.id == id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        let previousID = withTransaction(transaction) { model.removeProduct(id: id) }
        guard let previousID else { return }
        let slotID: AnyHashable = model.productDrafts.indices.contains(index)
            ? AnyHashable(model.productDrafts[index].id)
            : AnyHashable("addButton")
        withTransaction(transaction) { visibleCardID = slotID }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard visibleCardID == slotID else { return }
            withAnimation { visibleCardID = AnyHashable(previousID) }
        }
    }

    @ViewBuilder
    private func productTotals(_ breakdown: ProductCostBreakdown) -> some View {
        HStack {
            Text("Total")
                .font(totalsFont.weight(.semibold))
            Spacer()
            Text(breakdown.total.formatted(.currency(code: currencyCode)))
                .font(totalsFont.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        HStack {
            Text("RRP")
                .font(totalsFont.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer()
            Text((breakdown.total * pvpFactor).formatted(.currency(code: currencyCode)))
                .font(totalsFont.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func summaryText(canExpand: Bool, batchTotal: Double) -> String {
        let totalText = batchTotal.formatted(.currency(code: currencyCode))
        if !canExpand {
            return "\(totalText) · Add ingredients first"
        }
        // Counted the way the detail screen lists them, so the two agree.
        let sizeCount = model.productDrafts.count(where: \.isSeparateFromBatch)
        if sizeCount > 0 {
            return "\(totalText) · \(sizeCount) size\(sizeCount == 1 ? "" : "s")"
        }
        return totalText
    }
}
