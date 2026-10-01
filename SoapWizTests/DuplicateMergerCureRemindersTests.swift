import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Cure reminders switched on on one device survive a merge that keeps
/// another device's untouched settings row (SW-193), as the expiry reminders
/// already do.
@Suite("Duplicate merger – cure reminders", .serialized)
@MainActor
struct DuplicateMergerCureRemindersTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    @Test func mergeAll_CureRemindersOnAnyDevice_StayOn() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let untouched = AppSettings()
        untouched.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let opted = AppSettings()
        opted.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        opted.cureNotificationsEnabled = true
        ctx.insert(untouched)
        ctx.insert(opted)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.uuid == untouched.uuid)
        #expect(remaining.first?.cureNotificationsEnabled == true)
        #expect(remaining.first?.expiryNotificationsEnabled == false)
    }

    @Test func mergeAll_CureRemindersOffEverywhere_StayOff() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = AppSettings()
        first.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = AppSettings()
        second.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        ctx.insert(first)
        ctx.insert(second)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.first?.cureNotificationsEnabled == false)
    }
}
