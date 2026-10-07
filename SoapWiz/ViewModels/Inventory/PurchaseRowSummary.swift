import Foundation

/// A stamp on a purchase row: a stock warning, or the purchase's own badge.
enum PurchaseRowStamp: Equatable {
    case stock(IngredientStockStamp)
    case badge(String)

    var word: String {
        switch self {
        case .stock(let stamp): stamp.word
        case .badge(let text): text
        }
    }

    var tone: StatusStampTone {
        switch self {
        case .stock(let stamp): stamp.tone
        case .badge: .neutral
        }
    }

    var glyph: String? {
        switch self {
        case .stock(let stamp): stamp.glyph
        case .badge: nil
        }
    }
}

/// What a purchase row says about the purchase's state: the status after the
/// date on its second line, and the stamps on its third.
struct PurchaseRowSummary: Equatable {
    enum Status: Equatable {
        case none
        case usedUp
        case expires(Date)
        case expired
    }

    let status: Status
    let stamps: [PurchaseRowStamp]

    init(
        expiryDate: Date?,
        remainingAmount: Double,
        badge: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let hasStock = remainingAmount > 0
        var status = Status.none
        var stamps: [PurchaseRowStamp] = []

        if !hasStock {
            status = .usedUp
        } else if let expiryDate {
            if expiryDate < now {
                status = .expired
                stamps.append(.stock(.expired))
            } else {
                status = .expires(expiryDate)
                if let cutoff = calendar.date(byAdding: .month, value: 1, to: now), expiryDate <= cutoff {
                    let days = IngredientStockStamp.daysUntil(expiryDate, from: now, calendar: calendar)
                    stamps.append(.stock(.expiresIn(days: days)))
                }
            }
        }

        if !badge.isEmpty {
            stamps.append(.badge(badge))
        }

        self.status = status
        self.stamps = Array(stamps.prefix(2))
    }
}
