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

        let action = NotificationService.syncAction(for: settings, authorization: testCase.authorization, isPro: true)

        #expect(action == testCase.expected)
    }

    struct FreeCase: CustomTestStringConvertible, Sendable {
        let expiryOn: Bool
        let cureOn: Bool
        let tracksInventory: Bool
        let authorization: UNAuthorizationStatus
        var testDescription: String {
            "expiry \(expiryOn), cure \(cureOn), tracking \(tracksInventory), authorization \(authorization.rawValue)"
        }
    }

    private static let freeCases: [FreeCase] = {
        let statuses: [UNAuthorizationStatus] = [.notDetermined, .denied, .authorized, .provisional, .ephemeral]
        return statuses.flatMap { status in
            [true, false].flatMap { expiry in
                [true, false].flatMap { cure in
                    [true, false].map { tracks in
                        FreeCase(expiryOn: expiry, cureOn: cure, tracksInventory: tracks, authorization: status)
                    }
                }
            }
        }
    }()

    /// Reminders are part of Pro: whatever the stored flags and this device's
    /// permission say, a free user has nothing scheduled.
    @Test(arguments: freeCases)
    func syncAction_FreeUser_AlwaysCancels(_ testCase: FreeCase) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.expiryOn
        settings.cureNotificationsEnabled = testCase.cureOn
        settings.tracksInventory = testCase.tracksInventory

        let action = NotificationService.syncAction(for: settings, authorization: testCase.authorization, isPro: false)

        #expect(action == .cancel)
    }

    @Test func deviceMayNotNotify_FreeUserWithRemindersOnAndRefused_ShowsNoNote() {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = true

        #expect(!NotificationService.deviceMayNotNotify(for: settings, authorization: .denied, isPro: false))
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

        let showsNote = NotificationService.deviceMayNotNotify(
            for: settings,
            authorization: testCase.authorization,
            isPro: true
        )

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

        let action = NotificationService.syncAction(for: settings, authorization: testCase.authorization, isPro: true)

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
        var releaseFirst: CheckedContinuation<Void, Never>?

        let first = Task {
            await NotificationService.serialized {
                log.append("first started")
                await withCheckedContinuation { releaseFirst = $0 }
                log.append("first ended")
            }
        }
        // Asked for only once the first is known to be running, so the order
        // is the queue's doing rather than the scheduler's.
        while releaseFirst == nil {
            await Task.yield()
        }
        let second = Task {
            await NotificationService.serialized {
                log.append("second started")
            }
        }
        // Room for the second to run if nothing held it back.
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(log == ["first started"])

        releaseFirst?.resume()
        await first.value
        await second.value

        #expect(log == ["first started", "first ended", "second started"])
    }

    struct PermissionCase: CustomTestStringConvertible, Sendable {
        let expiryOn: Bool
        let cureOn: Bool
        let authorization: UNAuthorizationStatus
        let isPro: Bool
        let expected: Bool
        var testDescription: String {
            "expiry \(expiryOn), cure \(cureOn), authorization \(authorization.rawValue), pro \(isPro)"
        }
    }

    @Test(arguments: [
        PermissionCase(expiryOn: true, cureOn: false, authorization: .notDetermined, isPro: true, expected: true),
        PermissionCase(expiryOn: false, cureOn: true, authorization: .notDetermined, isPro: true, expected: true),
        PermissionCase(expiryOn: true, cureOn: true, authorization: .notDetermined, isPro: true, expected: true),
        PermissionCase(expiryOn: true, cureOn: true, authorization: .notDetermined, isPro: false, expected: false),
        PermissionCase(expiryOn: false, cureOn: false, authorization: .notDetermined, isPro: true, expected: false),
        PermissionCase(expiryOn: true, cureOn: true, authorization: .authorized, isPro: true, expected: false),
        PermissionCase(expiryOn: true, cureOn: true, authorization: .denied, isPro: true, expected: false)
    ])
    func shouldRequestPermission_OnlyProWithReminderOnAndNoAnswer(_ testCase: PermissionCase) {
        let settings = AppSettings()
        settings.expiryNotificationsEnabled = testCase.expiryOn
        settings.cureNotificationsEnabled = testCase.cureOn

        let result = NotificationService.shouldRequestPermission(
            settings: settings,
            authorization: testCase.authorization,
            isPro: testCase.isPro
        )

        #expect(result == testCase.expected)
    }

    @Test func deviceMayNotNotify_CureRemindersOnAndRefused_ShowsNote() {
        let settings = AppSettings()
        settings.cureNotificationsEnabled = true

        #expect(NotificationService.deviceMayNotNotify(for: settings, authorization: .denied, isPro: true))
    }
}
