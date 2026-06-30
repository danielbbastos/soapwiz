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

    static func syncIfEnabled(modelContext: ModelContext) async {
        let settings = AppSettings.resolve(in: modelContext)
        guard settings.expiryNotificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        guard notificationSettings.authorizationStatus == .authorized else { return }

        await syncNotifications(modelContext: modelContext)
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

        let requests = ExpiryNotificationScheduler.computeRequests(purchases: snapshots)

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
