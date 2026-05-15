//
//  AppDelegate.swift
//  Miya Health
//
//  Enables ROOK background listeners for HealthKit background delivery.
//  Also handles Apple Push Notification registration and device token upload.
//

import UIKit
import RookSDK
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Required by ROOK to receive background delivery callbacks and upload summaries/events.
        RookBackGroundSync.shared.setBackListeners()
        RookBackGroundSync.shared.enableBackGroundForSummaries()
        RookBackGroundSync.shared.enableBackGroundForEvents()
        print("✅ AppDelegate: ROOK background listeners enabled")

        // Set ourselves as the notification center delegate so we can show
        // banners while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = self

        // Push permission is requested from onboarding Privacy & Alerts when the user enables
        // "Push notifications". This avoids prompting too early at cold app launch.

        return true
    }

    // MARK: - APNs Token Handling

    /// Called by iOS when APNs successfully issues a device token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationRegistration.handleDeviceToken(deviceToken)
    }

    /// Called when APNs registration fails — expected on the iOS Simulator.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("⚠️ AppDelegate: APNs registration failed (normal on Simulator): \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show alert banners, play sound, and update badge even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user taps a push notification banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let data = userInfo["data"] as? [String: Any],
           let kind = data["kind"] as? String {
            switch kind {
            case "invite_joined":
                NotificationCenter.default.post(
                    name: .miyaPushTapInviteJoined, object: nil
                )
            case "open_sidebar_resync":
                NotificationCenter.default.post(
                    name: .miyaOpenSidebarForResync, object: nil
                )
            case "champions_moment":
                NotificationCenter.default.post(
                    name: .miyaOpenChampions, object: nil
                )
            default:
                break
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let miyaPushTapInviteJoined = Notification.Name("MiyaPushTapInviteJoined")
    static let miyaOpenSidebarForResync = Notification.Name("MiyaOpenSidebarForResync")
    /// User tapped a Champions change moment notification (local or push with this payload).
    static let miyaOpenChampions = Notification.Name("MiyaOpenChampions")
}
