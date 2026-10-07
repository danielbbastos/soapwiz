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
           let nearest = expiries.filter({ $0 > now }).min(),
           let stamp = expiry(nearest, now: now, calendar: calendar) {
            result.append(stamp)
        }

        return Array(result.prefix(2))
    }

    /// The stamp an expiry date earns on its own: Expired once it has passed,
    /// Expires in N d within a month of it, and nothing further out.
    static func expiry(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> IngredientStockStamp? {
        if date < now {
            return .expired
        }
        guard let cutoff = calendar.date(byAdding: .month, value: 1, to: now), date <= cutoff else {
            return nil
        }
        return .expiresIn(days: daysUntil(date, from: now, calendar: calendar))
    }

    static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}
