import Foundation

enum ExpiryThreshold: String, CaseIterable {
    case oneMonth = "1month"
    case oneWeek = "1week"

    func fireDate(before expiryDate: Date, calendar: Calendar) -> Date? {
        switch self {
        case .oneMonth:
            calendar.date(byAdding: .month, value: -1, to: expiryDate)
        case .oneWeek:
            calendar.date(byAdding: .day, value: -7, to: expiryDate)
        }
    }

    func notificationContent(ingredientNames: [String]) -> (title: String, body: String) {
        let window = switch self {
        case .oneMonth: "a month"
        case .oneWeek: "a week"
        }

        if ingredientNames.count == 1 {
            return (
                title: "Ingredient Expiring Soon",
                body: "\(ingredientNames[0]) expires within \(window)."
            )
        } else {
            let list = ingredientNames.joined(separator: ", ")
            return (
                title: "\(ingredientNames.count) Ingredients Expiring Soon",
                body: "\(list) expire within \(window)."
            )
        }
    }
}

struct PurchaseSnapshot {
    let ingredientName: String
    let expiryDate: Date
    let remainingAmount: Double
}

struct ExpiryNotificationRequest: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

enum ExpiryNotificationScheduler {
    static let notificationPrefix = "expiry-"

    static func computeRequests(
        purchases: [PurchaseSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ExpiryNotificationRequest] {
        let eligible = purchases.filter { $0.remainingAmount > 0 && $0.expiryDate > now }

        var requests: [ExpiryNotificationRequest] = []

        for threshold in ExpiryThreshold.allCases {
            var groups: [String: [String]] = [:]

            for purchase in eligible {
                guard let rawFireDate = threshold.fireDate(before: purchase.expiryDate, calendar: calendar),
                      let normalizedFireDate = normalizedToMorning(rawFireDate, calendar: calendar),
                      normalizedFireDate > now else { continue }

                let key = dayKey(from: rawFireDate, calendar: calendar)
                groups[key, default: []].append(purchase.ingredientName)
            }

            for (key, names) in groups {
                let identifier = "\(notificationPrefix)\(threshold.rawValue)-\(key)"
                let sortedNames = names.sorted()
                let (title, body) = threshold.notificationContent(ingredientNames: sortedNames)

                guard let fireDate = date(fromDayKey: key, hour: 9, calendar: calendar) else { continue }

                requests.append(ExpiryNotificationRequest(
                    identifier: identifier,
                    fireDate: fireDate,
                    title: title,
                    body: body
                ))
            }
        }

        return requests.sorted { $0.fireDate < $1.fireDate }
    }

    private static func normalizedToMorning(_ date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func date(fromDayKey key: String, hour: Int, calendar: Calendar) -> Date? {
        guard key.count == 8,
              let year = Int(key.prefix(4)),
              let month = Int(key.dropFirst(4).prefix(2)),
              let day = Int(key.dropFirst(6).prefix(2)) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components)
    }
}
