import Foundation

// MARK: - Notification System Models
// Extracted from DashboardNotifications.swift for better compilation performance

// MARK: - Family Notification Item

/// Care loop state for server alerts. nil = new (no action taken yet).
enum CareState: String, Codable {
    case monitoring
    case improving
    case resolved
    case archived
}

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
    
    /// Care loop state (server alerts only). nil = new.
    let careState: CareState?
    /// Who last acted (for "Sent by [Name]").
    let actedByUserId: String?
    let actedAt: Date?
    let followUpDueDate: Date?
    /// Miya's outcome or next-step message.
    let outcomeMessage: String?
    let cycleCount: Int
    /// Last intervention type (challenge, reach_out, etc.) for gating CTAs.
    let lastInterventionType: String?
    /// Per-user challenge status for this alert (from challenge_challengers). nil, "pending_invite", "active", "completed_failed", "snoozed".
    let myChallengeStatus: String?
    
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
    
    /// True when this notification was produced by the server-side pattern alert engine
    /// (i.e. has an alertStateId and supports Arlo chat). False for locally-computed
    /// trend insights and fallback items.
    var isServerAlert: Bool {
        guard let why = debugWhy else { return false }
        return why.contains("serverPattern") && why.contains("alertStateId=")
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
    
    /// Parsed duration (in days) that the underlying pattern/trend has been active,
    /// derived from debugWhy or the title/body text. Returns nil if no duration
    /// can be confidently parsed.
    var patternDurationDays: Int? {
        switch kind {
        case .fallback:
            return nil
        case .trend(let insight):
            // 1) Prefer parsing from debugWhy when available.
            if let debug = insight.debugWhy {
                // Server pattern: "level=7"
                if let range = debug.range(of: #"level=(\d+)"#, options: .regularExpression) {
                    let match = debug[range]
                        .components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .compactMap { Int($0) }
                        .first
                    if let days = match {
                        return days
                    }
                }
                // Client trend: "consecutiveDays: 7" or "consecutiveDays=7"
                if let range = debug.range(of: #"consecutiveDays[\":\s=]+(\d+)"#, options: .regularExpression) {
                    let match = debug[range]
                        .components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .compactMap { Int($0) }
                        .first
                    if let days = match {
                        return days
                    }
                }
            }
            
            // 2) Fallback: look for "last 7d" / "(last 7d)" patterns in title/body.
            let textToSearch = title + " " + body
            if let range = textToSearch.range(of: #"last (\d+)d"#, options: .regularExpression) {
                let match = textToSearch[range]
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                    .first
                if let days = match {
                    return days
                }
            }
            
            // 3) If we still can't parse, return nil so callers can omit the chip.
            return nil
        }
    }
    
    /// Convenience token like "3d" derived from patternDurationDays.
    var patternDurationToken: String? {
        guard let days = patternDurationDays, days > 0 else {
            return nil
        }
        return "\(days)d"
    }
    
    /// Single-line display for cards: "Pillar is X% below/above Name's baseline (3d)" when body has that pattern, else title.
    var displayLine: String {
        switch kind {
        case .fallback(_, _, _, _, let title, _):
            return title
        case .trend(let insight):
            let b = insight.body
            let hasIs = b.contains(" is ")
            let hasBelow = b.contains(" below ")
            let hasAbove = b.contains(" above ")
            let hasBaseline = b.contains("'s baseline")
            guard hasIs, (hasBelow || hasAbove), hasBaseline,
                  let isRange = b.range(of: " is ") else {
                return insight.title
            }
            // Stat part: substring after " is ", strip " (last …)" and trim
            var statPart = String(b[isRange.upperBound...])
            if let lastRange = statPart.range(of: " (last ") {
                statPart = String(statPart[..<lastRange.lowerBound])
            }
            statPart = statPart.trimmingCharacters(in: .whitespacesAndNewlines)
            // Metric from title: strip " below baseline" / " above baseline"
            let metric = insight.title
                .replacingOccurrences(of: " below baseline", with: "")
                .replacingOccurrences(of: " above baseline", with: "")
                .trimmingCharacters(in: .whitespaces)
            // Trigger from body: " (last 3d)." → second line "(3d)"
            var triggerSuffix = ""
            if let lastPrefix = b.range(of: " (last "),
               let closeParen = b[lastPrefix.upperBound...].firstIndex(of: ")") {
                let token = String(b[lastPrefix.upperBound..<closeParen]).trimmingCharacters(in: .whitespaces)
                if !token.isEmpty {
                    triggerSuffix = "\n(\(token))"
                }
            }
            return "\(metric) is \(statPart)\(triggerSuffix)"
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
                    @unknown default:
                        // Unknown severity: keep so new types are not silently dropped (BUG-028).
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
                        memberName: ins.memberName,
                        careState: nil,
                        actedByUserId: nil,
                        actedAt: nil,
                        followUpDueDate: nil,
                        outcomeMessage: nil,
                        cycleCount: 0,
                        lastInterventionType: nil,
                        myChallengeStatus: nil
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
                memberName: m.name,
                careState: nil,
                actedByUserId: nil,
                actedAt: nil,
                followUpDueDate: nil,
                outcomeMessage: nil,
                cycleCount: 0,
                lastInterventionType: nil,
                myChallengeStatus: nil
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

extension FamilyNotificationItem {
    /// Enforces one notification per member + pillar + timeframe for UI display.
    /// Keeps a deterministic representative item for each key.
    static func dedupedByMemberPillarWindow(_ items: [FamilyNotificationItem]) -> [FamilyNotificationItem] {
        guard !items.isEmpty else { return [] }

        struct DedupeKey: Hashable {
            let memberKey: String
            let pillarKey: String
            let windowKey: Int
        }

        func severityPriority(_ notification: FamilyNotificationItem) -> Int {
            switch notification.kind {
            case .trend(let insight):
                switch insight.severity {
                case .attention: return 3
                case .watch: return 2
                case .celebrate: return 1
                @unknown default:
                    return 2 // Treat unknown like watch for ordering (BUG-028).
                }
            case .fallback:
                return 3
            }
        }

        // Deterministic order: severity first, then id.
        let ranked = items.sorted { lhs, rhs in
            let l = severityPriority(lhs)
            let r = severityPriority(rhs)
            if l != r { return l > r }
            return lhs.id < rhs.id
        }

        var seen: Set<DedupeKey> = []
        var out: [FamilyNotificationItem] = []

        for item in ranked {
            let memberKey = (item.memberUserId ?? item.memberName).lowercased()
            let key = DedupeKey(
                memberKey: memberKey,
                pillarKey: item.pillar.rawValue,
                windowKey: item.triggerWindowDays ?? 0
            )

            if seen.insert(key).inserted {
                out.append(item)
            }
        }

        return out
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
