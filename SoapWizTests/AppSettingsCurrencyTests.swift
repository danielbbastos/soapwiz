import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The currency prices are shown in is a synced setting, not the device
/// region (SW-179): a region default is never stored, so a real choice always
/// wins when two devices' settings rows merge.
@Suite("AppSettings – currency", .serialized)
@MainActor
struct AppSettingsCurrencyTests {

    private let portugal = Locale(identifier: "pt_PT")

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func settings(_ uuid: String, currency: String) throws -> AppSettings {
        let settings = AppSettings()
        settings.uuid = try #require(UUID(uuidString: uuid))
        settings.currencyCode = currency
        return settings
    }

    @Test func currencyCode_NoRecords_UsesTheRegionCurrency() {
        #expect(AppSettings.currencyCode(from: [], locale: portugal) == "EUR")
    }

    @Test func currencyCode_NotChosen_UsesTheRegionCurrency() {
        let settings = AppSettings()

        #expect(AppSettings.currencyCode(from: [settings], locale: Locale(identifier: "en_GB")) == "GBP")
    }

    @Test func currencyCode_Chosen_IgnoresTheRegion() {
        let settings = AppSettings()
        settings.currencyCode = "EUR"

        #expect(AppSettings.currencyCode(from: [settings], locale: Locale(identifier: "en_GB")) == "EUR")
    }

    @Test func currencyCode_ReadsTheCanonicalRecord() throws {
        let canonical = try settings("00000000-0000-0000-0000-000000000001", currency: "CHF")
        let other = try settings("00000000-0000-0000-0000-000000000002", currency: "USD")

        #expect(AppSettings.currencyCode(from: [other, canonical], locale: portugal) == "CHF")
    }

    @Test func regionCurrencyCode_RegionWithoutCurrency_FallsBackToEuro() {
        #expect(AppSettings.regionCurrencyCode(locale: Locale(identifier: "en")) == "EUR")
    }

    @Test func resolve_NewRecord_LeavesCurrencyUnchosen() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let settings = AppSettings.resolve(in: ctx)

        #expect(settings.currencyCode.isEmpty)
    }

    // MARK: - Merge

    @Test func mergeAll_WinnerNotChosen_TakesTheOtherDevicesChoice() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try settings("00000000-0000-0000-0000-000000000001", currency: ""))
        ctx.insert(try settings("00000000-0000-0000-0000-000000000002", currency: "GBP"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.currencyCode == "GBP")
    }

    @Test func mergeAll_WinnerChosen_KeepsItsChoice() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try settings("00000000-0000-0000-0000-000000000001", currency: "EUR"))
        ctx.insert(try settings("00000000-0000-0000-0000-000000000002", currency: "GBP"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.currencyCode == "EUR")
    }

    @Test func mergeAll_NeitherChosen_StaysUnchosen() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try settings("00000000-0000-0000-0000-000000000001", currency: ""))
        ctx.insert(try settings("00000000-0000-0000-0000-000000000002", currency: ""))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.first?.currencyCode.isEmpty == true)
    }

    // MARK: - Picker choices

    @Test func currencyChoices_OfferCommonCodesSortedByLabel() {
        let choices = CurrencyChoice.all(including: "EUR", locale: portugal)

        #expect(choices.contains { $0.code == "EUR" })
        #expect(choices.contains { $0.code == "USD" })
        #expect(choices.map(\.label) == choices.map(\.label).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(Set(choices.map(\.code)).count == choices.count)
    }

    @Test func currencyChoices_LabelNamesTheCurrencyAndCode() throws {
        let euro = try #require(CurrencyChoice.all(including: "EUR", locale: portugal).first { $0.code == "EUR" })
        let name = try #require(portugal.localizedString(forCurrencyCode: "EUR"))

        #expect(euro.label == "\(name) (EUR)")
    }

    @Test func currencyChoices_UncommonSelection_IsStillOffered() throws {
        let common = Set(Locale.commonISOCurrencyCodes)
        let uncommon = try #require(Locale.Currency.isoCurrencies.map(\.identifier).first { !common.contains($0) })

        #expect(CurrencyChoice.all(including: uncommon, locale: portugal).contains { $0.code == uncommon })
    }

    @Test func currencyChoices_EmptySelection_IsNotOffered() {
        #expect(!CurrencyChoice.all(including: "", locale: portugal).contains { $0.code.isEmpty })
    }
}
