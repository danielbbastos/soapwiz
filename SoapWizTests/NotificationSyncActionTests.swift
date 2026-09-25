import Testing
import Foundation
@testable import SoapWiz

/// A sync clears the scheduled reminders whenever reminders or tracking are
/// off (SW-186): a restore or another device can switch either off without the
/// Settings toggle, which is the only other place that cancels them.
@Suite("NotificationService – sync action")
@MainActor
struct NotificationSyncActionTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let remindersOn: Bool
        let tracksInventory: Bool
        let expected: NotificationService.SyncAction
        var testDescription: String { "reminders \(remindersOn), tracking \(tracksInventory)" }
    }

    @Test(arguments: [
        Case(remindersOn: true, tracksInventory: true, expected: .schedule),
        Case(remindersOn: false, tracksInventory: true, expected: .cancel),
        Case(remindersOn: true, tracksInventory: false, expected: .cancel),
        Case(remindersOn: false, tracksInventory: false, expected: .cancel)
    ])
    func syncAction_SchedulesOnlyWhenRemindersAndTrackingAreOn(_ testCase: Case) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.remindersOn
        settings.tracksInventory = testCase.tracksInventory

        #expect(NotificationService.syncAction(for: settings) == testCase.expected)
    }
}
