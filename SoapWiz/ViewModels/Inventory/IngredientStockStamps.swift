import Foundation

/// One status mark on an inventory row.
enum IngredientStockStamp: Equatable {
    case out
    case expired
    case low
    case expiresIn(days: Int)

    var word: String {
        switch self {
        case .out: String(localized: "Out")
        case .expired: String(localized: "Expired")
        case .low: String(localized: "Low")
        case .expiresIn(let days):
            if days == 0 {
                String(localized: "Expires today")
            } else {
                String(localized: "Expires in \(days) d")
            }
        }
    }

    var tone: StatusStampTone {
        switch self {
        case .out, .expired: .danger
        case .low, .expiresIn: .warning
        }
    }

    var glyph: String {
        switch self {
        case .out, .low: "exclamationmark.triangle"
        case .expired, .expiresIn: "clock.arrow.circlepath"
        }
    }

    /// The stamps a row carries, most urgent first and at most two.
    ///
    /// An ingredient with no purchases gets none: the library installs a couple
    /// of hundred ingredients the user has never bought, and they must not all
    /// read as out of stock. Out replaces Low, since it is the stronger form of it.
    static func stamps(
        for ingredient: Ingredient,
        tracksInventory: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [IngredientStockStamp] {
        guard tracksInventory, !ingredient.purchases.isEmpty else { return [] }

        var result: [IngredientStockStamp] = []
        let remaining = ingredient.totalRemaining
        let isOut = remaining <= 0
        if isOut {
            result.append(.out)
        }

        let expiries = ingredient.purchases.compactMap(\.expiryDate)
        if expiries.contains(where: { $0 < now }) {
            result.append(.expired)
        }

        if !isOut, let threshold = ingredient.lowStockThreshold, remaining <= threshold {
            result.append(.low)
        }

        if !result.contains(.expired),
           let cutoff = calendar.date(byAdding: .month, value: 1, to: now),
           let nearest = expiries.filter({ $0 > now && $0 <= cutoff }).min() {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: nearest)
            ).day ?? 0
            result.append(.expiresIn(days: days))
        }

        return Array(result.prefix(2))
    }
}
