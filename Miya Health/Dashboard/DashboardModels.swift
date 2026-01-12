import Foundation

// MARK: - VITALITY MODEL

// A single family member's score for a specific vitality factor
struct FamilyMemberScore: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let userId: String?         // auth.users.id (uuid string) when available
    let hasScore: Bool          // true only if a valid vitality_score_current exists (>= 0) AND profile row exists
    let isScoreFresh: Bool      // true only if vitality_score_updated_at is within last 3 days (UTC-ish)
    let isStale: Bool           // hasScore == true && isScoreFresh == false (displayable but excluded from family calcs/insights)
    let currentScore: Int       // 0–100 for UI; meaningful only if hasScore (freshness affects inclusion, not display)
    let optimalScore: Int       // UI; meaningful only if hasScore (0 if missing/invalid)
    /// Derived, capped 0–100 progress-to-optimal score (computed in DB via age×risk matrix).
    /// If nil, callers may fall back to current/optimal ratio for display only.
    let progressScore: Int?
    let inviteStatus: String?
    let onboardingType: String?
    let guidedSetupStatus: String?
    let isMe: Bool

    var ringProgress: Double {
        if let progressScore {
            return max(0.0, min(Double(progressScore) / 100.0, 1.0))
        }
        // Display-only fallback: if a member doesn't have a progress score yet, render relative to
        // current/optimal (or 100 if target missing) so the UI doesn't appear "empty".
        let denom = optimalScore > 0 ? optimalScore : 100
        let ratio = Double(currentScore) / Double(denom)
        return max(0.0, min(ratio, 1.0))
    }
    
    var isPending: Bool {
        // BUG 2 FIX: Guided members are pending until reviewed_complete
        if onboardingType == "Guided Setup" {
            #if DEBUG
            print("🔍 isPending check: name=\(name) status='\(guidedSetupStatus ?? "nil")' result=\(guidedSetupStatus != "reviewed_complete")")
            #endif
            return guidedSetupStatus != "reviewed_complete"
        }
        // Self Setup / normal: use invite status
        return (inviteStatus ?? "").lowercased() == "pending"
    }
}

// A single vitality factor in the dashboard (Sleep, Activity, Stress, Mindfulness)
struct VitalityFactor: Identifiable {
    let id = UUID()
    let name: String              // e.g. "Sleep"
    let iconName: String          // SF Symbol name
    let percent: Int              // Family-wide average 0–100
    let description: String       // Explanation text
    let actionPlan: [String]      // List of recommended actions
    let memberScores: [FamilyMemberScore]  // Individual scores for each family member
}

// MARK: - PILLAR DETAIL MODELS

enum TrendDirection {
    case up, down, stable
}

struct SubMetric {
    let name: String // "Steps"
    let value: String // "8,234 steps"
    let isBackfilled: Bool
    let sourceAgeInDays: Int?
}

struct PillarMemberDetail: Identifiable {
    let id = UUID()
    let member: FamilyMemberScore
    let todayScore: Int?
    let trendDirection: TrendDirection
    let trendPercentChange: Double?
    let subMetrics: [SubMetric]
    let hasBackfilledData: Bool
    let oldestSourceAgeInDays: Int?
}
