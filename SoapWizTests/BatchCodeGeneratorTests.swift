import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The shape of a batch code and the rules for handing out the next one
/// (SW-175): `<prefix>-<yyMMdd>-<sequence>`.
@Suite("Batch code generator")
@MainActor
struct BatchCodeGeneratorTests {

    private let utc: TimeZone

    init() throws {
        utc = try #require(TimeZone(identifier: "UTC"))
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in timeZone: TimeZone? = nil
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? utc
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    // MARK: - Prefix

    @Test func prefix_SingleWord_TakesFirstThreeLetters() {
        #expect(BatchCodeGenerator.prefix(for: "Lavender") == "LAV")
    }

    @Test func prefix_TwoWords_ExtendsInitialsToThree() {
        #expect(BatchCodeGenerator.prefix(for: "Lavender Oatmeal") == "LOA")
    }

    @Test func prefix_ManyWords_StopsAtThreeInitials() {
        #expect(BatchCodeGenerator.prefix(for: "Goat Milk And Honey Soap") == "GMA")
    }

    @Test func prefix_Diacritics_AreFolded() {
        #expect(BatchCodeGenerator.prefix(for: "Açaí") == "ACA")
    }

    @Test func prefix_Punctuation_IsDropped() {
        #expect(BatchCodeGenerator.prefix(for: "Salt-Bar") == "SAL")
        #expect(BatchCodeGenerator.prefix(for: "Mum's Soap") == "MSO")
    }

    @Test func prefix_ShortName_UsesWhatThereIs() {
        #expect(BatchCodeGenerator.prefix(for: "Oz") == "OZ")
    }

    @Test func prefix_LowercaseName_IsUppercased() {
        #expect(BatchCodeGenerator.prefix(for: "castile") == "CAS")
    }

    @Test(arguments: ["", "   ", "—!?", "🧼"])
    func prefix_NothingToAbbreviate_FallsBack(name: String) {
        #expect(BatchCodeGenerator.prefix(for: name) == BatchCodeGenerator.fallbackPrefix)
    }

    // MARK: - Date stamp

    @Test func dateStamp_PadsMonthAndDay() throws {
        #expect(BatchCodeGenerator.dateStamp(for: try date(2026, 9, 4), timeZone: utc) == "260904")
    }

    @Test func dateStamp_YearBelowTen_IsPadded() throws {
        #expect(BatchCodeGenerator.dateStamp(for: try date(2005, 12, 31), timeZone: utc) == "051231")
    }

    /// The day is the one the maker saw on the wall, not the day in UTC.
    @Test func dateStamp_LateEvening_FollowsTheGivenTimeZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let lateInUTC = try date(2026, 9, 30, hour: 23)

        #expect(BatchCodeGenerator.dateStamp(for: lateInUTC, timeZone: utc) == "260930")
        #expect(BatchCodeGenerator.dateStamp(for: lateInUTC, timeZone: tokyo) == "261001")
    }

    // MARK: - Suggested code

    @Test func suggestedCode_NoExistingCodes_StartsAtOne() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30), existingCodes: [String](), timeZone: utc
        )

        #expect(code == "LAV-260930-01")
    }

    @Test func suggestedCode_SameRecipeSameDay_TakesNextSequence() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260930-01", "LAV-260930-02"], timeZone: utc
        )

        #expect(code == "LAV-260930-03")
    }

    @Test func suggestedCode_OtherDayOrRecipe_DoesNotAdvanceSequence() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260929-04", "ROS-260930-07"], timeZone: utc
        )

        #expect(code == "LAV-260930-01")
    }

    /// A number that was once on a label is never handed to another batch.
    @Test func suggestedCode_GapInSequence_IsNotRefilled() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260930-01", "LAV-260930-05"], timeZone: utc
        )

        #expect(code == "LAV-260930-06")
    }

    @Test func suggestedCode_PastNinetyNine_WidensToThreeDigits() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260930-99"], timeZone: utc
        )

        #expect(code == "LAV-260930-100")
    }

    @Test func suggestedCode_ExistingCodeInLowercaseWithSpaces_StillCounts() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["  lav-260930-01 "], timeZone: utc
        )

        #expect(code == "LAV-260930-02")
    }

    @Test func suggestedCode_HandTypedCodesUnderTheStem_AreSkipped() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260930-A", "LAV-260930-", "LAV-260930", "2026/14"], timeZone: utc
        )

        #expect(code == "LAV-260930-01")
    }

    // MARK: - Sequence

    @Test func sequence_CodeUnderStem_ReturnsItsNumber() {
        #expect(BatchCodeGenerator.sequence(of: "LAV-260930-07", in: "LAV-260930") == 7)
    }

    @Test func sequence_CodeUnderLongerStem_ReturnsNil() {
        #expect(BatchCodeGenerator.sequence(of: "LAVX-260930-07", in: "LAV-260930") == nil)
    }

    @Test func sequence_NineDigits_IsStillASequence() {
        #expect(BatchCodeGenerator.sequence(of: "LAV-260930-123456789", in: "LAV-260930") == 123_456_789)
    }

    @Test(arguments: ["LAV-260930-1234567890", "LAV-260930-\(Int.max)", "LAV-260930-99999999999999999999999"])
    func sequence_TailTooLongToBeCountedTo_ReturnsNil(code: String) {
        #expect(BatchCodeGenerator.sequence(of: code, in: "LAV-260930") == nil)
    }

    /// Counting on from the largest integer would overflow and crash.
    @Test func suggestedCode_ExistingCodeEndsInLargestInteger_IgnoresItInsteadOfOverflowing() throws {
        let code = BatchCodeGenerator.suggestedCode(
            recipeName: "Lavender", date: try date(2026, 9, 30),
            existingCodes: ["LAV-260930-\(Int.max)", "LAV-260930-02"], timeZone: utc
        )

        #expect(code == "LAV-260930-03")
    }

    // MARK: - Generated stem

    @Test func generatedStem_GeneratedCode_ReturnsStem() {
        #expect(BatchCodeGenerator.generatedStem(of: "LAV-260930-01") == "LAV-260930")
        #expect(BatchCodeGenerator.generatedStem(of: " lav-260930-112 ") == "LAV-260930")
    }

    @Test(arguments: ["", "2026/14", "LAV-01", "LAV-2609-01", "LAV-260930-1", "LAV-260930-0A", "-260930-01", "260930-01"])
    func generatedStem_AnyOtherShape_ReturnsNil(code: String) {
        #expect(BatchCodeGenerator.generatedStem(of: code) == nil)
    }

    // MARK: - Duplicates

    @Test func isTaken_AnotherBatchHasTheCode_ReturnsTrue() {
        let other = Batch(recipe: nil, code: "LAV-260930-01", recipeName: "Lavender", batchCount: 1)

        #expect(BatchCodeGenerator.isTaken("lav-260930-01 ", among: [other]))
    }

    @Test func isTaken_OnlyTheBatchItselfHasTheCode_ReturnsFalse() {
        let batch = Batch(recipe: nil, code: "LAV-260930-01", recipeName: "Lavender", batchCount: 1)

        #expect(BatchCodeGenerator.isTaken("LAV-260930-01", among: [batch], excluding: batch) == false)
    }

    @Test func isTaken_EmptyCode_IsNeverADuplicate() {
        let uncoded = Batch(recipe: nil, recipeName: "Lavender", batchCount: 1)

        #expect(BatchCodeGenerator.isTaken("", among: [uncoded]) == false)
        #expect(BatchCodeGenerator.isTaken("   ", among: [uncoded]) == false)
    }

    @Test func isTaken_NoBatches_ReturnsFalse() {
        #expect(BatchCodeGenerator.isTaken("LAV-260930-01", among: []) == false)
    }

    @Test func isTaken_AnotherBatchHasTheCodeBesidesTheExcludedOne_ReturnsTrue() {
        let batch = Batch(recipe: nil, code: "LAV-260930-02", recipeName: "Lavender", batchCount: 1)
        let other = Batch(recipe: nil, code: "LAV-260930-01", recipeName: "Lavender", batchCount: 1)

        #expect(BatchCodeGenerator.isTaken("lav-260930-01", among: [batch, other], excluding: batch))
    }
}
