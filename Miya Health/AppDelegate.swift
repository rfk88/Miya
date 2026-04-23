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
import Supabase

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
    /// Saves the token to Supabase and auto-enables push notifications in the user's profile.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("✅ AppDelegate: APNs device token received")

        Task {
            do {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let osVersion = UIDevice.current.systemVersion

                // Save device token so the backend can send pushes to this device
                try await SupabaseConfig.client
                    .rpc("register_device_token", params: [
                        "token": AnyJSON.string(tokenString),
                        "platform_type": AnyJSON.string("ios"),
                        "app_ver": AnyJSON.string(appVersion),
                        "os_ver": AnyJSON.string(osVersion)
                    ])
                    .execute()

                // Auto-enable push notifications in the user's profile.
                // Granting the iOS permission prompt = push is on — no extra toggle needed.
                if let userId = SupabaseConfig.client.auth.currentUser?.id.uuidString {
                    try await SupabaseConfig.client
                        .from("user_profiles")
                        .update(["notify_push": AnyJSON.bool(true)])
                        .eq("user_id", value: userId)
                        .execute()
                }

                print("✅ AppDelegate: Device token registered and push notifications enabled")
            } catch {
                // Expected on first launch before sign-in. Retried after login
                // via registerForRemoteNotifications() in Miya_HealthApp.swift.
                print("⚠️ AppDelegate: Could not register token yet (expected before login): \(error.localizedDescription)")
            }
        }
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
    /// Posts a typed NotificationCenter event so SwiftUI views can react
    /// without AppDelegate needing direct references to view state.
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
}
