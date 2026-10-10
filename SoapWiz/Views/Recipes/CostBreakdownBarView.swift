import SwiftUI
import SwiftData

struct CostBreakdownBarView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var model: RecipeFormViewModel
    @Binding var isExpanded: Bool
    var availableHeight: CGFloat = 0
    @Query private var settingsRecords: [AppSettings]
    @State private var visibleCardID: AnyHashable?
    @State private var keyboardVisible = false
    /// A touch taller than anything a page's header holds, so the bar keeps
    /// one height as it pages between a plain title and a size's controls.
    @ScaledMetric(relativeTo: .subheadline) private var compactPageHeaderHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var regularPageHeaderHeight: CGFloat = 24

    /// Narrower than the screens' readable width, so on iPad the bar reads as
    /// a floating summary rather than a second sheet.
    private static let maximumWidth: CGFloat = 640

    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var headlineFont: Font { isRegular ? .body : .subheadline }
    private var captionFont: Font { isRegular ? .footnote : .caption }
    private var horizontalPadding: CGFloat { isRegular ? 20 : 16 }

    private var pvpFactor: Double { AppSettings.canonical(from: settingsRecords)?.pvpFactor ?? 4.0 }

    var body: some View {
        let batch = model.wholeBatchBreakdown
        let canExpand = model.hasIngredients
        let expanded = isExpanded && canExpand
        VStack(spacing: 0) {
            header(canExpand: canExpand, expanded: expanded, batch: batch)

            if expanded {
                VStack(spacing: 0) {
                    carousel(batch: batch)
                    pageDots
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .modifier(CostBarSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    /// Collapsed, the batch cost and its RRP; expanded, the showing page's own
    /// header in their place. The size header holds live controls, so the tap
    /// that folds the bar sits behind the header, and only what isn't a
    /// control lets it through.
    ///
    /// Assistive technologies get the toggle as an explicit action: the whole
    /// collapsed bar is one button, and the chevron is one once expanded, so
    /// the size controls beside it stay reachable on their own.
    @ViewBuilder
    private func header(canExpand: Bool, expanded: Bool, batch: ProductCostBreakdown) -> some View {
        let content = headerContent(canExpand: canExpand, expanded: expanded, batch: batch)
        if expanded {
            content
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cost breakdown")
                .accessibilityValue(model.costBarSummary(pvpFactor: pvpFactor, currencyCode: currencyCode))
                .accessibilityAddTraits(canExpand ? .isButton : [])
                .accessibilityAction { toggleExpanded(canExpand: canExpand) }
        }
    }

    private func headerContent(canExpand: Bool, expanded: Bool, batch: ProductCostBreakdown) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eurosign.circle.fill")
                .foregroundStyle(Color.amberText)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if expanded {
                pageHeader(batch: batch)
                    .frame(minHeight: isRegular ? regularPageHeaderHeight : compactPageHeaderHeight)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cost breakdown")
                        .font(captionFont)
                        .foregroundStyle(Color.inkSoft)
                    Text(model.costBarSummary(pvpFactor: pvpFactor, currencyCode: currencyCode))
                        .font(headlineFont.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
            if canExpand {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.inkSoft)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Collapse cost breakdown")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { toggleExpanded(canExpand: canExpand) }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, isRegular ? 14 : 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded(canExpand: canExpand) }
                .accessibilityHidden(true)
        }
    }

    private func toggleExpanded(canExpand: Bool) {
        guard canExpand else { return }
        withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
    }

    @ViewBuilder
    private func pageHeader(batch: ProductCostBreakdown) -> some View {
        switch model.costBarPage(for: visibleCardID) {
        case .addSize:
            Text("New size")
                .font(headlineFont.weight(.semibold))
                .foregroundStyle(Color.ink)
                .allowsHitTesting(false)
        case .product(let id):
            if let draft = model.productDrafts.first(where: { $0.id == id }) {
                let isDefault = model.productDrafts.first?.id == id
                RecipeProductHeaderView(
                    draft: draftBinding(id: id, fallback: draft),
                    breakdown: model.breakdownAndCost(for: draft, batch: batch),
                    availableUnits: ProductUnit.allCases.filter { $0 != .wholeBatch },
                    isDefault: isDefault,
                    onDelete: isDefault ? nil : { deleteProduct(id: id) }
                )
                // Each size gets its own header, so a focused size field or an
                // open unit picker doesn't carry over to the next size.
                .id(id)
            }
        }
    }

    /// Finds the size by id on every read and write. A size field that is
    /// still focused when its size is deleted commits as it loses focus, and a
    /// binding by position would then write past the end of the array.
    private func draftBinding(id: UUID, fallback: RecipeProductDraft) -> Binding<RecipeProductDraft> {
        Binding(
            get: { model.productDrafts.first { $0.id == id } ?? fallback },
            set: { newValue in
                guard let index = model.productDrafts.firstIndex(where: { $0.id == id }) else { return }
                model.productDrafts[index] = newValue
            }
        )
    }

    private func carousel(batch: ProductCostBreakdown) -> some View {
        let fraction: CGFloat = keyboardVisible ? 0.3 : 0.4
        let maxHeight: CGFloat = availableHeight > 0 ? availableHeight * fraction : 350
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.productDrafts) { draft in
                        productColumn(draft: draft, batch: batch)
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
                    .id(CostBarPage.addSizeID)
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

    private func productColumn(draft: RecipeProductDraft, batch: ProductCostBreakdown) -> some View {
        let breakdown = model.breakdownAndCost(for: draft, batch: batch)
        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                RecipeProductCardView(breakdown: breakdown, model: model)
            }
            if breakdown.total > 0 {
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
            : CostBarPage.addSizeID
        withTransaction(transaction) { visibleCardID = slotID }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard visibleCardID == slotID else { return }
            withAnimation { visibleCardID = AnyHashable(previousID) }
        }
    }

    /// The page's only Total and RRP, under a single `inkSoft` hairline,
    /// pinned below the lines as they scroll.
    private func productTotals(_ breakdown: ProductCostBreakdown) -> some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.inkSoft)
                .frame(height: 1)
                .padding(.bottom, 6)
            HStack {
                Text("Total")
                Spacer()
                Text(breakdown.total.formatted(.currency(code: currencyCode)))
            }
            .foregroundStyle(Color.ink)
            HStack {
                Text("RRP")
                Spacer()
                Text((breakdown.total * pvpFactor).formatted(.currency(code: currencyCode)))
            }
            .foregroundStyle(Color.amberText)
        }
        .font(headlineFont.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, horizontalPadding)
        .padding(.top, isRegular ? 10 : 8)
    }

    /// One dot per size and one for the add-size page, the showing one in amber.
    private var pageDots: some View {
        let pages = model.costBarPages
        let current = model.costBarPage(for: visibleCardID)
        let position = (pages.firstIndex(of: current) ?? 0) + 1
        return HStack(spacing: 6) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == current ? Color.amberText : Color.ruleStrong.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(position) of \(pages.count)")
    }
}

/// Liquid Glass made dense with a `paperRaised` tint, so the list behind reads
/// only as a soft blur; solid `paperRaised` with Reduce Transparency.
private struct CostBarSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        fill(content)
            .overlay(shape.strokeBorder(reduceTransparency ? Color.rule : Color.glassEdge, lineWidth: 1))
            .shadow(color: Color.shadow.opacity(colorScheme == .dark ? 0.40 : 0.16), radius: 10, y: 6)
    }

    @ViewBuilder
    private func fill(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.paperRaised, in: shape)
        } else if #available(iOS 26, *) {
            content
                .background(Color.paperRaised.opacity(0.78), in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
