import Foundation
import RookSDK

/// Thin wrapper around the Rook SDK configuration and user binding.
/// NOTE: The SDK is configured with enableBackgroundSync=true, so once the user
/// is set and Apple Health permissions are granted, data should flow
/// automatically to the configured webhook.
final class RookService {
    static let shared = RookService()

    private init() {
        configure()
    }

    private func configure() {
        // TODO: move creds to secure config before production
        let clientUUID = "f60e5d66-1d2f-4e71-ba6c-f90c6c8ac2dc"
        let secretKey  = "kO6KBCELDtz4jBMWLrw63WFG8ppzSkQIND4E"

        RookConnectConfigurationManager.shared.setEnvironment(.sandbox)
        RookConnectConfigurationManager.shared.setConfiguration(
            clientUUID: clientUUID,
            secretKey: secretKey,
            enableBackgroundSync: true,
            enableEventsBackgroundSync: true
        )

        RookConnectConfigurationManager.shared.initRook()
        print("✅ RookService: Rook SDK initialized (sandbox)")

        #if DEBUG
        // Helpful when diagnosing whether uploads are occurring.
        RookConnectConfigurationManager.shared.setConsoleLogAvailable(true)
        #endif
    }

    /// Must be called with the authenticated user's ID before requesting permissions.
    /// This tells Rook which user is connecting their health data.
    /// CRITICAL: This userId MUST be the Miya auth UUID to ensure webhooks can map correctly.
    func setUserId(_ userId: String, completion: ((Bool) -> Void)? = nil) {
        print("🟢 RookService: Setting user ID: \(userId)")
        print("🔍 RookService: Verifying UUID format...")
        
        // Validate UUID format
        let uuidRegex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        let range = NSRange(location: 0, length: userId.utf16.count)
        if let regex = uuidRegex, regex.firstMatch(in: userId, range: range) != nil {
            print("✅ RookService: User ID is valid UUID format")
        } else {
            print("⚠️ RookService: User ID does NOT match UUID format - webhooks may fail to map!")
            print("   Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
            print("   Received: \(userId)")
        }

        RookConnectConfigurationManager.shared.updateUserId(userId) { result in
            switch result {
            case .success:
                print("✅ RookService: User ID set successfully with Rook SDK")
                print("ℹ️ RookService: Background sync will now automatically sync health data")
                print("ℹ️ RookService: Webhooks should receive client_user_id=\(userId)")
                completion?(true)
            case .failure(let error):
                print("❌ RookService: Failed to set user ID: \(error.localizedDescription)")
                print("❌ RookService: Webhooks will NOT be able to map to this user!")
                completion?(false)
            }
        }
    }

    /// Called after permissions are granted. With enableBackgroundSync: true configured,
    /// the SDK will synchronize in the background. We log here to make it explicit.
    func syncHealthData(backfillDays requestedDays: Int = 7) {
        // NOTE:
        // - Apple Health "pre-existing data" is limited; for many SDK flows this effectively caps at ~29 days.
        // - Rook also advises against very large backfills for daily + epoch volume.
        let maxSupportedDays = 29
        let days = min(requestedDays, maxSupportedDays)
        if requestedDays > maxSupportedDays {
            print("⚠️ RookService: Requested backfill \(requestedDays)d, capping to \(maxSupportedDays)d for Apple Health/Rook limits")
        }

        print("🟢 RookService: Enabling automatic sync + triggering manual backfill (\(days)d)")
        print("ℹ️ RookService: Expect webhook deliveries to Supabase if Rook is configured correctly")

        // Enable continuous upload of missing summaries whenever the app opens.
        RookConnectConfigurationManager.shared.enableSync()

        let summaryManager = RookSummaryManager()

        // First, try syncing any pending summaries the SDK already knows about.
        summaryManager.syncPendingSummaries { result in
            switch result {
            case .success(let ok):
                print("✅ RookService: syncPendingSummaries finished ok=\(ok)")
            case .failure(let error):
                print("❌ RookService: syncPendingSummaries error: \(error.localizedDescription)")
            }
        }
        
        // NOTE: Event backfill APIs are not available in the current Rook SDK version.
        // Workout events will still sync via background delivery (AppDelegate enables event background sync).
        // Then, explicitly request per-day sync for last N days (sleep + physical + body).
        let calendar = Calendar.current
        let summaryTypes: [SummaryTypeToUpload] = [.sleep, .physical, .body]

        func syncDay(offsetDaysAgo: Int) {
            guard offsetDaysAgo >= 0 else {
                print("✅ RookService: Manual backfill completed (\(days)d)")
                return
            }

            guard let date = calendar.date(byAdding: .day, value: -offsetDaysAgo, to: Date()) else {
                syncDay(offsetDaysAgo: offsetDaysAgo - 1)
                return
            }

            // Sync summaries for this date
            summaryManager.sync(date, summaryType: summaryTypes) { result in
                switch result {
                case .success(let ok):
                    print("✅ RookService: Synced summaries for \(date) ok=\(ok)")
                case .failure(let error):
                    print("❌ RookService: Sync summaries for \(date) failed: \(error.localizedDescription)")
                }
            }
            
            // Move to next day (serial to avoid hammering HealthKit).
            syncDay(offsetDaysAgo: offsetDaysAgo - 1)
        }

        syncDay(offsetDaysAgo: days - 1)
    }
}

