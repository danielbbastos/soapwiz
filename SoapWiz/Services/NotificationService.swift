import UserNotifications
import SwiftData

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// What a sync does with the reminders scheduled on this device.
    enum SyncAction: Equatable {
        case cancel
        case schedule
        case requestPermission
        /// This device may not notify; leave the setting and the schedule alone.
        case skip
    }

    /// Expiry reminders are about stock, so they go quiet with tracking off.
    static func expiryRemindersActive(for settings: AppSettings) -> Bool {
        settings.expiryNotificationsEnabled && settings.tracksInventory
    }

    /// Cure reminders have nothing to do with stock and follow their own
    /// setting alone.
    static func cureRemindersActive(for settings: AppSettings) -> Bool {
        settings.cureNotificationsEnabled
    }

    /// Reminders or tracking can be switched off without the Settings toggle —
    /// synced from another device, or by a restore — so with no kind of
    /// reminder left active, the ones already scheduled here are cleared rather
    /// than left to fire. With one kind still active, the sync schedules and
    /// drops the other kind itself.
    ///
    /// A missing permission never turns the setting off: the setting syncs, the
    /// permission is this device's alone, and switching it off here would cancel
    /// the reminders on every other device.
    static func syncAction(for settings: AppSettings, authorization: UNAuthorizationStatus) -> SyncAction {
        guard expiryRemindersActive(for: settings) || cureRemindersActive(for: settings) else { return .cancel }
        switch authorization {
        case .authorized: return .schedule
        case .notDetermined: return .requestPermission
        default: return .skip
        }
    }

    /// Whether Settings should say that this device won't deliver reminders
    /// that are switched on: exactly when a sync skips it (SW-187). The setting
    /// syncs and the permission doesn't, so without the note a device that
    /// refused notifications shows reminders on while none ever arrive there.
    static func deviceMayNotNotify(for settings: AppSettings, authorization: UNAuthorizationStatus) -> Bool {
        syncAction(for: settings, authorization: authorization) == .skip
    }

    /// A tap on a reminders toggle, writing `setting`. Turning reminders on asks
    /// for this device's permission first and stores the setting only once it's
    /// granted, so a refusal never switches a synced setting that is on
    /// elsewhere off. Returns whether to tell the user notifications are
    /// refused here.
    ///
    /// Only a tap comes through here. A change that arrives from another device
    /// or a restore must never ask, and never write the setting back: a device
    /// that refused would switch reminders off on every other one.
    ///
    /// `settings` is read again after the permission prompt rather than taken
    /// at the tap. The prompt stays up as long as the user leaves it, and a
    /// first sync on a new device can merge this device's settings row away
    /// meanwhile, which would swallow a write to the row captured earlier.
    static func applyToggle(
        _ isOn: Bool,
        setting: ReferenceWritableKeyPath<AppSettings, Bool>,
        settings: () -> AppSettings,
        askPermission: () async -> Bool = { await requestAuthorization() }
    ) async -> Bool {
        guard isOn else {
            settings()[keyPath: setting] = false
            return false
        }
        guard await askPermission() else { return true }
        settings()[keyPath: setting] = true
        return false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The last change to this device's pending reminders that was asked for.
    /// Each change waits for the one before it: a sync clears the pending
    /// reminders and then adds the new ones across several awaits, and a
    /// second sync landing in between — a cure stepped twice, or a stepper
    /// tap meeting the foreground sync — would otherwise leave the first
    /// one's outdated reminder pending beside its own.
    private static var lastChange: Task<Void, Never>?

    /// Runs `change` after every change already asked for, so changes to the
    /// pending reminders never interleave. Each sync reads the store when its
    /// turn comes, so the last one always reflects the latest state.
    static func serialized(_ change: @escaping () async -> Void) async {
        let previous = lastChange
        let task = Task {
            await previous?.value
            await change()
        }
        lastChange = task
        await task.value
    }

    static func syncIfEnabled(modelContext: ModelContext) async {
        await serialized { await performSync(modelContext: modelContext) }
    }

    private static func performSync(modelContext: ModelContext) async {
        let settings = AppSettings.resolve(in: modelContext)
        let status = await authorizationStatus()

        switch syncAction(for: settings, authorization: status) {
        case .cancel:
            await cancelPendingReminders(withPrefixes: allPrefixes)
        case .schedule:
            await syncNotifications(modelContext: modelContext)
        case .requestPermission:
            if await requestAuthorization() {
                await syncNotifications(modelContext: modelContext)
            }
        case .skip:
            break
        }
    }

    private static let allPrefixes = [
        ExpiryNotificationScheduler.notificationPrefix,
        CureNotificationScheduler.notificationPrefix
    ]

    /// iOS keeps only the 64 soonest pending notifications of an app, so the
    /// two kinds share that budget, soonest first.
    private static let pendingLimit = 64

    /// Replaces every reminder scheduled here with the ones the store calls
    /// for now. A kind that isn't active contributes none, so its pending
    /// reminders go with the rest.
    private static func syncNotifications(modelContext: ModelContext) async {
        let settings = AppSettings.resolve(in: modelContext)
        let expiry: [ScheduledReminder]
        let cure: [ScheduledReminder]
        do {
            expiry = expiryRemindersActive(for: settings) ? try expiryRequests(modelContext) : []
            cure = cureRemindersActive(for: settings) ? try cureRequests(modelContext) : []
        } catch {
            return
        }
        let requests = (expiry + cure).sorted { $0.fireDate < $1.fireDate }.prefix(pendingLimit)

        let center = UNUserNotificationCenter.current()
        await cancelPendingReminders(withPrefixes: allPrefixes)

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: request.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let notificationRequest = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )

            try? await center.add(notificationRequest)
        }
    }

    private static func expiryRequests(_ modelContext: ModelContext) throws -> [ScheduledReminder] {
        let purchases = try modelContext.fetch(FetchDescriptor<IngredientPurchase>())
        let snapshots = purchases.compactMap { purchase -> PurchaseSnapshot? in
            guard let name = purchase.ingredient?.name,
                  let expiryDate = purchase.expiryDate else { return nil }
            return PurchaseSnapshot(
                ingredientName: name,
                expiryDate: expiryDate,
                remainingAmount: purchase.remainingAmount
            )
        }
        return ExpiryNotificationScheduler.computeRequests(purchases: snapshots)
    }

    /// Only batches that cure: anything else never schedules a reminder.
    private static func cureRequests(_ modelContext: ModelContext) throws -> [ScheduledReminder] {
        let batches = try modelContext.fetch(FetchDescriptor<Batch>(predicate: #Predicate { $0.cureDays > 0 }))
        let snapshots = batches.compactMap { batch -> CureSnapshot? in
            guard let readyDate = batch.cureReadyDate else { return nil }
            return CureSnapshot(
                recipeName: batch.recipeName,
                code: batch.code,
                usableDate: batch.cureUsableDate,
                readyDate: readyDate
            )
        }
        return CureNotificationScheduler.computeRequests(batches: snapshots)
    }

    static func cancelAllExpiryNotifications() async {
        await serialized { await cancelPendingReminders(withPrefixes: [ExpiryNotificationScheduler.notificationPrefix]) }
    }

    private static func cancelPendingReminders(withPrefixes prefixes: [String]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { id in prefixes.contains { id.hasPrefix($0) } }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
