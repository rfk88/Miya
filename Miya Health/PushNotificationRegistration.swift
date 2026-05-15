//
//  PushNotificationRegistration.swift
//  Miya Health
//
//  Centralizes APNs registration, permission checks, and Supabase device token upload
//  so pushes can be delivered while the app is in the background.
//

import Foundation
import Supabase
import UIKit
import UserNotifications

enum PushNotificationRegistration {

    private static let pendingTokenKey = "miya.pendingApnsDeviceToken"

    // MARK: - Public API

    /// Call after auth is available (cold start, login, foreground) when the user has granted notification permission.
    @MainActor
    static func registerIfAuthorized() {
        Task {
            guard await isNotificationAuthorized() else {
                #if DEBUG
                print("ℹ️ PushRegistration: skipping registerForRemoteNotifications (not authorized)")
                #endif
                return
            }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Request iOS permission (if needed) and register for remote notifications. Used from onboarding / profile.
    @MainActor
    static func requestAuthorizationAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional

        if settings.authorizationStatus == .notDetermined {
            do {
                authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("⚠️ PushRegistration: requestAuthorization failed: \(error.localizedDescription)")
                return false
            }
        }

        guard authorized else { return false }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    /// Store token from AppDelegate and upload when the user is signed in.
    static func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenString, forKey: pendingTokenKey)
        print("✅ PushRegistration: APNs device token received")

        Task {
            await uploadPendingTokenIfPossible()
        }
    }

    /// Retry upload after login if token arrived before auth was ready.
    static func retryPendingTokenUpload() async {
        await uploadPendingTokenIfPossible()
    }

    #if DEBUG
    /// Logs push pipeline hints for Xcode debugging (device token row, notify_push).
    static func logDiagnostics() async {
        guard let userId = SupabaseConfig.client.auth.currentUser?.id.uuidString else {
            print("🔔 PushDiagnostics: not signed in")
            return
        }
        struct ProfileRow: Decodable {
            let notify_push: Bool?
        }
        struct TokenRow: Decodable {
            let device_token: String
            let is_active: Bool?
        }
        do {
            let profiles: [ProfileRow] = try await SupabaseConfig.client
                .from("user_profiles")
                .select("notify_push")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            let tokens: [TokenRow] = try await SupabaseConfig.client
                .from("device_tokens")
                .select("device_token, is_active")
                .eq("user_id", value: userId)
                .eq("platform", value: "ios")
                .eq("is_active", value: true)
                .limit(3)
                .execute()
                .value
            let notifyPush = profiles.first?.notify_push ?? false
            print("🔔 PushDiagnostics: user=\(userId.prefix(8))… notify_push=\(notifyPush) active_ios_tokens=\(tokens.count) pendingLocalToken=\(UserDefaults.standard.string(forKey: pendingTokenKey) != nil)")
        } catch {
            print("🔔 PushDiagnostics: query failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Private

    private static func isNotificationAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    private static func uploadPendingTokenIfPossible() async {
        guard let tokenString = UserDefaults.standard.string(forKey: pendingTokenKey), !tokenString.isEmpty else {
            return
        }
        guard SupabaseConfig.client.auth.currentUser != nil else {
            #if DEBUG
            print("ℹ️ PushRegistration: token stored locally; will upload after sign-in")
            #endif
            return
        }

        do {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let osVersion = await MainActor.run { UIDevice.current.systemVersion }

            try await SupabaseConfig.client
                .rpc("register_device_token", params: [
                    "token": AnyJSON.string(tokenString),
                    "platform_type": AnyJSON.string("ios"),
                    "app_ver": AnyJSON.string(appVersion),
                    "os_ver": AnyJSON.string(osVersion)
                ])
                .execute()

            if let userId = SupabaseConfig.client.auth.currentUser?.id.uuidString {
                try await SupabaseConfig.client
                    .from("user_profiles")
                    .update(["notify_push": AnyJSON.bool(true)])
                    .eq("user_id", value: userId)
                    .execute()
            }

            print("✅ PushRegistration: Device token registered and notify_push enabled")
            #if DEBUG
            await logDiagnostics()
            #endif
        } catch {
            print("⚠️ PushRegistration: Could not register token: \(error.localizedDescription)")
        }
    }
}
