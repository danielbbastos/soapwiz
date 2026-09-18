import Testing
import Foundation
@testable import SoapWiz

@Suite
struct AppVersionDisplayTests {

    @Test func appVersionDisplay_ShortVersionAndBuild_CombinesBoth() {
        #expect(Bundle.appVersionDisplay(shortVersion: "1.0", build: "1") == "1.0 (1)")
    }

    @Test func appVersionDisplay_BuildMissing_ReturnsShortVersionOnly() {
        #expect(Bundle.appVersionDisplay(shortVersion: "1.0", build: nil) == "1.0")
    }

    @Test func appVersionDisplay_ShortVersionMissing_ReturnsPlaceholder() {
        #expect(Bundle.appVersionDisplay(shortVersion: nil, build: "1") == "—")
    }

    @Test func appVersionDisplay_BothMissing_ReturnsPlaceholder() {
        #expect(Bundle.appVersionDisplay(shortVersion: nil, build: nil) == "—")
    }
}
