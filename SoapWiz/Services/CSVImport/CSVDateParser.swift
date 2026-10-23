import Foundation

/// Reads a column of dates from a CSV file without guessing.
///
/// Understood: `yyyy-MM-dd` and `yyyy/MM/dd` (a time after a space or "T" is
/// ignored), numeric day, month and year with "/", "-" or "." and a 4- or
/// 2-digit year (2-digit years are 20yy), and English month names as in
/// "15 Mar 2024", "15 March 2024", "Mar 15, 2024" and "March 15 2024".
///
/// "05/03/2024" is 5 March in one country and 3 May in another, so the order
/// is decided by the column: a first number above 12 means day-first, a second
/// number above 12 means month-first, and when the column shows both or
/// neither it follows the locale. A column where every value is a whole number
/// from 20000 to 80000 is a spreadsheet's day count and is read as days since
/// 1899-12-30.
///
/// Values come back at the start of their day in the calendar's time zone. A
/// date that doesn't exist (31/02/2024) or isn't in a known format is nil. The
/// calendar is expected to be Gregorian.
nonisolated enum CSVDateParser {
    private static let excelSerials = 20000...80000
    private static let monthNames = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]

    static func dates(in cells: [String], locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) -> [Date?] {
        let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmpty = trimmed.filter { !$0.isEmpty }
        if !nonEmpty.isEmpty, nonEmpty.allSatisfy({ Int($0).map(excelSerials.contains) ?? false }) {
            return trimmed.map { Int($0).flatMap { excelDate(serial: $0, calendar: calendar) } }
        }

        let readings = trimmed.map { reading(of: $0) }
        let isDayFirst = isDayFirst(in: readings, locale: locale)
        return readings.map { reading in
            switch reading {
            case .fixed(let year, let month, let day): date(year: year, month: month, day: day, calendar: calendar)
            case .numeric(let first, let second, let year):
                date(
                    year: year,
                    month: isDayFirst ? second : first,
                    day: isDayFirst ? first : second,
                    calendar: calendar
                )
            case .unreadable: nil
            }
        }
    }

    private static func isDayFirst(in readings: [CSVDateReading], locale: Locale) -> Bool {
        var hasDayFirstEvidence = false
        var hasMonthFirstEvidence = false
        for case .numeric(let first, let second, _) in readings {
            hasDayFirstEvidence = hasDayFirstEvidence || first > 12
            hasMonthFirstEvidence = hasMonthFirstEvidence || second > 12
        }
        if hasDayFirstEvidence != hasMonthFirstEvidence { return hasDayFirstEvidence }

        let format = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? ""
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return true }
        return day < month
    }

    private static func reading(of text: String) -> CSVDateReading {
        let head = text.split(maxSplits: 1, whereSeparator: { $0 == "T" || $0 == " " }).first.map(String.init) ?? text
        if let numbers = numericParts(head) {
            if numbers.digitCounts[0] == 4, numbers.digitCounts[1...].allSatisfy({ $0 <= 2 }) {
                return .fixed(year: numbers.values[0], month: numbers.values[1], day: numbers.values[2])
            }
            if numbers.digitCounts[0] <= 2, numbers.digitCounts[1] <= 2, [2, 4].contains(numbers.digitCounts[2]) {
                let year = numbers.digitCounts[2] == 2 ? 2000 + numbers.values[2] : numbers.values[2]
                return .numeric(first: numbers.values[0], second: numbers.values[1], year: year)
            }
            return .unreadable
        }
        return namedReading(of: text)
    }

    /// The three numbers of a date written with one kind of separator.
    private static func numericParts(_ text: String) -> (values: [Int], digitCounts: [Int])? {
        guard let separator = text.first(where: { "/-.".contains($0) }) else { return nil }
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        return (parts.compactMap { Int($0) }, parts.map(\.count))
    }

    private static func namedReading(of text: String) -> CSVDateReading {
        let tokens = text.split(whereSeparator: { " ,.-/".contains($0) })
        guard tokens.count == 3 else { return .unreadable }
        let isNumber = tokens.map { $0.allSatisfy { $0.isASCII && $0.isNumber } }
        if isNumber == [true, false, true], tokens[0].count <= 2, tokens[2].count == 4,
           let day = Int(tokens[0]), let month = monthNumber(tokens[1]), let year = Int(tokens[2]) {
            return .fixed(year: year, month: month, day: day)
        }
        if isNumber == [false, true, true], tokens[1].count <= 2, tokens[2].count == 4,
           let month = monthNumber(tokens[0]), let day = Int(tokens[1]), let year = Int(tokens[2]) {
            return .fixed(year: year, month: month, day: day)
        }
        return .unreadable
    }

    /// The month a full or abbreviated English name stands for.
    private static func monthNumber(_ name: Substring) -> Int? {
        let lowered = name.lowercased()
        guard lowered.count >= 3 else { return nil }
        let index = monthNames.firstIndex { $0 == lowered || $0.prefix(3) == lowered || (lowered == "sept" && $0 == "september") }
        return index.map { $0 + 1 }
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func excelDate(serial: Int, calendar: Calendar) -> Date? {
        guard let epoch = date(year: 1899, month: 12, day: 30, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: serial, to: epoch)
    }
}

/// What one CSV cell says about its date before the column decides the order.
private nonisolated enum CSVDateReading {
    case fixed(year: Int, month: Int, day: Int)
    case numeric(first: Int, second: Int, year: Int)
    case unreadable
}
