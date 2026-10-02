import Testing
@testable import SoapWiz

/// Expanding a collapsible section scrolls its header to the top of the form.
/// Nothing marks a section's last row any more, so the request only ever names
/// a header.
@Suite("ExpandingSectionScrollContext")
@MainActor
struct ExpandingSectionScrollContextTests {

    @Test func expansionBegan_AfterSettling_RequestsTheSectionHeader() async throws {
        let sut = ExpandingSectionScrollContext(settleDelay: .milliseconds(10))

        sut.expansionBegan("additives")

        let request = try #require(await settledRequest(of: sut))
        #expect(request.target == ExpandingSectionHeaderID(section: "additives"))
    }

    @Test func expansionBegan_BeforeSettling_RequestsNothing() {
        let sut = ExpandingSectionScrollContext(settleDelay: .seconds(60))

        sut.expansionBegan("additives")

        #expect(sut.request == nil)
    }

    @Test func expansionBegan_SameSectionTwice_RequestsTwiceWithDistinctTokens() async throws {
        let sut = ExpandingSectionScrollContext(settleDelay: .milliseconds(10))

        sut.expansionBegan("oils")
        let first = try #require(await settledRequest(of: sut))
        sut.expansionBegan("oils")
        let second = try #require(await settledRequest(of: sut, after: first))

        #expect(first.target == second.target)
        #expect(first != second)
    }

    @Test func expansionBegan_AnotherSectionBeforeSettling_RequestsOnlyTheLatest() async throws {
        let sut = ExpandingSectionScrollContext(settleDelay: .milliseconds(50))

        sut.expansionBegan("oils")
        sut.expansionBegan("fragrances")

        let request = try #require(await settledRequest(of: sut))
        #expect(request.target == ExpandingSectionHeaderID(section: "fragrances"))
        #expect(request.token == 1)
    }

    @Test func headerMoved_WhilePending_DelaysTheRequest() async throws {
        let sut = ExpandingSectionScrollContext(settleDelay: .milliseconds(200))

        sut.expansionBegan("additives")
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(40))
            sut.headerMoved("additives")
        }

        #expect(sut.request == nil)
        let request = try #require(await settledRequest(of: sut))
        #expect(request.target == ExpandingSectionHeaderID(section: "additives"))
    }

    @Test func headerMoved_NothingPending_RequestsNothing() async throws {
        let sut = ExpandingSectionScrollContext(settleDelay: .milliseconds(10))

        sut.headerMoved("additives")
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.request == nil)
    }

    /// Polls until the context publishes a request other than `previous`, or
    /// gives up after two seconds.
    private func settledRequest(
        of sut: ExpandingSectionScrollContext,
        after previous: ExpandingSectionScrollRequest? = nil
    ) async -> ExpandingSectionScrollRequest? {
        for _ in 0..<200 {
            if let request = sut.request, request != previous { return request }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}
