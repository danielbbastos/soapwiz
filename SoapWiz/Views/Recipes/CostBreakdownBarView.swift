import SwiftUI

struct CostBreakdownBarView: View {
    @Bindable var model: RecipeFormViewModel
    @Binding var isExpanded: Bool

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        return f
    }()

    var body: some View {
        let cornerRadius: CGFloat = isExpanded ? 28 : 22
        GlassEffectContainerIOS26(spacing: 16) {
            VStack(spacing: 0) {
                collapsedBar

                if isExpanded {
                    Divider().opacity(0.4)
                    carousel
                        .frame(height: 320)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .glassEffectInteractiveIOS26(in: .rect(cornerRadius: cornerRadius))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var collapsedBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cost breakdown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summaryText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var carousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach($model.productDrafts) { $draft in
                        let result = model.breakdownAndCost(for: draft)
                        RecipeProductCardView(
                            draft: $draft,
                            breakdown: result.breakdown,
                            totalCost: result.total,
                            availableUnits: IngredientUnit.allCases
                        )
                        .containerRelativeFrame(.horizontal)
                        .id(draft.id)
                    }
                    AddProductCardView {
                        model.addProduct(defaultUnitSymbol: IngredientUnit.grams.rawValue)
                        if let newID = model.productDrafts.last?.id {
                            withAnimation { proxy.scrollTo(newID) }
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id("addButton")
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
        }
    }

    private var summaryText: String {
        guard let firstDraft = model.productDrafts.first else {
            return "No products yet — tap to expand"
        }
        let total = model.breakdownAndCost(for: firstDraft).total
        let totalText = Self.currencyFormatter.string(from: NSNumber(value: total)) ?? "—"
        if model.productDrafts.count > 1 {
            return "\(totalText) · \(model.productDrafts.count) products"
        }
        return totalText
    }
}
