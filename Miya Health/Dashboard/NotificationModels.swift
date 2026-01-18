import Foundation

// MARK: - Notification System Models
// Extracted from DashboardNotifications.swift for better compilation performance

// MARK: - Family Notification Item

struct FamilyNotificationItem: Identifiable {
    enum Kind {
        case trend(TrendInsight)
        case fallback(memberName: String, memberInitials: String, memberUserId: String?, pillar: VitalityPillar, title: String, body: String)
    }
    
    let id: String
    let kind: Kind
    let pillar: VitalityPillar
    let title: String
    let body: String
    let memberInitials: String
    let memberName: String
    
    /// Extract member user ID from the item (for history fetching)
    var memberUserId: String? {
        switch kind {
        case .trend(let insight):
            return insight.memberUserId
        case .fallback(_, _, let userId, _, _, _):
            return userId
        }
    }
    
    /// Extract debug why text if available
    var debugWhy: String? {
        switch kind {
        case .trend(let insight):
            return insight.debugWhy
        case .fallback:
            return nil
        }
    }
    
    /// Extract window days if available (for defaulting segmented control)
    var triggerWindowDays: Int? {
        switch kind {
        case .trend(let insight):
            return insight.windowDays
        case .fallback:
            return nil
        }
    }
    
    static func build(
        snapshot: FamilyVitalitySnapshot,
        trendInsights: [TrendInsight],
        trendCoverage: TrendCoverageStatus?,
        factors: [VitalityFactor],
        members: [FamilyMemberScore]
    ) -> [FamilyNotificationItem] {
        func memberPillarScore(userId: String?, factorName: String) -> Int? {
            guard let uid = userId?.lowercased() else { return nil }
            let f = factors.first(where: { $0.name.lowercased() == factorName.lowercased() })
            return f?.memberScores.first(where: { $0.userId?.lowercased() == uid })?.currentScore
        }
        
        func memberPillarScore(userId: String?, pillar: VitalityPillar) -> Int? {
            switch pillar {
            case .sleep: return memberPillarScore(userId: userId, factorName: "Sleep")
            case .movement: return memberPillarScore(userId: userId, factorName: "Activity")
            case .stress: return memberPillarScore(userId: userId, factorName: "Recovery")
            }
        }
        
        /// If a member's current pillar score is strong, suppress negative trend alerts (they've likely already recovered).
        /// For all pillars (Sleep, Movement, Stress): HIGHER score = BETTER (better sleep, more movement, better stress management).
        /// If current score >= 85, the member is doing well NOW, so we suppress alerts about past problems.
        func isStillRelevantNegativeAlert(memberUserId: String?, pillar: VitalityPillar) -> Bool {
            guard let current = memberPillarScore(userId: memberUserId, pillar: pillar) else {
                #if DEBUG
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=nil → KEEP (no score available)")
                #endif
                return true
            }
            // Only suppress if current pillar score is very strong (>= 85), indicating full recovery.
            // Lower threshold (75) was too aggressive and filtered out valid trend alerts.
            let shouldKeep = current < 85
            #if DEBUG
            if shouldKeep {
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=\(current) → KEEP (score < 85, alert still relevant)")
            } else {
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=\(current) → FILTER OUT (score >= 85, member has recovered)")
            }
            #endif
            return shouldKeep
        }
        
        // 1) Prefer true trend insights when available
        if trendCoverage?.hasMinimumCoverage == true, !trendInsights.isEmpty {
            #if DEBUG
            print("🔔 Building notifications from \(trendInsights.count) trend insights")
            #endif
            let filtered = trendInsights
                .filter { !$0.memberName.isEmpty }
            #if DEBUG
            print("🔔 After name filter: \(filtered.count) insights")
            #endif
            // Suppress stale negative alerts if the member is now doing well in that pillar.
            let relevanceFiltered = filtered.filter { ins in
                    switch ins.severity {
                    case .attention, .watch:
                        let keep = isStillRelevantNegativeAlert(memberUserId: ins.memberUserId, pillar: ins.pillar)
                        #if DEBUG
                        if !keep {
                            let currentScore = memberPillarScore(userId: ins.memberUserId, pillar: ins.pillar) ?? 0
                            print("🔔 Filtered out: \(ins.title) (current \(ins.pillar.displayName) score=\(currentScore) >= 85, member has recovered from past issue)")
                        }
                        #endif
                        return keep
                    case .celebrate:
                        return true
                    }
                }
            #if DEBUG
            print("🔔 After relevance filter: \(relevanceFiltered.count) insights")
            #endif
            let final = relevanceFiltered.prefix(5).map { ins in
                    let initials = makeInitials(from: ins.memberName)
                    return FamilyNotificationItem(
                        id: ins.id.uuidString,
                        kind: .trend(ins),
                        pillar: ins.pillar,
                        title: ins.title,
                        body: ins.body,
                        memberInitials: initials,
                        memberName: ins.memberName
                    )
                }
            #if DEBUG
            print("🔔 Final notification count: \(final.count)")
            for item in final {
                print("  - \(item.title)")
            }
            #endif
            return final
        }
        
        // 2) Fallback: derive a pillar per member from their pillar scores (Sleep / Activity / Stress)
        // This avoids hardcoding everything to the family's focus pillar.
        let others = members.filter { !$0.isMe && !$0.isPending && $0.hasScore && $0.isScoreFresh }
        guard !others.isEmpty else { return [] }
        
        func lowestPillar(for member: FamilyMemberScore) -> (pillar: VitalityPillar, score: Int)? {
            let sleep = memberPillarScore(userId: member.userId, factorName: "Sleep")
            let movement = memberPillarScore(userId: member.userId, factorName: "Activity")
            let stress = memberPillarScore(userId: member.userId, factorName: "Recovery")
            let options: [(VitalityPillar, Int?)] = [(.sleep, sleep), (.movement, movement), (.stress, stress)]
            let present = options.compactMap { (pillar, value) -> (VitalityPillar, Int)? in
                value.map { (pillar, $0) }
            }
            guard let minPair = present.min(by: { $0.1 < $1.1 }) else { return nil }
            return (minPair.0, minPair.1)
        }
        
        return others.compactMap { m in
            guard let lp = lowestPillar(for: m) else { return nil }
            
            // Relevance gate (fallback): only create a notification if there is an actual issue right now.
            // This prevents "Terrible3 · Stress" from showing when all scores are 90+.
            let currentVsOptimalOK: Bool = (m.optimalScore > 0) ? (Double(m.currentScore) / Double(m.optimalScore) >= 0.90) : (m.currentScore >= 80)
            let pillarOK: Bool = lp.score >= 75
            if currentVsOptimalOK && pillarOK {
                return nil
            }
            
            let initials = m.initials
            let firstName = m.name.split(separator: " ").first.map(String.init) ?? m.name
            let title: String
            let body: String
            switch lp.pillar {
            case .sleep:
                title = "\(firstName) · Sleep"
                body = "Sleep is the biggest drag on \(firstName)'s vitality right now. A small bedtime consistency reset can help."
            case .movement:
                title = "\(firstName) · Movement"
                body = "Movement is trending low for \(firstName). A simple daily steps goal is a good first unlock."
            case .stress:
                title = "\(firstName) · Stress"
                body = "\(firstName)'s recovery signals look strained lately. Prioritizing rest and calm minutes can help."
            }
            return FamilyNotificationItem(
                id: (m.userId ?? m.name) + "-" + lp.pillar.rawValue,
                kind: .fallback(memberName: m.name, memberInitials: initials, memberUserId: m.userId, pillar: lp.pillar, title: title, body: body),
                pillar: lp.pillar,
                title: title,
                body: body,
                memberInitials: initials,
                memberName: m.name
            )
        }
        .prefix(3)
        .map { $0 }
    }
    
    private static func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.dropFirst().first?.prefix(1) ?? ""
        let combined = String(first + second)
        return combined.isEmpty ? String(name.prefix(2)).uppercased() : combined.uppercased()
    }
}

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let timestamp: Date = Date()
    
    enum MessageRole {
        case miya    // AI messages
        case user    // User messages
    }
}

struct PillPrompt: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let category: PromptCategory
    
    enum PromptCategory {
        case general          // Any suggested question
        case reachOut         // Opens reach-out sheet
        case dayByDay         // Day-by-day specific request
    }
}
