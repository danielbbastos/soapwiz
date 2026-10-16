import SwiftUI

struct ProBenefit: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = .amberText
    var titleColor: Color = .ink

    var id: String { title }

    static let paid: [ProBenefit] = [
        ProBenefit(
            symbol: "book.closed",
            title: "Unlimited recipes and ingredients",
            detail: "Free keeps \(FreeTierLimits.recipeCap) recipes and "
                + "\(FreeTierLimits.customIngredientCap) custom ingredients. "
                + "The 230+ library ingredients are always free."
        ),
        ProBenefit(
            symbol: "icloud",
            title: "iCloud sync",
            detail: "Inventory, recipes and batches on every iPhone and iPad you use."
        ),
        ProBenefit(
            symbol: "folder",
            title: "Collections",
            detail: "Group recipes your own way."
        ),
        ProBenefit(
            symbol: "bell",
            title: "Reminders",
            detail: "Before an ingredient expires, and when a batch has cured."
        ),
        ProBenefit(
            symbol: "gift",
            title: "Future Pro features",
            detail: "Pro features added in later updates are included."
        )
    ]

    static let alwaysFreeNote = "Batches, inventory, calculations, recipe import, sharing and backups"

    static let alwaysFree = ProBenefit(
        symbol: "checkmark",
        title: "Always free",
        detail: alwaysFreeNote + ".",
        tint: .success
    )
}

/// An icon beside a title and its description.
struct ProBenefitRow: View {
    let benefit: ProBenefit

    static let iconWidth: CGFloat = 28
    static let spacing: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            Image(systemName: benefit.symbol)
                .font(.title3)
                .foregroundStyle(benefit.tint)
                .frame(width: Self.iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.headline)
                    .foregroundStyle(benefit.titleColor)
                Text(benefit.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact width: one raised sheet, the benefits as rows.
struct ProBenefitsList: View {
    let benefits: [ProBenefit]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                if index > 0 {
                    Rectangle()
                        .fill(Color.rule)
                        .frame(height: 1)
                        .padding(.leading, 16 + ProBenefitRow.iconWidth + ProBenefitRow.spacing)
                }
                ProBenefitRow(benefit: benefit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .ledgerSheet()
    }
}

/// Regular width: a card per benefit, two to a row.
struct ProBenefitsGrid: View {
    let benefits: [ProBenefit]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: benefits.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(benefits[start..<min(start + 2, benefits.count)]) { benefit in
                        ProBenefitCard(benefit: benefit)
                    }
                }
            }
        }
    }
}

struct ProBenefitCard: View {
    let benefit: ProBenefit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: benefit.symbol)
                    .font(.title3)
                    .foregroundStyle(benefit.tint)
                    .accessibilityHidden(true)
                Text(benefit.title)
                    .font(.headline)
                    .foregroundStyle(benefit.titleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(benefit.detail)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ledgerSheet()
    }
}
