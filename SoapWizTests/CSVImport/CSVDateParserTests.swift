import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVDateParserTests {
    private let us = Locale(identifier: "en_US")
    private let portuguese = Locale(identifier: "pt_PT")
    private let calendar = makeCalendar(timeZone: "GMT")

    private static func makeCalendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func parse(_ cells: [String], locale: Locale) -> [Date?] {
        CSVDateParser.dates(in: cells, locale: locale, calendar: calendar)
    }

    @Test(arguments: [
        ("2024-03-15", 2024, 3, 15),
        ("2024/03/15", 2024, 3, 15),
        ("2024-3-5", 2024, 3, 5),
        ("2024-03-15T10:30:00Z", 2024, 3, 15),
        ("2024-03-15 10:30", 2024, 3, 15),
        ("15/03/2024", 2024, 3, 15),
        ("15-03-2024", 2024, 3, 15),
        ("15.03.2024", 2024, 3, 15),
        ("15/03/24", 2024, 3, 15),
        ("15/03/2024 14:30", 2024, 3, 15),
        ("15 Mar 2024", 2024, 3, 15),
        ("15 March 2024", 2024, 3, 15),
        ("15-Mar-2024", 2024, 3, 15),
        ("Mar 15, 2024", 2024, 3, 15),
        ("March 15 2024", 2024, 3, 15),
        ("MARCH 15, 2024", 2024, 3, 15),
        ("5 sept 2024", 2024, 9, 5),
        ("Sept 5, 2024", 2024, 9, 5),
        ("Sep. 5, 2024", 2024, 9, 5),
        ("1 January 2024", 2024, 1, 1),
        ("31 Dec 2023", 2023, 12, 31)
    ])
    func dates_SupportedFormat_ParsesToStartOfDay(text: String, year: Int, month: Int, day: Int) throws {
        #expect(parse([text], locale: us) == [try date(year, month, day)])
    }

    @Test(arguments: ["", "   ", "hello", "2024-13-01", "15/13/2024", "Foo 15, 2024", "15 Mar", "Mar 2024", "2024-03", "15/03/202", "99999-01-01"])
    func dates_EmptyOrUnreadable_ReturnsNil(text: String) {
        #expect(parse([text], locale: us) == [nil])
    }

    @Test func dates_PreservesCountAndOrder() throws {
        let result = parse(["2024-01-02", "", "nope", "2024-03-04"], locale: us)
        #expect(result == [try date(2024, 1, 2), nil, nil, try date(2024, 3, 4)])
    }

    @Test func dates_EmptyInput_ReturnsEmpty() {
        #expect(parse([], locale: us).isEmpty)
    }

    @Test(arguments: ["31/02/2024", "2024-02-30", "30 Feb 2024", "29/02/2023", "31/04/2024"])
    func dates_NonexistentDay_ReturnsNil(text: String) {
        #expect(parse([text], locale: us) == [nil])
    }

    @Test func dates_LeapDay_IsValid() throws {
        #expect(parse(["29/02/2024"], locale: us) == [try date(2024, 2, 29)])
    }

    @Test func dates_TwoDigitYear_Means2000s() throws {
        #expect(parse(["5/3/24"], locale: portuguese) == [try date(2024, 3, 5)])
        #expect(parse(["5/3/99"], locale: portuguese) == [try date(2099, 3, 5)])
    }

    @Test func dates_FirstNumberAbove12_InfersDayFirstEvenInUSLocale() throws {
        let result = parse(["05/03/2024", "25/03/2024"], locale: us)
        #expect(result == [try date(2024, 3, 5), try date(2024, 3, 25)])
    }

    @Test func dates_SecondNumberAbove12_InfersMonthFirstEvenInPortugueseLocale() throws {
        let result = parse(["05/03/2024", "03/25/2024"], locale: portuguese)
        #expect(result == [try date(2024, 5, 3), try date(2024, 3, 25)])
    }

    @Test func dates_AmbiguousColumn_FallsBackToUSLocaleOrder() throws {
        #expect(parse(["05/03/2024", "01/02/2024"], locale: us) == [try date(2024, 5, 3), try date(2024, 1, 2)])
    }

    @Test func dates_AmbiguousColumn_FallsBackToPortugueseLocaleOrder() throws {
        #expect(parse(["05/03/2024", "01/02/2024"], locale: portuguese) == [try date(2024, 3, 5), try date(2024, 2, 1)])
    }

    @Test func dates_ColumnShowingBothOrders_FallsBackToLocaleAndRejectsImpossibleOnes() throws {
        let cells = ["13/01/2024", "01/13/2024"]
        #expect(parse(cells, locale: us) == [nil, try date(2024, 1, 13)])
        #expect(parse(cells, locale: portuguese) == [try date(2024, 1, 13), nil])
    }

    @Test func dates_NamedAndISOCells_DoNotAffectNumericOrder() throws {
        let cells = ["2024-12-01", "15 Mar 2024", "05/03/2024"]
        #expect(parse(cells, locale: portuguese) == [try date(2024, 12, 1), try date(2024, 3, 15), try date(2024, 3, 5)])
    }

    @Test func dates_ExcelSerials_CountDaysFrom1899_12_30() throws {
        let result = parse(["45000", "45292", ""], locale: us)
        #expect(result == [try date(2023, 3, 15), try date(2024, 1, 1), nil])
    }

    @Test func dates_SerialBoundaries_AreInclusive() {
        #expect(parse(["20000", "80000"], locale: us).allSatisfy { $0 != nil })
        #expect(parse(["19999"], locale: us) == [nil])
        #expect(parse(["80001"], locale: us) == [nil])
    }

    @Test func dates_SerialsMixedWithOtherText_AreNotSerials() throws {
        #expect(parse(["45000", "2024-01-05"], locale: us) == [nil, try date(2024, 1, 5)])
    }

    @Test func dates_DecimalNumber_IsNotASerial() {
        #expect(parse(["45000.5"], locale: us) == [nil])
    }

    @Test func dates_OtherTimeZone_ReturnsStartOfDayInThatZone() throws {
        let newYork = Self.makeCalendar(timeZone: "America/New_York")
        let result = CSVDateParser.dates(in: ["2024-03-15"], locale: us, calendar: newYork)
        let parsed = try #require(result[0])
        #expect(parsed == newYork.startOfDay(for: parsed))
        let components = newYork.dateComponents([.year, .month, .day, .hour], from: parsed)
        #expect(components.year == 2024 && components.month == 3 && components.day == 15 && components.hour == 0)
    }
}
