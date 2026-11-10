import Foundation

/// One Monday-to-Sunday week of the batch heatmap and the batches made in it.
struct HeatmapWeek: Identifiable, Equatable {
    /// The Monday the week starts on.
    let start: Date
    /// The Sunday the week ends on.
    let end: Date
    let count: Int
    /// The row of the phone grid: the Monday's ordinal in its month, from 0.
    let row: Int
    /// "Nov 10–16" or "Nov 24 – Dec 7". The year is added when either end is
    /// not in the current year: "Dec 29, 2025 – Jan 4, 2026".
    let rangeText: String

    var id: Date { start }
}

/// Formats a week's range. Its styles are built once for the whole heatmap.
private struct HeatmapRangeFormatter {
    private let calendar: Calendar
    private let nowYear: Int
    private let monthDay: Date.FormatStyle
    private let dayOnly: Date.FormatStyle
    private let yearOnly: Date.FormatStyle
    private let monthDayYear: Date.FormatStyle

    init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        nowYear = calendar.component(.year, from: now)
        let locale = calendar.locale ?? .current
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        monthDay = base.month(.abbreviated).day()
        dayOnly = base.day()
        yearOnly = base.year()
        monthDayYear = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }

    func text(start: Date, end: Date) -> String {
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let showsYear = startYear != nowYear || endYear != nowYear
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
            && startYear == endYear
        if sameMonth {
            let range = "\(start.formatted(monthDay))–\(end.formatted(dayOnly))"
            return showsYear ? "\(range), \(start.formatted(yearOnly))" : range
        }
        let format = showsYear ? monthDayYear : monthDay
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }
}

/// A month's column of the phone grid: the weeks whose Monday falls in it,
/// each in the row of its Monday's ordinal, so a partial month leaves gaps.
struct HeatmapMonth: Identifiable, Equatable {
    let monthStart: Date
    let initial: String
    let weeks: [HeatmapWeek]

    var id: Date { monthStart }
}

/// How many batches were made in each of the last 52 weeks, the current one
/// included. Computed from the batch dates, never stored.
struct BatchHeatmap {
    static let weekCount = 52
    static let stripRowLength = 26

    let weeks: [HeatmapWeek]
    let months: [HeatmapMonth]
    let strip: [[HeatmapWeek]]
    let total: Int
    let rowCount: Int

    init(dates: [Date], now: Date = .now, calendar: Calendar = .current) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        iso.locale = calendar.locale
        let formatter = HeatmapRangeFormatter(calendar: Self.displayCalendar(for: calendar), now: now)

        let starts = Self.weekStarts(now: now, calendar: iso)
        var counts = [Int](repeating: 0, count: starts.count)
        if let first = starts.first, let last = starts.last,
           let windowEnd = iso.date(byAdding: .weekOfYear, value: 1, to: last) {
            for date in dates where date >= first && date < windowEnd {
                if let index = starts.lastIndex(where: { $0 <= date }) {
                    counts[index] += 1
                }
            }
        }

        let weeks = starts.enumerated().map { index, start in
            let end = iso.date(byAdding: .day, value: 6, to: start) ?? start
            return HeatmapWeek(
                start: start,
                end: end,
                count: counts[index],
                row: max(iso.component(.weekdayOrdinal, from: start) - 1, 0),
                rangeText: formatter.text(start: start, end: end)
            )
        }
        self.weeks = weeks
        total = counts.reduce(0, +)
        strip = stride(from: 0, to: weeks.count, by: Self.stripRowLength).map {
            Array(weeks[$0..<min($0 + Self.stripRowLength, weeks.count)])
        }

        months = Self.months(of: weeks, calendar: iso)
        rowCount = (weeks.map(\.row).max() ?? -1) + 1
    }

    init(batches: [Batch], now: Date = .now, calendar: Calendar = .current) {
        self.init(dates: batches.map(\.dateCreated), now: now, calendar: calendar)
    }

    /// 0 for none, 1 and 2 as they are, 3 for three or more.
    static func level(for count: Int) -> Int {
        min(max(count, 0), 3)
    }

    private static func months(of weeks: [HeatmapWeek], calendar: Calendar) -> [HeatmapMonth] {
        var months: [HeatmapMonth] = []
        var currentKey: DateComponents?
        for week in weeks {
            let key = calendar.dateComponents([.year, .month], from: week.start)
            if key == currentKey, let last = months.last {
                months[months.count - 1] = HeatmapMonth(
                    monthStart: last.monthStart,
                    initial: last.initial,
                    weeks: last.weeks + [week]
                )
            } else {
                let symbols = calendar.veryShortMonthSymbols
                let index = (key.month ?? 1) - 1
                months.append(HeatmapMonth(
                    monthStart: calendar.date(from: key) ?? week.start,
                    initial: symbols.indices.contains(index) ? symbols[index] : "",
                    weeks: [week]
                ))
                currentKey = key
            }
        }
        return months
    }

    private static func displayCalendar(for calendar: Calendar) -> Calendar {
        guard calendar.identifier == .iso8601 else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = calendar.locale
        return gregorian
    }

    private static func weekStarts(now: Date, calendar: Calendar) -> [Date] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let first = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: current)
        else { return [] }
        return (0..<weekCount).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: first)
        }
    }
}
