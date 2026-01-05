//
//  FamilyVitalitySnapshot.swift
//  Miya Health
//
//  Pure Swift-side computation model that derives meaningful, supportive insights
//  from current snapshot data only (no historical queries, no DB changes).
//
//  Language: Neutral, supportive, non-judgmental. No trend language, no comparisons, no blame.
//

import Foundation

// MARK: - Family Vitality Snapshot (Computed Insights)

/// Snapshot of family vitality with computed insights for coaching/support.
/// Derived from current member scores only (no historical data required).
struct FamilyVitalitySnapshot {
    /// Overall family state label (e.g., "rebuilding", "steady", "strong")
    let familyStateLabel: FamilyState
    
    /// How aligned the family is (tight = similar scores, wide = varied scores)
    let alignmentLevel: AlignmentLevel
    
    /// Pillar that needs the most attention (lowest family average)
    let focusPillar: VitalityPillar?
    
    /// Pillar that's the family's strength (highest family average)
    let strengthPillar: VitalityPillar?
    
    /// Members who might benefit from support (neutral, supportive framing)
    let supportMembers: [MemberInsight]
    
    /// Members doing well (neutral, celebratory framing)
    let celebrateMembers: [MemberInsight]
    
    /// Family average vitality score (0-100)
    let familyAverageScore: Int?
    
    /// Number of members included in calculations
    let membersIncluded: Int
    
    /// Total family members
    let membersTotal: Int

    // MARK: - Snapshot copy
    var headline: String {
        // No recent data
        if membersIncluded == 0 {
            return "No recent data yet. Connect wearables to start building your family score."
        }

        // Helper lookups
        let focus = focusPillar?.displayName ?? "Sleep"
        let strength = strengthPillar?.displayName ?? "wellness"

        func firstName(_ full: String) -> String {
            let parts = full.split(separator: " ")
            return parts.first.map(String.init) ?? full
        }

        // Two or more need support
        if supportMembers.count >= 2 {
            return "Two family members are below their personal target. Start with \(focus)."
        }

        // One needs support
        if supportMembers.count == 1, let first = supportMembers.first {
            return "\(firstName(first.memberName)) is below their personal target. Focus on \(focus) this week."
        }

        // At least one to celebrate
        if let firstCelebrate = celebrateMembers.first {
            return "Nice work — \(firstName(firstCelebrate.memberName)) is near their personal target. Keep momentum in \(strength)."
        }

        // Default: use state description
        return familyStateLabel.description
    }

    var subheadline: String? {
        guard membersIncluded > 0 else { return nil }
        return "Based on \(membersIncluded)/\(membersTotal) members with recent data."
    }

    // Help cards derived from the snapshot (no new calculations)
    let helpCards: [MemberHelpCard]
}

// MARK: - Supporting Types

/// Overall family vitality state (neutral, supportive labels)
enum FamilyState: String {
    case rebuilding = "Rebuilding"
    case steady = "Steady"
    case strong = "Strong"
    
    var description: String {
        switch self {
        case .rebuilding:
            return "Your family is focusing on building healthy habits together."
        case .steady:
            return "Your family is maintaining consistent wellness patterns."
        case .strong:
            return "Your family is showing strong vitality together."
        }
    }
}

/// Family alignment level (how similar member scores are)
enum AlignmentLevel: String {
    case tight = "Tight"
    case mixed = "Mixed"
    case wide = "Wide"
    
    var description: String {
        switch self {
        case .tight:
            return "Your family members have similar vitality levels."
        case .mixed:
            return "Your family has a mix of vitality levels."
        case .wide:
            return "Your family members have varied vitality levels."
        }
    }
}

/// Insight about a specific family member (neutral, supportive)
struct MemberInsight: Identifiable {
    let id: UUID
    let memberName: String
    let memberUserId: String?
    let insightType: InsightType
    let currentScore: Int
    let optimalScore: Int
    let progressScore: Int?   // 0–100 (capped) if available
    let message: String  // Neutral, supportive message
}

enum InsightType {
    case support  // Member might benefit from support
    case celebrate  // Member is doing well
}

// MARK: - Member Help Card
struct MemberHelpCard: Identifiable {
    let id = UUID()
    let memberId: String
    let memberName: String
    let focusPillar: VitalityPillar
    let title: String
    let recommendation: String
    let ctaLabel: String
}

// MARK: - Pillar Data (for family-level pillar analysis)

struct PillarData {
    let pillar: VitalityPillar
    let familyAverage: Int  // 0-100
    let memberScores: [Int]  // Per-member pillar scores (0-100)
}

// MARK: - Computation Engine

struct FamilyVitalitySnapshotEngine {
    
    /// Compute family vitality snapshot from current member data.
    /// - Parameters:
    ///   - members: Current member scores (must have currentScore, optimalScore, and pillar scores if available)
    ///   - familyAverage: Family average vitality score (from RPC or computed)
    ///   - pillarAverages: Family averages per pillar (sleep, movement, stress)
    ///   - membersTotal: Total family members (for context)
    /// - Returns: Computed snapshot with insights
    static func compute(
        members: [FamilyMemberScore],
        familyAverage: Int?,
        pillarAverages: [VitalityPillar: Int],  // e.g., [.sleep: 72, .movement: 86, .stress: 64]
        membersTotal: Int
    ) -> FamilyVitalitySnapshot {
        
        // Filter to members eligible for insight calculations:
        // - not pending (no onboarding/invite gating)
        // - has a real score
        // - score is fresh (updated within last 3 days; caller precomputes)
        // - has a meaningful optimal target (> 0) so we can compare current vs target
        let activeMembers = members.filter { !$0.isPending && $0.hasScore && $0.isScoreFresh && $0.optimalScore > 0 }
        let membersIncluded = activeMembers.count

        // If no eligible members, return a neutral snapshot:
        // - no support/celebrate messaging
        // - alignment is "tight" (no variance to compute)
        // - family state defaults to rebuilding (we're effectively waiting on fresh data)
        if activeMembers.isEmpty {
            return FamilyVitalitySnapshot(
                familyStateLabel: .rebuilding,
                alignmentLevel: .tight,
                focusPillar: pillarAverages.min(by: { $0.value < $1.value })?.key,
                strengthPillar: pillarAverages.max(by: { $0.value < $1.value })?.key,
                supportMembers: [],
                celebrateMembers: [],
                familyAverageScore: familyAverage,
                membersIncluded: 0,
                membersTotal: membersTotal,
                helpCards: []
            )
        }
        
        // 1. Family state label (based on family average)
        let familyState = computeFamilyState(familyAverage: familyAverage)
        
        // 2. Alignment level (based on variance across member scores)
        let alignment = computeAlignment(members: activeMembers)
        
        // 3. Focus pillar (lowest family average)
        let focusPillar = pillarAverages.min(by: { $0.value < $1.value })?.key
        
        // 4. Strength pillar (highest family average)
        let strengthPillar = pillarAverages.max(by: { $0.value < $1.value })?.key
        
        // 5. Support members (neutral, supportive framing)
        let supportMembers = computeSupportMembers(members: activeMembers)
        
        // 6. Celebrate members (neutral, celebratory framing)
        let celebrateMembers = computeCelebrateMembers(members: activeMembers)

        // 7. Member help cards from supportMembers (max 2)
        let helpCards = buildHelpCards(from: supportMembers, focusPillarFallback: focusPillar)
        
        return FamilyVitalitySnapshot(
            familyStateLabel: familyState,
            alignmentLevel: alignment,
            focusPillar: focusPillar,
            strengthPillar: strengthPillar,
            supportMembers: supportMembers,
            celebrateMembers: celebrateMembers,
            familyAverageScore: familyAverage,
            membersIncluded: membersIncluded,
            membersTotal: membersTotal,
            helpCards: helpCards
        )
    }
    
    // MARK: - Private Computation Helpers
    
    /// Compute family state label from average score (neutral, supportive).
    /// Thresholds: < 50 = rebuilding, 50-70 = steady, > 70 = strong
    private static func computeFamilyState(familyAverage: Int?) -> FamilyState {
        guard let avg = familyAverage else {
            return .rebuilding  // No data = rebuilding state
        }
        
        if avg < 50 {
            return .rebuilding
        } else if avg <= 70 {
            return .steady
        } else {
            return .strong
        }
    }
    
    /// Compute alignment level from variance in member scores.
    /// Uses coefficient of variation (CV = stddev / mean) to normalize for different score ranges.
    /// Thresholds: CV < 0.15 = tight, 0.15-0.30 = mixed, > 0.30 = wide
    private static func computeAlignment(members: [FamilyMemberScore]) -> AlignmentLevel {
        guard members.count >= 2 else {
            return .tight  // Single member or no members = tight by definition
        }
        
        let scores = members.map { Double($0.currentScore) }
        let mean = scores.reduce(0, +) / Double(scores.count)
        
        guard mean > 0 else {
            return .wide  // Zero mean = wide variance
        }
        
        let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
        let stddev = sqrt(variance)
        let coefficientOfVariation = stddev / mean
        
        if coefficientOfVariation < 0.15 {
            return .tight
        } else if coefficientOfVariation <= 0.30 {
            return .mixed
        } else {
            return .wide
        }
    }
    
    /// Identify members who might benefit from support (neutral, supportive framing).
    /// Primary rule: compare currentScore vs optimalScore only (no family comparisons; no trends).
    /// Language: Focus on support and opportunity, not deficit or blame.
    private static func computeSupportMembers(members: [FamilyMemberScore]) -> [MemberInsight] {
        return members.compactMap { member in
            // Prefer progressScore if available; fallback to current/optimal.
            let ratio: Double? = {
                if let p = member.progressScore { return Double(p) / 100.0 }
                guard member.optimalScore > 0 else { return nil }
                return Double(member.currentScore) / Double(member.optimalScore)
            }()
            guard let ratio else { return nil }
            
            // Support threshold: below ~75% of the member's personal target.
            // This is intentionally gentle and non-judgmental; it's just a signal for offering support.
            guard ratio < 0.75 else { return nil }
            
            // Neutral, supportive message (no blame, no comparison)
            let message: String
            if member.currentScore < 40 {
                message = "\(member.name) has room to build healthy habits."
            } else if member.currentScore < 60 {
                message = "\(member.name) is working on wellness goals."
            } else {
                message = "\(member.name) is making progress toward their vitality goals."
            }
            
            return MemberInsight(
                id: member.id,
                memberName: member.name,
                memberUserId: member.userId,
                insightType: .support,
                currentScore: member.currentScore,
                optimalScore: member.optimalScore,
                progressScore: member.progressScore,
                message: message
            )
        }
    }
    
    /// Identify members doing well (neutral, celebratory framing).
    /// Primary rule: compare currentScore vs optimalScore only (no family comparisons; no trends).
    /// Language: Focus on recognition and encouragement, not comparison.
    private static func computeCelebrateMembers(members: [FamilyMemberScore]) -> [MemberInsight] {
        return members.compactMap { member in
            let ratio: Double? = {
                if let p = member.progressScore { return Double(p) / 100.0 }
                guard member.optimalScore > 0 else { return nil }
                return Double(member.currentScore) / Double(member.optimalScore)
            }()
            guard let ratio else { return nil }
            
            // Celebrate threshold: at/above ~90% of the member's personal target.
            guard ratio >= 0.90 else { return nil }
            
            // Neutral, celebratory message (no comparison, no judgment)
            let message: String
            if member.currentScore >= 80 {
                message = "\(member.name) is showing strong vitality."
            } else if member.currentScore >= 70 {
                message = "\(member.name) is maintaining good wellness patterns."
            } else {
                message = "\(member.name) is making positive progress."
            }
            
            return MemberInsight(
                id: member.id,
                memberName: member.name,
                memberUserId: member.userId,
                insightType: .celebrate,
                currentScore: member.currentScore,
                optimalScore: member.optimalScore,
                progressScore: member.progressScore,
                message: message
            )
        }
    }
}

// Note: VitalityPillar is defined in ScoringSchema.swift and imported here

// MARK: - Help Cards Builder
private extension FamilyVitalitySnapshotEngine {
    static func buildHelpCards(
        from supportMembers: [MemberInsight],
        focusPillarFallback: VitalityPillar?
    ) -> [MemberHelpCard] {
        // Map supportMembers to (insight, gap)
        let scored: [(MemberInsight, Double)] = supportMembers.compactMap { insight in
            if let p = insight.progressScore {
                let gap = max(0.0, min(1.0, 1.0 - (Double(p) / 100.0)))
                return (insight, gap)
            }
            guard insight.optimalScore > 0 else { return nil }
            let gap = Double(insight.optimalScore - insight.currentScore) / Double(insight.optimalScore)
            return (insight, gap)
        }
        
        // Sort descending by gap (largest gap first), take up to 2
        let topTwo = scored.sorted { $0.1 > $1.1 }.prefix(2).map { $0.0 }
        
        func firstName(_ full: String) -> String {
            let parts = full.split(separator: " ")
            return parts.first.map(String.init) ?? full
        }
        
        func copy(for member: MemberInsight, pillar: VitalityPillar) -> MemberHelpCard {
            let name = firstName(member.memberName)
            switch pillar {
            case .sleep:
                return MemberHelpCard(
                    memberId: member.memberUserId ?? member.memberName,
                    memberName: member.memberName,
                    focusPillar: .sleep,
                    title: "Help \(name) with sleep",
                    recommendation: "Sleep is pulling \(name) below their target this week.",
                    ctaLabel: "Support bedtime consistency"
                )
            case .movement:
                return MemberHelpCard(
                    memberId: member.memberUserId ?? member.memberName,
                    memberName: member.memberName,
                    focusPillar: .movement,
                    title: "Help \(name) move more",
                    recommendation: "Low movement is holding \(name) back this week.",
                    ctaLabel: "Add a short daily walk"
                )
            case .stress:
                return MemberHelpCard(
                    memberId: member.memberUserId ?? member.memberName,
                    memberName: member.memberName,
                    focusPillar: .stress,
                    title: "Help \(name) recover",
                    recommendation: "Recovery signals are strained for \(name).",
                    ctaLabel: "Prioritize rest today"
                )
            }
        }
        
        return topTwo.map { insight in
            let pillar = focusPillarFallback ?? .sleep
            return copy(for: insight, pillar: pillar)
        }
    }
}

