import SwiftUI
import SwiftData

struct CostBreakdownBarView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var model: RecipeFormViewModel
    @Binding var isExpanded: Bool
    /// How far the carousel has been dragged past its opening height.
    @Binding var extraHeight: CGFloat
    var availableHeight: CGFloat = 0
    /// The tallest the whole panel may be, or 0 while that isn't measured yet.
    var maximumHeight: CGFloat = 0
    /// Whether the window is wider than it is tall.
    var isLandscape = false
    var keyboardVisible = false
    @Query private var settingsRecords: [AppSettings]
    @State private var visibleCardID: AnyHashable?
    @State private var headerHeight: CGFloat = 0
    @State private var grabberHeight: CGFloat = 0
    @State private var dotsHeight: CGFloat = 0
    /// Each size page's card and footer heights, by size.
    @State private var contentHeights: [UUID: CGFloat] = [:]
    @State private var footerHeights: [UUID: CGFloat] = [:]
    /// A touch taller than anything a page's header holds, so the bar keeps
    /// one height as it pages between a plain title and a size's controls.
    @ScaledMetric(relativeTo: .body) private var pageHeaderHeight: CGFloat = 24

    /// Narrower than the screens' readable width, so on iPad the bar reads as
    /// a floating summary rather than a second sheet.
    private static let maximumWidth: CGFloat = 640
    private static let bottomPadding: CGFloat = 4

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
            if expanded {
                CostBarGrabber(extraHeight: $extraHeight, extraRoom: extraRoom)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { grabberHeight = $0 }
                    .transition(.opacity)
            }
            header(canExpand: canExpand, expanded: expanded, batch: batch)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            if expanded {
                VStack(spacing: 0) {
                    carousel(batch: batch)
                    pageDots
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dotsHeight = $0 }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .modifier(CostBarSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomPadding)
    }

    // MARK: - Resizing

    /// The tallest the carousel opens, though a short page opens shorter.
    private var carouselCap: CGFloat {
        let fraction = CostBreakdownBarInset.defaultCarouselFraction(
            isRegular: isRegular, isLandscape: isLandscape, keyboardVisible: keyboardVisible
        )
        return availableHeight > 0 ? availableHeight * fraction : 350
    }

    private var carouselBound: CGFloat {
        CostBreakdownBarInset.carouselUpperBound(maximum: maximumCarouselHeight, contentHeight: tallestContentHeight)
    }

    private var openingHeight: CGFloat {
        CostBreakdownBarInset.openingCarouselHeight(
            cap: carouselCap,
            maximum: maximumCarouselHeight,
            contentHeight: tallestContentHeight
        )
    }

    /// What is left of the panel's maximum once the header, grabber and page
    /// dots have taken their share, measured rather than assumed.
    private var maximumCarouselHeight: CGFloat {
        maximumHeight - headerHeight - grabberHeight - dotsHeight - Self.bottomPadding
    }

    /// The tallest size page, card and footer together, so the panel keeps one
    /// height as it pages between sizes. Sizes that are gone don't count, and
    /// the add-size page isn't a size. 0 until a page has been measured.
    private var tallestContentHeight: CGFloat {
        model.productDrafts
            .map { (contentHeights[$0.id] ?? 0) + (footerHeights[$0.id] ?? 0) }
            .max() ?? 0
    }

    private var carouselHeight: CGFloat {
        CostBreakdownBarInset.panelCarouselHeight(
            cap: carouselCap,
            extraHeight: extraHeight,
            maximum: maximumCarouselHeight,
            contentHeight: tallestContentHeight
        )
    }

    /// The room between the opening height and the upper bound. Zero where the
    /// panel can't grow.
    private var extraRoom: CGFloat {
        max(0, carouselBound - openingHeight)
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
            Image(systemName: CurrencySymbol.symbolName(forCurrencyCode: currencyCode))
                .foregroundStyle(Color.amberText)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if expanded {
                pageHeader(batch: batch)
                    .frame(minHeight: pageHeaderHeight)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cost breakdown")
                        .font(captionFont)
                        .foregroundStyle(Color.inkSoft)
                    collapsedSummary
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

    /// The batch cost in `ink` and the RRP after it in the smaller amber, on
    /// one baseline. A recipe with no ingredients keeps its single plain line.
    private var collapsedSummary: Text {
        guard model.hasIngredients else {
            return Text(model.costBarSummary(pvpFactor: pvpFactor, currencyCode: currencyCode))
                .font(headlineFont.weight(.semibold))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
        }
        let batch = Text(model.costBarBatchText(currencyCode: currencyCode))
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
        let rrp = Text(" · \(model.costBarRRPText(pvpFactor: pvpFactor, currencyCode: currencyCode))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.amberText)
        return (batch + rrp).monospacedDigit()
    }

    private func toggleExpanded(canExpand: Bool) {
        guard canExpand else { return }
        // Until a page has been measured the carousel opens at its cap and
        // shrinks to fit a frame later; animating the insertion across that
        // change leaves the panel's content drawn below its surface.
        let animation: Animation? = tallestContentHeight > 0 || isExpanded ? .easeInOut(duration: 0.25) : nil
        withAnimation(animation) { isExpanded.toggle() }
    }

    @ViewBuilder
    private func pageHeader(batch: ProductCostBreakdown) -> some View {
        switch model.costBarPage(for: visibleCardID) {
        case .addSize:
            Text("New size")
                .font(.body.weight(.semibold))
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
        ScrollViewReader { proxy in
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
            .frame(height: carouselHeight)
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeights[draft.id] = $0
                    }
            }
            if breakdown.total > 0 {
                productTotals(breakdown)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        footerHeights[draft.id] = $0
                    }
                    .onDisappear { footerHeights[draft.id] = nil }
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
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
            HStack {
                Text("RRP")
                Spacer()
                Text((breakdown.total * pvpFactor).formatted(.currency(code: currencyCode)))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.amberText)
        }
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
