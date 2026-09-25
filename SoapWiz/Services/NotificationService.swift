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

    /// Reminders or tracking can be switched off without the Settings toggle —
    /// synced from another device, or by a restore — so either being off clears
    /// the reminders already scheduled here rather than leaving them to fire.
    ///
    /// A missing permission never turns the setting off: the setting syncs, the
    /// permission is this device's alone, and switching it off here would cancel
    /// the reminders on every other device.
    static func syncAction(for settings: AppSettings, authorization: UNAuthorizationStatus) -> SyncAction {
        guard settings.expiryNotificationsEnabled, settings.tracksInventory else { return .cancel }
        switch authorization {
        case .authorized: return .schedule
        case .notDetermined: return .requestPermission
        default: return .skip
        }
    }

    static func syncIfEnabled(modelContext: ModelContext) async {
        let settings = AppSettings.resolve(in: modelContext)
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus

        switch syncAction(for: settings, authorization: status) {
        case .cancel:
            await cancelAllExpiryNotifications()
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

    static func syncNotifications(modelContext: ModelContext) async {
        let purchases: [IngredientPurchase]
        do {
            purchases = try modelContext.fetch(FetchDescriptor<IngredientPurchase>())
        } catch {
            return
        }

        let snapshots = purchases.compactMap { purchase -> PurchaseSnapshot? in
            guard let name = purchase.ingredient?.name,
                  let expiryDate = purchase.expiryDate else { return nil }
            return PurchaseSnapshot(
                ingredientName: name,
                expiryDate: expiryDate,
                remainingAmount: purchase.remainingAmount
            )
        }

        let allRequests = ExpiryNotificationScheduler.computeRequests(purchases: snapshots)
        let requests = allRequests.prefix(64)

        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(ExpiryNotificationScheduler.notificationPrefix) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

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

    static func cancelAllExpiryNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let expiryIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(ExpiryNotificationScheduler.notificationPrefix) }
        if !expiryIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: expiryIDs)
        }
    }
}
