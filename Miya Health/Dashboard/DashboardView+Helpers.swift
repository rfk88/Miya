import SwiftUI
import Supabase

// MARK: - DashboardView Helpers Extension
// Extracted from DashboardView.swift for better organization and compilation performance

extension DashboardView {
    // MARK: - Guided setup status actions (manual nudges; no background logic)
    
    enum GuidedAdminAction {
        case resendInvite
        case startGuidedSetup
        case remindMember
        case viewProfile
    }
    
    internal func handleGuidedStatusAction(member: FamilyMemberRecord, action: GuidedAdminAction) {
        switch action {
        case .resendInvite:
            shareText = inviteShareText(for: member, intent: "Invite not accepted")
            isShareSheetPresented = true
        case .remindMember:
            shareText = inviteShareText(for: member, intent: "Reminder to review")
            isShareSheetPresented = true
        case .startGuidedSetup:
            // Navigation occurs via NavigationLink in the row.
            break
        case .viewProfile:
            // Navigation occurs via NavigationLink in the row when available.
            break
        }
    }
    
    internal func inviteShareText(for member: FamilyMemberRecord, intent: String) -> String {
        let code = member.inviteCode ?? ""
        return """
        \(intent)
        
        Join the \(resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName) Family on Miya Health
        Invite for: \(member.firstName)
        Code: \(code)
        """
    }
    
    // MARK: - Persistence for dismissed guided members
    
    internal func dismissedKey(for userId: String) -> String {
        "dismissedGuidedMembers:\(userId)"
    }
    
    internal func loadDismissedGuidedMembers(for userId: String) {
        let key = dismissedKey(for: userId)
        if let data = UserDefaults.standard.array(forKey: key) as? [String] {
            dismissedGuidedMemberIds = Set(data)
        }
    }
    
    // MARK: - Missing Wearable Detection
    
    internal func detectMissingWearableData() async {
        let now = Date()
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        func parseISODate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return isoFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        
        let snoozedUntil = loadMissingWearableSnoozedUntil()
        func isSnoozed(notificationId: String) -> Bool {
            guard let until = snoozedUntil[notificationId] else { return false }
            return until > now
        }
        
        var notifications: [MissingWearableNotification] = []
        
        for member in familyMembers where !member.isMe && !member.isPending {
            guard let userId = member.userId else { continue }
            
            do {
                let supabase = SupabaseConfig.client
                struct ProfileRow: Decodable {
                    let vitality_score_updated_at: String?
                }
                
                let profiles: [ProfileRow] = try await supabase
                    .from("user_profiles")
                    .select("vitality_score_updated_at")
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
                
                guard let profile = profiles.first,
                      let updatedAtStr = profile.vitality_score_updated_at,
                      let updatedAt = parseISODate(updatedAtStr) else {
                    if member.hasScore && member.isStale {
                        let notificationId = "missing_wearable_\(userId)_7"
                        if !dismissedMissingWearableIds.contains(notificationId), !isSnoozed(notificationId: notificationId) {
                            notifications.append(MissingWearableNotification(
                                id: notificationId,
                                memberName: member.name,
                                memberUserId: userId,
                                memberInitials: member.initials,
                                daysStale: 7,
                                lastUpdated: nil
                            ))
                        }
                    }
                    continue
                }
                
                let daysStale = Calendar.current.dateComponents([.day], from: updatedAt, to: now).day ?? 0
                
                if daysStale >= 3 {
                    let notificationDays = daysStale >= 7 ? 7 : 3
                    let notificationId = "missing_wearable_\(userId)_\(notificationDays)"
                    
                    if !dismissedMissingWearableIds.contains(notificationId), !isSnoozed(notificationId: notificationId) {
                        if daysStale >= 7 {
                            notifications = notifications.filter { $0.id != "missing_wearable_\(userId)_3" }
                            notifications.append(MissingWearableNotification(
                                id: notificationId,
                                memberName: member.name,
                                memberUserId: userId,
                                memberInitials: member.initials,
                                daysStale: 7,
                                lastUpdated: updatedAt
                            ))
                        } else if daysStale >= 3 {
                            notifications.append(MissingWearableNotification(
                                id: notificationId,
                                memberName: member.name,
                                memberUserId: userId,
                                memberInitials: member.initials,
                                daysStale: 3,
                                lastUpdated: updatedAt
                            ))
                        }
                    }
                }
            } catch {
                print("⚠️ Dashboard: Failed to check missing wearable data for \(member.name): \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            missingWearableNotifications = notifications
        }
    }
    
    // MARK: - Missing Wearable Dismiss Persistence
    
    private static let missingWearableSnoozedUntilKey = "missingWearableSnoozedUntil"
    
    /// Returns notification ids that are currently snoozed (snoozed-until date > now).
    /// Expired entries are removed from storage so the dict does not grow forever.
    internal func loadMissingWearableSnoozedUntil() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: Self.missingWearableSnoozedUntilKey) as? [String: String] ?? [:]
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var result: [String: Date] = [:]
        var toPersist: [String: String] = [:]
        let now = Date()
        for (id, dateStr) in raw {
            guard let date = isoFmt.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr) else { continue }
            if date > now {
                result[id] = date
                toPersist[id] = dateStr
            }
        }
        if toPersist.count != raw.count {
            UserDefaults.standard.set(toPersist, forKey: Self.missingWearableSnoozedUntilKey)
        }
        return result
    }
    
    /// Snooze a missing-wearable notification for the given number of days.
    /// Persists the snoozed-until date and removes the notification from the in-memory list.
    internal func snoozeMissingWearableNotification(id: String, forDays days: Int) {
        let now = Date()
        guard let until = Calendar.current.date(byAdding: .day, value: days, to: now) else { return }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let raw = UserDefaults.standard.dictionary(forKey: Self.missingWearableSnoozedUntilKey) as? [String: String] ?? [:]
        var updated = raw
        updated[id] = isoFmt.string(from: until)
        UserDefaults.standard.set(updated, forKey: Self.missingWearableSnoozedUntilKey)
        missingWearableNotifications = missingWearableNotifications.filter { $0.id != id }
    }
    
    internal func dismissedMissingWearableKey(for userId: String) -> String {
        "dismissedMissingWearable:\(userId)"
    }
    
    internal func loadDismissedMissingWearable(for userId: String) {
        let key = dismissedMissingWearableKey(for: userId)
        if let data = UserDefaults.standard.array(forKey: key) as? [String] {
            dismissedMissingWearableIds = Set(data)
        }
    }
    
    internal func persistDismissedMissingWearable(for userId: String) {
        let key = dismissedMissingWearableKey(for: userId)
        UserDefaults.standard.set(Array(dismissedMissingWearableIds), forKey: key)
    }
    
    internal func dismissMissingWearableNotification(id: String) {
        dismissedMissingWearableIds.insert(id)
        if let userId = currentUserIdString {
            persistDismissedMissingWearable(for: userId)
        }
        missingWearableNotifications = missingWearableNotifications.filter { $0.id != id }
    }
    
    // MARK: - WhatsApp/iMessage Helpers
    
    internal func openWhatsApp(with message: String) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "whatsapp://send?text=\(encoded)") {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    DispatchQueue.main.async {
                        if let appStoreURL = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997") {
                            UIApplication.shared.open(appStoreURL)
                        }
                    }
                }
            }
        }
    }
    
    /// Opens the Messages app with pre-filled body (user can send as iMessage or SMS depending on recipient).
    internal func openMessages(with message: String) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "sms:&body=\(encoded)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    internal func persistDismissedGuidedMembers(for userId: String) {
        let key = dismissedKey(for: userId)
        UserDefaults.standard.set(Array(dismissedGuidedMemberIds), forKey: key)
    }



}