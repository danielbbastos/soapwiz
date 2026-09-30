import Testing
import Foundation
@testable import SoapWiz

/// Which photos the full-size viewer pages through, and which page it opens on,
/// when some of an entry's photos haven't arrived from iCloud yet.
@Suite("Batch log viewer pages")
@MainActor
struct BatchLogViewerPagesTests {

    private let first = Data("first".utf8)
    private let second = Data("second".utf8)
    private let third = Data("third".utf8)

    @Test func viewerPages_AllPhotosPresent_OpensOnTheTappedOne() throws {
        let pages = try #require(BatchHistoryViewModel.viewerPages([first, second, third], tappedIndex: 1))

        #expect(pages.images == [first, second, third])
        #expect(pages.startIndex == 1)
    }

    @Test func viewerPages_PhotoBeforeTheTappedOneMissing_SkipsItAndStillOpensOnTheTappedOne() throws {
        let pages = try #require(BatchHistoryViewModel.viewerPages([first, nil, third], tappedIndex: 2))

        #expect(pages.images == [first, third])
        #expect(pages.startIndex == 1)
        #expect(pages.images[pages.startIndex] == third)
    }

    @Test func viewerPages_TappedPhotoMissing_IsNil() {
        #expect(BatchHistoryViewModel.viewerPages([first, nil, third], tappedIndex: 1)?.startIndex == nil)
    }

    @Test func viewerPages_IndexOutOfRange_IsNil() {
        #expect(BatchHistoryViewModel.viewerPages([first], tappedIndex: 1)?.startIndex == nil)
        #expect(BatchHistoryViewModel.viewerPages([first], tappedIndex: -1)?.startIndex == nil)
    }
}
