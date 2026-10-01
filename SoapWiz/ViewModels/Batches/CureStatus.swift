import Foundation

/// How long a cure has left, in the unit it reads best in: days up to two
/// months out, weeks beyond — "26 weeks left" rather than "182 days left".
enum CureRemaining: Equatable {
    case days(Int)
    /// Rounded up, so a part week still counts and the last one never reads
    /// as zero.
    case weeks(Int)

    init(daysLeft: Int, readyDate: Date, now: Date, calendar: Calendar) {
        guard let twoMonthsOut = calendar.date(byAdding: .month, value: 2, to: calendar.startOfDay(for: now)),
              readyDate > twoMonthsOut
        else {
            self = .days(daysLeft)
            return
        }
        self = .weeks((daysLeft + 6) / 7)
    }
}

/// Where a batch is in its cure, counted in calendar days: a batch made on the
/// 1st with a 7-day cure is ready on the 8th, whatever the hour it was made.
enum CureStatus: Equatable {
    /// The batch doesn't cure.
    case none
    /// `progress` runs from 0 on the day the batch was made towards 1.
    case curing(remaining: CureRemaining, progress: Double)
    case ready

    init(dateCreated: Date, cureDays: Int, now: Date = .now, calendar: Calendar = .current) {
        guard cureDays > 0,
              let readyDay = Self.readyDate(dateCreated: dateCreated, cureDays: cureDays, calendar: calendar),
              let daysLeft = calendar.dateComponents(
                  [.day], from: calendar.startOfDay(for: now), to: readyDay
              ).day
        else {
            self = .none
            return
        }
        guard daysLeft > 0 else {
            self = .ready
            return
        }
        let elapsed = cureDays - daysLeft
        self = .curing(
            remaining: CureRemaining(daysLeft: daysLeft, readyDate: readyDay, now: now, calendar: calendar),
            progress: min(1, max(0, Double(elapsed) / Double(cureDays)))
        )
    }

    /// The start of the day the cure ends, or `nil` for a batch that doesn't
    /// cure.
    static func readyDate(dateCreated: Date, cureDays: Int, calendar: Calendar = .current) -> Date? {
        guard cureDays > 0 else { return nil }
        return calendar.date(byAdding: .day, value: cureDays, to: calendar.startOfDay(for: dateCreated))
    }

    /// The start of the day the bars reach the band's shortest recommended
    /// cure and can be used. `nil` without a band, or when the batch's own
    /// cure is no longer than that — the ready date then says it all.
    static func usableDate(
        dateCreated: Date,
        cureDays: Int,
        band: CureBand?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let band, band.usableDays < cureDays else { return nil }
        return readyDate(dateCreated: dateCreated, cureDays: band.usableDays, calendar: calendar)
    }
}

/// The cure lengths the steppers offer, a week at a time. The longest
/// suggestion, castile's six months, sits well inside.
enum BatchCureLimits {
    static let days = 7...364
}

extension Batch {
    var cureStatus: CureStatus {
        CureStatus(dateCreated: dateCreated, cureDays: cureDays)
    }

    var cureReadyDate: Date? {
        CureStatus.readyDate(dateCreated: dateCreated, cureDays: cureDays)
    }

    var cureUsableDate: Date? {
        CureStatus.usableDate(dateCreated: dateCreated, cureDays: cureDays, band: CureBand.resolve(cureBand))
    }
}
