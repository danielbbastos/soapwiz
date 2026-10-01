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

        let showsDenied = await NotificationService.applyToggle(
            true, setting: \.expiryNotificationsEnabled, settings: { settings }, askPermission: { true }
        )

        #expect(settings.expiryNotificationsEnabled)
        #expect(!showsDenied)
    }

    /// A first sync can merge this device's settings row away while the
    /// permission prompt is up; the grant must land on the row that survived.
    @Test func applyToggle_RowReplacedDuringThePrompt_WritesTheCurrentRow() async {
        let tapped = AppSettings()
        let survivor = AppSettings()
        var current = tapped

        let showsDenied = await NotificationService.applyToggle(
            true,
            setting: \.expiryNotificationsEnabled,
            settings: { current },
            askPermission: {
                current = survivor
                return true
            }
        )

        #expect(survivor.expiryNotificationsEnabled)
        #expect(!tapped.expiryNotificationsEnabled)
        #expect(!showsDenied)
    }

    /// The setting is never written on a refusal: it syncs, and switching it
    /// off here would switch reminders off on every other device too.
    @Test func applyToggle_OnAndRefused_LeavesTheSettingAloneAndSaysWhy() async {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = false

        let showsDenied = await NotificationService.applyToggle(
            true, setting: \.expiryNotificationsEnabled, settings: { settings }, askPermission: { false }
        )

        #expect(!settings.expiryNotificationsEnabled)
        #expect(showsDenied)
    }

    @Test func applyToggle_Off_TurnsRemindersOffWithoutAsking() async {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = true
        var asked = false

        let showsDenied = await NotificationService.applyToggle(
            false,
            setting: \.expiryNotificationsEnabled,
            settings: { settings },
            askPermission: {
                asked = true
                return false
            }
        )

        #expect(!settings.expiryNotificationsEnabled)
        #expect(!asked)
        #expect(!showsDenied)
    }

    @Test func applyToggle_CureSetting_WritesOnlyThatSetting() async {
        let settings = AppSettings()

        let showsDenied = await NotificationService.applyToggle(
            true, setting: \.cureNotificationsEnabled, settings: { settings }, askPermission: { true }
        )

        #expect(settings.cureNotificationsEnabled)
        #expect(!settings.expiryNotificationsEnabled)
        #expect(!showsDenied)
    }
}

/// The cure reminders (SW-193) sit beside the expiry ones: they follow their
/// own setting alone, so turning stock tracking off quiets only the expiry
/// reminders, and a sync cancels everything only when neither kind is on.
@Suite("NotificationService – cure reminders")
@MainActor
struct NotificationCureSyncActionTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let expiryOn: Bool
        let cureOn: Bool
        let tracksInventory: Bool
        let authorization: UNAuthorizationStatus
        let expected: NotificationService.SyncAction
        var testDescription: String {
            "expiry \(expiryOn), cure \(cureOn), tracking \(tracksInventory), authorization \(authorization.rawValue)"
        }
    }

    @Test(arguments: [
        Case(expiryOn: false, cureOn: true, tracksInventory: true, authorization: .authorized, expected: .schedule),
        Case(expiryOn: false, cureOn: true, tracksInventory: false, authorization: .authorized, expected: .schedule),
        Case(expiryOn: true, cureOn: true, tracksInventory: false, authorization: .authorized, expected: .schedule),
        Case(expiryOn: false, cureOn: true, tracksInventory: true, authorization: .notDetermined, expected: .requestPermission),
        Case(expiryOn: false, cureOn: true, tracksInventory: true, authorization: .denied, expected: .skip),
        Case(expiryOn: true, cureOn: false, tracksInventory: false, authorization: .authorized, expected: .cancel),
        Case(expiryOn: false, cureOn: false, tracksInventory: true, authorization: .authorized, expected: .cancel)
    ])
    func syncAction_EitherKindActive_Syncs(_ testCase: Case) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.expiryOn
        settings.cureNotificationsEnabled = testCase.cureOn
        settings.tracksInventory = testCase.tracksInventory

        let action = NotificationService.syncAction(for: settings, authorization: testCase.authorization)

        #expect(action == testCase.expected)
    }

    @Test func activeKinds_TrackingOff_KeepsCureAndDropsExpiry() {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = true
        settings.cureNotificationsEnabled = true
        settings.tracksInventory = false

        #expect(!NotificationService.expiryRemindersActive(for: settings))
        #expect(NotificationService.cureRemindersActive(for: settings))
    }

    /// A change asked for while another is still running waits for it, so a
    /// cure stepped twice can't leave the first step's reminder behind.
    @Test func serialized_SecondChangeWhileFirstRuns_StartsAfterItEnds() async {
        var log: [String] = []

        async let first: Void = NotificationService.serialized {
            log.append("first started")
            try? await Task.sleep(for: .milliseconds(100))
            log.append("first ended")
        }
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void = NotificationService.serialized {
            log.append("second started")
        }
        _ = await (first, second)

        #expect(log == ["first started", "first ended", "second started"])
    }

    @Test func deviceMayNotNotify_CureRemindersOnAndRefused_ShowsNote() {
        let settings = AppSettings()
        settings.cureNotificationsEnabled = true

        #expect(NotificationService.deviceMayNotNotify(for: settings, authorization: .denied))
    }
}
