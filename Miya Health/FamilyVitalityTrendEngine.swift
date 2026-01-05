//
//  FamilyVitalityTrendEngine.swift
//  Miya Health
//
//  Trend detection engine using stored vitality_scores history.
//  Generates member-level, actionable insights based on point patterns.
//

import Foundation

// MARK: - Trend Insight Model

/// Severity levels for trend insights
enum TrendSeverity: String {
    case attention   // Needs action now
    case watch       // Worth monitoring
    case celebrate   // Positive trend
}

/// Coverage status for a member/window
struct TrendCoverageStatus {
    let windowDays: Int
    let daysAvailable: Int
    let missingDays: Int
    let requiredDaysForAnyInsight: Int
    let needMoreDataDays: Int
    let hasMinimumCoverage: Bool
}

// MARK: - Family Recommendations (actionable, pillar-specific)

struct FamilyRecommendationRow: Identifiable {
    let id = UUID()
    let memberUserId: String?
    let pillar: VitalityPillar
    let text: String
}

struct FamilyRecommendationEngine {
    /// Build up to 2 recommendation rows based on coverage + trends + snapshot support members.
    /// Rules:
    /// - If coverage.hasMinimumCoverage == false -> []
    /// - Require at least one negative (non-celebrate) trend insight to emit any recommendations.
    /// - Prioritize supportMembers first, then negative trend insights.
    /// - Pillar from trend insight if available for that member, else fallback to snapshot.focusPillar (or .sleep).
    static func build(
        snapshot: FamilyVitalitySnapshot,
        trendInsights: [TrendInsight],
        coverage: TrendCoverageStatus?
    ) -> [FamilyRecommendationRow] {
        guard coverage?.hasMinimumCoverage == true else { return [] }
        
        // Negative (non-celebrate) insights only
        let negativeInsights = trendInsights.filter { $0.severity != .celebrate }
        guard !negativeInsights.isEmpty else { return [] }
        
        // Build candidate member IDs/names from supportMembers first
        var orderedMemberIds: [String?] = []
        var seen: Set<String> = []
        
        func appendMember(_ memberId: String?) {
            let key = memberId?.lowercased() ?? ""
            if !seen.contains(key) {
                seen.insert(key)
                orderedMemberIds.append(memberId)
            }
        }
        
        for m in snapshot.supportMembers {
            appendMember(m.memberUserId)
        }
        for ins in negativeInsights {
            appendMember(ins.memberUserId)
        }
        
        func firstName(_ full: String) -> String {
            let parts = full.split(separator: " ")
            return parts.first.map(String.init) ?? full
        }
        
        func recText(name: String, pillar: VitalityPillar) -> String {
            switch pillar {
            case .sleep:
                return "\(name) — Tonight: 30-minute wind-down + consistent bedtime. Your sleep trend is slipping."
            case .movement:
                return "\(name) — Today: 10-minute walk after a meal. Movement has been low lately."
            case .stress:
                return "\(name) — Today: 3 minutes of slow breathing (4s in, 6s out). Recovery looks strained."
            }
        }
        
        // Build a lookup for member names from supportMembers and trend insights
        var nameByUserId: [String?: String] = [:]
        for m in snapshot.supportMembers {
            nameByUserId[m.memberUserId] = m.memberName
        }
        for ins in negativeInsights {
            // Derive name from title "Name · Pillar"
            let parts = ins.title.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            if let name = parts.first, !name.isEmpty {
                nameByUserId[ins.memberUserId] = name
            }
        }
        
        // Pillar lookup from negative insights
        let pillarByUserId: [String?: VitalityPillar] = {
            var dict: [String?: VitalityPillar] = [:]
            for ins in negativeInsights {
                dict[ins.memberUserId] = ins.pillar
            }
            return dict
        }()
        
        let fallbackPillar: VitalityPillar = snapshot.focusPillar ?? .sleep
        
        var rows: [FamilyRecommendationRow] = []
        for memberId in orderedMemberIds {
            if rows.count >= 2 { break }
            
            let pillar = pillarByUserId[memberId] ?? fallbackPillar
            let name = nameByUserId[memberId].map { firstName($0) } ?? "This member"
            let text = recText(name: name, pillar: pillar)
            
            rows.append(FamilyRecommendationRow(
                memberUserId: memberId,
                pillar: pillar,
                text: text
            ))
        }
        
        return rows
    }
}

/// A single trend insight for a family member
struct TrendInsight: Identifiable {
    let id = UUID()
    let memberName: String
    let memberUserId: String
    let pillar: VitalityPillar
    let severity: TrendSeverity
    let title: String           // Short headline
    let body: String            // One sentence explanation
    let debugWhy: String?       // Debug info (optional)
    let windowDays: Int
    let requiredDays: Int
    let missingDays: Int
    let confidence: Double
    
    /// CTA label for the insight
    var ctaLabel: String {
        "View \(firstName)'s \(pillar.displayName.lowercased())"
    }
    
    private var firstName: String {
        let parts = memberName.split(separator: " ")
        return parts.first.map(String.init) ?? memberName
    }
}

// MARK: - Trend Engine

struct FamilyVitalityTrendEngine {
    
    typealias DailyScore = DataManager.DailyVitalityScore
    
    /// Minimum days of data required to generate trends
    static let minimumDaysRequired = 5
    static let requiredMinDaysForAnyInsight = 7
    static let requiredConsecutiveForStreak = 3
    static let windowDays = 21

    // MARK: - Windowing Helper (UTC, last 21 days)
    private static func filterToWindow(_ scores: [DailyScore]) -> [DailyScore] {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        
        // Anchor "today" to UTC midnight
        let today = Date()
        guard let todayUTC = Calendar(identifier: .gregorian).date(bySettingHour: 0, minute: 0, second: 0, of: today, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .backward) else {
            return scores
        }
        guard let startUTC = Calendar(identifier: .gregorian).date(byAdding: .day, value: -windowDays + 1, to: todayUTC) else {
            return scores
        }
        
        return scores.filter { score in
            guard let d = df.date(from: score.dayKey) else { return false }
            return d >= startUTC && d <= todayUTC
        }
    }
    
    /// Compute trend insights from member data and their score history.
    /// - Parameters:
    ///   - members: Family members with current scores
    ///   - history: Dictionary of userId → [DailyVitalityScore] (ascending by date)
    /// - Returns: (insights, coverage) where coverage reflects last 21d availability
    static func computeTrends(
        members: [FamilyMemberScore],
        history: [String: [DailyScore]]
    ) -> (insights: [TrendInsight], coverage: TrendCoverageStatus) {
        
        // Only analyze active, fresh members
        let eligibleMembers = members.filter { member in
            !member.isPending && member.hasScore && member.isScoreFresh && member.userId != nil
        }
        
        print("🔍 TrendEngine: Starting analysis")
        print("  - Total members: \(members.count)")
        print("  - Eligible members: \(eligibleMembers.count)")
        print("  - History keys: \(history.keys.joined(separator: ", "))")
        
        var allInsights: [TrendInsight] = []
        var perMemberCoverage: [(member: FamilyMemberScore, coverage: TrendCoverageStatus, longestStreak: Int)] = []
        
        for member in eligibleMembers {
            guard let userIdRaw = member.userId, !userIdRaw.isEmpty else {
                print("  ⚠️ Member '\(member.name)' skipped: userId is nil/empty")
                continue
            }
            let userId = userIdRaw.lowercased()
            
            guard let scoresAll = history[userId] else {
                print("  ⚠️ Member '\(member.name)' (userId: \(userId)) skipped: no history found")
                let cov = TrendCoverageStatus(
                    windowDays: windowDays,
                    daysAvailable: 0,
                    missingDays: windowDays,
                    requiredDaysForAnyInsight: requiredMinDaysForAnyInsight,
                    needMoreDataDays: requiredMinDaysForAnyInsight,
                    hasMinimumCoverage: false
                )
                perMemberCoverage.append((member, cov, 0))
                continue
            }
            
            // Windowed scores (last 21 days only, UTC)
            let scores = filterToWindow(scoresAll)
            if scores.isEmpty {
                print("  ⚠️ Member '\(member.name)' (userId: \(userId)) skipped: 0 rows in window")
                let cov = TrendCoverageStatus(
                    windowDays: windowDays,
                    daysAvailable: 0,
                    missingDays: windowDays,
                    requiredDaysForAnyInsight: requiredMinDaysForAnyInsight,
                    needMoreDataDays: requiredMinDaysForAnyInsight,
                    hasMinimumCoverage: false
                )
                perMemberCoverage.append((member, cov, 0))
                continue
            }
            
            let dayKeys = Array(Set(scores.map { $0.dayKey }))
            let daysAvailable = dayKeys.count
            let cov = TrendCoverageStatus(
                windowDays: windowDays,
                daysAvailable: daysAvailable,
                missingDays: max(0, windowDays - daysAvailable),
                requiredDaysForAnyInsight: requiredMinDaysForAnyInsight,
                needMoreDataDays: max(0, requiredMinDaysForAnyInsight - daysAvailable),
                hasMinimumCoverage: daysAvailable >= requiredMinDaysForAnyInsight
            )
            
            let longestStreak = longestConsecutiveStreak(dayKeys: dayKeys)
            perMemberCoverage.append((member, cov, longestStreak))
            
            print("  • \(member.name): days=\(daysAvailable) missing=\(cov.missingDays) needMore=\(cov.needMoreDataDays) hasMin=\(cov.hasMinimumCoverage) longestStreak=\(longestStreak)")
            
            // Per-member gating
            if daysAvailable == 0 {
                print("    ⚠️ Skipping insights for \(member.name): 0 valid days")
                continue
            }
            if !cov.hasMinimumCoverage {
                print("    ⚠️ Skipping insights for \(member.name): insufficient coverage (<\(requiredMinDaysForAnyInsight))")
                continue
            }
            
            print("  ✅ Analyzing '\(member.name)' (userId: \(userId), \(scores.count) rows, \(daysAvailable) unique days)")
            
            // Analyze each pillar using per-member coverage
            let pillarInsights = analyzeMemberPillars(member: member, scores: scores, daysAvailable: daysAvailable)
            allInsights.append(contentsOf: pillarInsights)
            print("    Generated \(pillarInsights.count) insights for this member")
        }
        
        // Choose family coverage representative
        let representative: (FamilyMemberScore, TrendCoverageStatus)? = {
            if let primary = eligibleMembers.first(where: { $0.isMe }) {
                return perMemberCoverage.first(where: { $0.member.userId?.lowercased() == primary.userId?.lowercased() }).map { ($0.member, $0.coverage) }
            }
            if let best = perMemberCoverage.max(by: { $0.coverage.daysAvailable < $1.coverage.daysAvailable }) {
                return (best.member, best.coverage)
            }
            return perMemberCoverage.first.map { ($0.member, $0.coverage) }
        }()
        
        let familyCoverage = representative?.1 ?? TrendCoverageStatus(
            windowDays: windowDays,
            daysAvailable: 0,
            missingDays: windowDays,
            requiredDaysForAnyInsight: requiredMinDaysForAnyInsight,
            needMoreDataDays: requiredMinDaysForAnyInsight,
            hasMinimumCoverage: false
        )
        
        if let rep = representative {
            print("🔎 Family coverage representative: \(rep.0.name) (daysAvailable=\(rep.1.daysAvailable), missing=\(rep.1.missingDays), needMore=\(rep.1.needMoreDataDays), hasMin=\(rep.1.hasMinimumCoverage))")
        } else {
            print("🔎 Family coverage representative: none (no eligible members)")
        }
        
        // If no days for the representative, return no insights
        if familyCoverage.daysAvailable == 0 {
            print("  ⚠️ No trend data yet (0 valid days for representative). Suppressing insights.")
            return ([], familyCoverage)
        }
        
        // If coverage insufficient for representative, emit no insights
        if !familyCoverage.hasMinimumCoverage {
            print("  ⚠️ Coverage insufficient for representative: daysAvailable=\(familyCoverage.daysAvailable), need \(requiredMinDaysForAnyInsight)")
            return ([], familyCoverage)
        }
        
        // Sort by severity and pick top insights
        let selected = selectTopInsights(from: allInsights)
        return (selected, familyCoverage)
    }
    
    // MARK: - Private Analysis
    
    private static func analyzeMemberPillars(
        member: FamilyMemberScore,
        scores: [DailyScore],
        daysAvailable: Int
    ) -> [TrendInsight] {
        
        var insights: [TrendInsight] = []
        
        // Analyze each pillar
        for pillar in VitalityPillar.allCases {
            if let insight = analyzePillar(pillar, member: member, scores: scores, daysAvailable: daysAvailable) {
                insights.append(insight)
            }
        }
        
        return insights
    }
    
    private static func analyzePillar(
        _ pillar: VitalityPillar,
        member: FamilyMemberScore,
        scores: [DailyScore],
        daysAvailable: Int
    ) -> TrendInsight? {
        
        // Extract pillar points and aligned dayKeys from history (only days with this pillar non-nil)
        var pillarPoints: [Int] = []
        var pillarDayKeys: [String] = []
        for score in scores {
            let val: Int?
            switch pillar {
            case .sleep: val = score.sleepPoints
            case .movement: val = score.movementPoints
            case .stress: val = score.stressPoints
            }
            if let v = val {
                pillarPoints.append(v)
                pillarDayKeys.append(score.dayKey)
            }
        }
        
        guard pillarPoints.count >= minimumDaysRequired else {
            return nil
        }
        
        // Sort by date (scores already ascending, but ensure)
        let dayKeys = pillarDayKeys
        let missingDays = max(0, windowDays - daysAvailable)
        let confidence = max(0.0, min(1.0, Double(daysAvailable) / Double(windowDays)))
        
        let firstName = {
            let parts = member.name.split(separator: " ")
            return parts.first.map(String.init) ?? member.name
        }()
        
        // Split into recent (last 3 days) and baseline (previous 7 days)
        let recentCount = min(3, pillarPoints.count)
        let recent = Array(pillarPoints.suffix(recentCount))
        let baseline = Array(pillarPoints.dropLast(recentCount).suffix(7))
        
        guard !recent.isEmpty else { return nil }
        
        let recentAvg = Double(recent.reduce(0, +)) / Double(recent.count)
        let baselineAvg = baseline.isEmpty ? recentAvg : Double(baseline.reduce(0, +)) / Double(baseline.count)
        
        // Rule 1: "3-day streak low" - last 3 days in bottom quartile of 14-day range
        let allPoints = pillarPoints
        let sortedPoints = allPoints.sorted()
        let bottomQuartileThreshold = sortedPoints[sortedPoints.count / 4]
        let allRecentInBottomQuartile = recent.allSatisfy { $0 <= bottomQuartileThreshold }
        
        let longestStreak = longestConsecutiveStreak(dayKeys: dayKeys)
        if allRecentInBottomQuartile && recent.count >= requiredConsecutiveForStreak && longestStreak >= requiredConsecutiveForStreak {
            return TrendInsight(
                memberName: member.name,
                memberUserId: member.userId?.lowercased() ?? "",
                pillar: pillar,
                severity: .attention,
                title: "\(firstName) · \(pillar.displayName)",
                body: "\(pillar.displayName) has been in the lower range for 3 days. \(actionSuggestion(for: pillar))",
                debugWhy: "3-day streak in bottom quartile (threshold: \(bottomQuartileThreshold), recent: \(recent))",
                windowDays: windowDays,
                requiredDays: requiredMinDaysForAnyInsight,
                missingDays: missingDays,
                confidence: confidence
            )
        }
        
        // Rule 2: "Drop vs baseline" - recent avg >= 20% lower than baseline
        if baseline.count >= 5 && baselineAvg > 0 && recent.count >= 3 {
            let dropPercent = (baselineAvg - recentAvg) / baselineAvg
            if dropPercent >= 0.20 {
                return TrendInsight(
                    memberName: member.name,
                    memberUserId: member.userId?.lowercased() ?? "",
                    pillar: pillar,
                    severity: .attention,
                    title: "\(firstName) · \(pillar.displayName)",
                    body: "\(pillar.displayName) recovery is below \(firstName)'s recent norm. \(actionSuggestion(for: pillar))",
                    debugWhy: "20%+ drop (baseline: \(Int(baselineAvg)), recent: \(Int(recentAvg)), drop: \(Int(dropPercent * 100))%)",
                    windowDays: windowDays,
                    requiredDays: requiredMinDaysForAnyInsight,
                    missingDays: missingDays,
                    confidence: confidence
                )
            }
        }
        
        // Rule 3: "Rebound" - recent avg >= 15% higher than baseline (celebrate)
        if baseline.count >= 5 && baselineAvg > 0 && recent.count >= 3 {
            let gainPercent = (recentAvg - baselineAvg) / baselineAvg
            if gainPercent >= 0.15 {
                return TrendInsight(
                    memberName: member.name,
                    memberUserId: member.userId?.lowercased() ?? "",
                    pillar: pillar,
                    severity: .celebrate,
                    title: "\(firstName) · \(pillar.displayName)",
                    body: "\(firstName)'s \(pillar.displayName.lowercased()) is improving! Keep the momentum going.",
                    debugWhy: "15%+ rebound (baseline: \(Int(baselineAvg)), recent: \(Int(recentAvg)), gain: \(Int(gainPercent * 100))%)",
                    windowDays: windowDays,
                    requiredDays: requiredMinDaysForAnyInsight,
                    missingDays: missingDays,
                    confidence: confidence
                )
            }
        }
        
        return nil
    }
    
    private static func hasConsecutiveStreak(dayKeys: [String], length: Int) -> Bool {
        guard dayKeys.count >= length else { return false }
        // dayKeys are ascending; parse and check consecutive days
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        let dates: [Date] = dayKeys.compactMap { df.date(from: $0) }
        guard dates.count == dayKeys.count else { return false }
        var streak = 1
        for i in 1..<dates.count {
            let diff = Calendar.current.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 99
            if diff == 1 {
                streak += 1
                if streak >= length { return true }
            } else {
                streak = 1
            }
        }
        return false
    }
    
    private static func longestConsecutiveStreak(dayKeys: [String]) -> Int {
        guard !dayKeys.isEmpty else { return 0 }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        let dates: [Date] = dayKeys.compactMap { df.date(from: $0) }.sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1..<dates.count {
            let diff = Calendar.current.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 99
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
    
    private static func actionSuggestion(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep:
            return "Tonight: earlier wind-down + consistent bedtime."
        case .movement:
            return "Try a short walk today to rebuild momentum."
        case .stress:
            return "Prioritize rest and recovery today."
        }
    }
    
    private static func selectTopInsights(from allInsights: [TrendInsight]) -> [TrendInsight] {
        // Separate by severity
        let attentionInsights = allInsights.filter { $0.severity == .attention }
        let celebrateInsights = allInsights.filter { $0.severity == .celebrate }
        
        var selected: [TrendInsight] = []
        
        // Pick up to 2 attention insights (prefer different members)
        var usedMembers: Set<String> = []
        for insight in attentionInsights {
            if selected.count >= 2 { break }
            
            // Prefer different members
            if usedMembers.contains(insight.memberUserId) && selected.count >= 1 {
                continue
            }
            
            selected.append(insight)
            usedMembers.insert(insight.memberUserId)
        }
        
        // If no attention insights, add 1 celebrate insight
        if selected.isEmpty, let celebrate = celebrateInsights.first {
            selected.append(celebrate)
        }
        
        return selected
    }
}

