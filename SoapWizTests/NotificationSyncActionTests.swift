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

    struct NoteCase: CustomTestStringConvertible, Sendable {
        let remindersOn: Bool
        let tracksInventory: Bool
        let authorization: UNAuthorizationStatus
        let showsNote: Bool
        var testDescription: String {
            "reminders \(remindersOn), tracking \(tracksInventory), authorization \(authorization.rawValue)"
        }
    }

    /// Settings says this device won't deliver reminders exactly when they are
    /// on and it has refused them (SW-187) — not while it hasn't been asked yet,
    /// since the next sync asks, and not when reminders are off anyway.
    ///
    /// `.provisional` can't arise today, since the app only asks for full
    /// alerts. It is listed because the sync skips it too, so reminders
    /// wouldn't be scheduled and the note would still be true in substance.
    @Test(arguments: [
        NoteCase(remindersOn: true, tracksInventory: true, authorization: .denied, showsNote: true),
        NoteCase(remindersOn: true, tracksInventory: true, authorization: .provisional, showsNote: true),
        NoteCase(remindersOn: true, tracksInventory: true, authorization: .authorized, showsNote: false),
        NoteCase(remindersOn: true, tracksInventory: true, authorization: .notDetermined, showsNote: false),
        NoteCase(remindersOn: false, tracksInventory: true, authorization: .denied, showsNote: false),
        NoteCase(remindersOn: true, tracksInventory: false, authorization: .denied, showsNote: false)
    ])
    func deviceMayNotNotify_OnlyWhenRemindersAreOnAndThisDeviceRefusedThem(_ testCase: NoteCase) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.remindersOn
        settings.tracksInventory = testCase.tracksInventory

        let showsNote = NotificationService.deviceMayNotNotify(for: settings, authorization: testCase.authorization)

        #expect(showsNote == testCase.showsNote)
    }

    // MARK: - A tap on the toggle

    @Test func applyToggle_OnAndGranted_TurnsRemindersOn() async {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = false

        let showsDenied = await NotificationService.applyToggle(true, to: settings) { true }

        #expect(settings.expiryNotificationsEnabled)
        #expect(!showsDenied)
    }

    /// The setting is never written on a refusal: it syncs, and switching it
    /// off here would switch reminders off on every other device too.
    @Test func applyToggle_OnAndRefused_LeavesTheSettingAloneAndSaysWhy() async {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = false

        let showsDenied = await NotificationService.applyToggle(true, to: settings) { false }

        #expect(!settings.expiryNotificationsEnabled)
        #expect(showsDenied)
    }

    @Test func applyToggle_Off_TurnsRemindersOffWithoutAsking() async {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = true
        var asked = false

        let showsDenied = await NotificationService.applyToggle(false, to: settings) {
            asked = true
            return false
        }

        #expect(!settings.expiryNotificationsEnabled)
        #expect(!asked)
        #expect(!showsDenied)
    }
}
