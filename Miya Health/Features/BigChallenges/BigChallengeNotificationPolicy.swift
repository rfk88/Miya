import Foundation

/// Push rules for Phase B competitive challenges (see product plan). Server scheduler should enforce these.
enum BigChallengeNotificationPolicy {
    static let maxPushNotificationsPerActiveDay: Int = 2
    static let quietHoursStartHour: Int = 22 // 10pm local
    static let quietHoursEndHour: Int = 7 // 7am local, exclusive end for "safe" sends after 7

    /// Returns true if local clock falls in the no-send window [22:00, 07:00).
    static func isInQuietHours(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        if hour >= quietHoursStartHour { return true }
        if hour < quietHoursEndHour { return true }
        return false
    }
}
