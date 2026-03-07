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
        RookConnectConfigurationManager.shared.setEnvironment(.sandbox)
        RookConnectConfigurationManager.shared.setConfiguration(
            clientUUID: RookConfig.clientUUID,
            secretKey: RookConfig.secretKey,
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

    // MARK: - Foreground Freshness Sync

    private static let lastSyncKey = "rook_last_foreground_sync"

    /// Call this every time the app comes to the foreground.
    /// Triggers a lightweight 3-day re-sync only if more than `cooldownHours` have elapsed
    /// since the last sync, so we never hammer the SDK on every app-switch.
    func syncIfStale(cooldownHours: Int = 6) {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        let shouldSync: Bool
        if let lastSync {
            shouldSync = Date().timeIntervalSince(lastSync) > Double(cooldownHours) * 3600
        } else {
            shouldSync = true
        }
        guard shouldSync else {
            print("ℹ️ RookService: Skipping foreground sync — last sync was less than \(cooldownHours)h ago")
            return
        }
        print("🔄 RookService: Foreground sync triggered (cooldown elapsed or first sync)")
        UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
        syncHealthData(backfillDays: 3)
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
        
        // Then, backfill serially with proper async/await to avoid overwhelming HealthKit
        Task {
            await performSerialBackfill(days: days, summaryManager: summaryManager)
        }
    }
    
    /// Performs serial backfill of health data, one day at a time with delays between requests.
    /// This prevents overwhelming HealthKit with simultaneous requests and ensures reliable data sync.
    private func performSerialBackfill(days: Int, summaryManager: RookSummaryManager) async {
        let calendar = Calendar.current
        let summaryTypes: [SummaryTypeToUpload] = [.sleep, .physical, .body]
        
        let startTime = Date()
        print("🔵 RookService: Starting serial backfill (\(days) days) at \(startTime)")
        
        var successCount = 0
        var failureCount = 0
        
        // Sync from oldest to newest (more intuitive logging)
        for offsetDaysAgo in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offsetDaysAgo, to: Date()) else {
                print("⚠️ RookService: Could not compute date for offset \(offsetDaysAgo), skipping")
                failureCount += 1
                continue
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateString = dateFormatter.string(from: date)
            
            let dayStartTime = Date()
            
            // Wait for this day to complete before starting next (BUG-017: pass result out, update counters on task executor only)
            let dayResult = await withCheckedContinuation { continuation in
                summaryManager.sync(date, summaryType: summaryTypes) { result in
                    let dayDuration = Date().timeIntervalSince(dayStartTime)
                    switch result {
                    case .success(let ok):
                        print("✅ RookService: Day \(offsetDaysAgo) (\(dateString)) synced successfully (ok=\(ok), duration=\(String(format: "%.2f", dayDuration))s)")
                    case .failure(let error):
                        print("❌ RookService: Day \(offsetDaysAgo) (\(dateString)) failed: \(error.localizedDescription) (duration=\(String(format: "%.2f", dayDuration))s)")
                    }
                    continuation.resume(returning: result)
                }
            }
            switch dayResult {
            case .success:
                successCount += 1
            case .failure:
                failureCount += 1
            }

            // Small delay between days to avoid hammering HealthKit
            // 500ms = 0.5 seconds, so 29 days takes ~14.5 seconds total
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        let totalDuration = Date().timeIntervalSince(startTime)
        print("✅ RookService: Serial backfill completed (\(days) days) - Success: \(successCount), Failed: \(failureCount), Total duration: \(String(format: "%.2f", totalDuration))s)")
    }
}

