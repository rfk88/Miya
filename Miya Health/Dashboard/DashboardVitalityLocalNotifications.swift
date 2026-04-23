//
//  DashboardVitalityLocalNotifications.swift
//  Miya Health
//
//  Schedules and cancels local notifications for the CURRENT USER ONLY.
//  No family-level signals; never fires for another member's data.
//
//  Two notification types:
//    1. "Baseline ready" — one-time, fires when the user's first vitality score is available.
//    2. "Missing vitality / resync" — rate-limited to once per 24 h; tapping opens the sidebar.
//

import UserNotifications

// MARK: - Notification identifiers

enum VitalityNotificationIdentifier {
    /// One-time "your data is ready" notification.
    static let baselineReady = "miya.vitality.baseline_ready"
    /// Periodic "we're missing your metrics, please resync" notification.
    static let missingVitality = "miya.vitality.missing_vitality"
}

// MARK: - Scheduler

struct DashboardVitalityLocalNotifications {

    // MARK: - Baseline ready (fires once)

    /// Call this when the evaluator detects `initialBaselineComplete` for the first time.
    /// Guards against duplicates via `VitalityBannerStorage.hasNotifiedReady`.
    static func scheduleBaselineReady(userId: String?) async {
        guard let uid = userId, !uid.isEmpty else { return }
        guard !VitalityBannerStorage.hasNotifiedReady(userId: uid) else { return }

        let granted = await isAuthorized()
        guard granted else { return }

        // Mark first so a race can't schedule twice.
        VitalityBannerStorage.markNotifiedReady(userId: uid)

        let content = UNMutableNotificationContent()
        content.title = "Your health data is ready"
        content.body = "Miya has finished reading your health. Your vitality score is now live."
        content.sound = .default
        content.userInfo = ["data": ["kind": "baseline_ready"]]

        // Fire immediately (nil trigger = deliver at once).
        let request = UNNotificationRequest(
            identifier: VitalityNotificationIdentifier.baselineReady,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Non-fatal; the in-app banner is already gone by this point.
            print("⚠️ VitalityNotif: Could not schedule baseline-ready notification: \(error)")
        }
    }

    // MARK: - Missing vitality / resync (rate-limited)

    /// Call this when Banner B is active (user has no vitality after ingest phase).
    /// Fires at most once per 24 h per user; tapping opens the sidebar via deep link.
    static func scheduleMissingVitalityIfNeeded(userId: String?) async {
        guard let uid = userId, !uid.isEmpty else { return }
        guard VitalityBannerStorage.shouldSendResyncNotif(userId: uid) else { return }

        let granted = await isAuthorized()
        guard granted else { return }

        // Record before scheduling to prevent races.
        VitalityBannerStorage.setLastResyncNotifDate(Date(), userId: uid)

        let content = UNMutableNotificationContent()
        content.title = "We're missing your health metrics"
        content.body = "Tap to resync your wearable so Miya can calculate your vitality."
        content.sound = .default
        // Deep-link payload handled by AppDelegate → .miyaOpenSidebarForResync
        content.userInfo = ["data": ["kind": "open_sidebar_resync"]]

        // Delay 10 s so the banner doesn't fire while the user is actively looking at the dashboard.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(
            identifier: VitalityNotificationIdentifier.missingVitality,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("⚠️ VitalityNotif: Could not schedule missing-vitality notification: \(error)")
        }
    }

    // MARK: - Cancel when no longer needed

    /// Cancel any pending resync notification (call when `me.hasScore` becomes true).
    static func cancelMissingVitality() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [VitalityNotificationIdentifier.missingVitality]
        )
    }

    // MARK: - Private helpers

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized ||
               settings.authorizationStatus == .provisional
    }
}
