//
//  DashboardChampionsLocalNotifications.swift
//  Miya Health
//
//  Schedules system notification banners for Champions change moments (same pipeline as
//  DashboardVitalityLocalNotifications). Banner-only: no in-app toast for these events.
//

import Foundation
import UserNotifications

enum ChampionsNotificationIdentifier {
    /// One pending request per moment id (replaces duplicate refreshes).
    static func requestId(momentId: String) -> String {
        "miya.champions.moment.\(momentId)"
    }
}

struct DashboardChampionsLocalNotifications {

    /// Enqueue a banner for a Champions change moment. No-op if notifications denied or id invalid.
    static func schedule(momentId: String, title: String, body: String) async {
        let trimmedId = momentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }

        let granted = await isAuthorized()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let dataDict: [String: String] = [
            "kind": "champions_moment",
            "moment_id": trimmedId,
        ]
        content.userInfo = ["data": dataDict]

        let request = UNNotificationRequest(
            identifier: ChampionsNotificationIdentifier.requestId(momentId: trimmedId),
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("⚠️ ChampionsNotif: Could not schedule moment notification: \(error)")
        }
    }

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional
    }
}
