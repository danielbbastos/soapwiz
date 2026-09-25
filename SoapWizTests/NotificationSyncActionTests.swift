import Testing
import Foundation
import UserNotifications
@testable import SoapWiz

/// What a sync does with this device's reminders (SW-186). A restore or another
/// device can switch reminders or tracking off without the Settings toggle, so
/// either being off cancels them; a missing permission only skips this device,
/// since turning the synced setting off would cancel them everywhere.
@Suite("NotificationService – sync action")
@MainActor
struct NotificationSyncActionTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let remindersOn: Bool
        let tracksInventory: Bool
        let authorization: UNAuthorizationStatus
        let expected: NotificationService.SyncAction
        var testDescription: String {
            "reminders \(remindersOn), tracking \(tracksInventory), authorization \(authorization.rawValue)"
        }
    }

    @Test(arguments: [
        Case(remindersOn: true, tracksInventory: true, authorization: .authorized, expected: .schedule),
        Case(remindersOn: true, tracksInventory: true, authorization: .notDetermined, expected: .requestPermission),
        Case(remindersOn: true, tracksInventory: true, authorization: .denied, expected: .skip),
        Case(remindersOn: true, tracksInventory: true, authorization: .provisional, expected: .skip),
        Case(remindersOn: false, tracksInventory: true, authorization: .authorized, expected: .cancel),
        Case(remindersOn: false, tracksInventory: true, authorization: .denied, expected: .cancel),
        Case(remindersOn: true, tracksInventory: false, authorization: .authorized, expected: .cancel),
        Case(remindersOn: true, tracksInventory: false, authorization: .notDetermined, expected: .cancel),
        Case(remindersOn: false, tracksInventory: false, authorization: .authorized, expected: .cancel)
    ])
    func syncAction_FollowsTheSettingAndThisDevicesPermission(_ testCase: Case) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.remindersOn
        settings.tracksInventory = testCase.tracksInventory

        let action = NotificationService.syncAction(for: settings, authorization: testCase.authorization)

        #expect(action == testCase.expected)
    }
}
