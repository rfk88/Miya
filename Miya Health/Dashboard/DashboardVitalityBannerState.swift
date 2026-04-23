//
//  DashboardVitalityBannerState.swift
//  Miya Health
//
//  Single source of truth for which vitality banner to show the logged-in user.
//  All predicates are pure (no side effects); notification scheduling lives in
//  DashboardVitalityLocalNotifications.swift.
//

import Foundation

// MARK: - Banner kind

/// Which primary vitality banner to show (mutually exclusive).
enum PrimaryVitalityBanner: Equatable {
    /// First-time ingest still in flight — tell the user to wait up to ~20 minutes.
    case initialIngest
    /// Ingest phase is over but the current user still has no usable vitality —
    /// prompt them to reconnect / resync their wearable.
    case resync
    /// No banner needed.
    case none
}

// MARK: - Evaluator

/// Pure value type: feed it the current dashboard state and read `.banner`.
/// All inputs come from `DashboardView` state; evaluator owns no async work.
struct DashboardVitalityBannerEvaluator {

    // MARK: Inputs

    /// Auth user ID for the logged-in account. If nil nothing is shown.
    let currentUserId: String?
    /// The row for the current user in the family members array (`isMe == true`).
    let me: FamilyMemberScore?
    /// True while a wearable baseline computation is actively running.
    let isWearableSyncing: Bool
    /// True when the baseline returned rows but not a complete snapshot yet.
    let isDataInsufficient: Bool
    /// True when the very first baseline has been marked complete in UserDefaults.
    /// Used to gate Banner A so it never appears again after the first successful ingest.
    let initialBaselineEverCompleted: Bool

    // MARK: Derived properties

    /// The current user has a valid, non-stale vitality score (matches FamilyMemberScore.hasScore semantics).
    var currentUserHasVitality: Bool {
        me?.hasScore == true
    }

    /// The baseline has been completed (score exists) for the current user THIS session
    /// OR was previously persisted as complete.
    var initialBaselineComplete: Bool {
        currentUserHasVitality || initialBaselineEverCompleted
    }

    /// True while we believe data is still being processed for the first time.
    /// Caps at "no longer initial ingest" once the baseline is complete.
    var isInInitialIngestPhase: Bool {
        guard currentUserId != nil else { return false }
        guard !initialBaselineComplete else { return false }
        // Still in ingest phase if syncing OR data is partially there but not yet a snapshot.
        return isWearableSyncing || isDataInsufficient
    }

    // MARK: Output

    /// Which banner to show. Priority: initialIngest > resync > none.
    var banner: PrimaryVitalityBanner {
        guard currentUserId != nil else { return .none }

        if isInInitialIngestPhase {
            return .initialIngest
        }

        // Member strip not hydrated yet — avoid flashing Banner B while `me` is still nil,
        // but only after we've persisted a completed baseline (otherwise see resync path below).
        if initialBaselineEverCompleted && me == nil {
            return .none
        }

        if !currentUserHasVitality {
            return .resync
        }

        return .none
    }
}

// MARK: - UserDefaults persistence (keyed per user)

/// Persistence keys and helpers for one-time / rate-limited banner state.
/// All keys include the userId to prevent state leaking across accounts.
enum VitalityBannerStorage {

    // MARK: Initial baseline completion flag

    private static func initialBaselineKey(userId: String) -> String {
        "miya.initialBaselineCompleted.\(userId.lowercased())"
    }

    static func hasCompletedInitialBaseline(userId: String?) -> Bool {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: initialBaselineKey(userId: uid))
    }

    static func markInitialBaselineCompleted(userId: String?) {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: initialBaselineKey(userId: uid))
    }

    // MARK: "Ready" local notification — fire at most once

    private static func readyNotifKey(userId: String) -> String {
        "miya.initialBaselineReadyNotified.\(userId.lowercased())"
    }

    static func hasNotifiedReady(userId: String?) -> Bool {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return true }
        return UserDefaults.standard.bool(forKey: readyNotifKey(userId: uid))
    }

    static func markNotifiedReady(userId: String?) {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: readyNotifKey(userId: uid))
    }

    // MARK: Resync local notification — rate-limited to once per day

    private static func lastResyncNotifKey(userId: String) -> String {
        "miya.lastMissingVitalityNotifDate.\(userId.lowercased())"
    }

    static func lastResyncNotifDate(userId: String?) -> Date? {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return nil }
        return UserDefaults.standard.object(forKey: lastResyncNotifKey(userId: uid)) as? Date
    }

    static func setLastResyncNotifDate(_ date: Date, userId: String?) {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        UserDefaults.standard.set(date, forKey: lastResyncNotifKey(userId: uid))
    }

    static func shouldSendResyncNotif(userId: String?) -> Bool {
        guard let last = lastResyncNotifDate(userId: userId) else { return true }
        let oneDayAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        return last < oneDayAgo
    }
}
