import SwiftUI
import SwiftUIX
import Supabase

// MARK: - Notification System Components
// Extracted from DashboardView.swift - Phase 8 of refactoring

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

// MARK: - Family Notifications Card

struct FamilyNotificationsCard: View {
    let items: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    
    private func pillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(_ pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return DashboardDesign.sleepColor
        case .movement: return DashboardDesign.movementColor
        case .stress: return DashboardDesign.stressColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with better typography
            Text("Family notifications")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        onTap(item)
                    } label: {
                        HStack(spacing: 14) {
                            // Icon container - larger with gradient and shadow
                            ZStack {
                                // Gradient background
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                pillarColor(item.pillar).opacity(0.25),
                                                pillarColor(item.pillar).opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 52, height: 52)
                                
                                // Icon
                                Image(systemName: pillarIcon(item.pillar))
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                pillarColor(item.pillar),
                                                pillarColor(item.pillar).opacity(0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            // Text content with better spacing and hierarchy
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(DashboardDesign.primaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                                
                                Text(item.body)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(DashboardDesign.secondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                            }
                            
                            Spacer(minLength: 8)
                            
                            // Chevron with subtle styling
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.4))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                                .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(NotificationCardButtonStyle())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Premium Button Style for Notification Cards
struct NotificationCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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

// MARK: - Family Notification Detail Sheet

struct FamilyNotificationDetailSheet: View {
    let item: FamilyNotificationItem
    let onStartRecommendedChallenge: () -> Void
    let dataManager: DataManager // Changed from @EnvironmentObject to parameter
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Pillar Configuration
    
    /// Configuration for each pillar/metric type
    private struct PillarConfig {
        let displayName: String
        let primaryMetricLabel: String  // "Steps", "Sleep", "HRV (recovery)"
        let primaryUnit: String         // "steps", "hours", "ms"
        let secondaryMetricLabel: String? // nil for Movement/Sleep, "Resting heart rate" for Stress
        let secondaryUnit: String?       // nil or "bpm"
        let optimalTargetLabel: String   // "Optimal steps", "Optimal sleep", "Optimal HRV"
        let fallbackExplanation: String
        
        static func forPillar(_ pillar: VitalityPillar) -> PillarConfig {
            switch pillar {
            case .sleep:
                return PillarConfig(
                    displayName: "Sleep",
                    primaryMetricLabel: "Sleep",
                    primaryUnit: "hours",
                    secondaryMetricLabel: nil,
                    secondaryUnit: nil,
                    optimalTargetLabel: "Optimal sleep",
                    fallbackExplanation: "Sleep quality and duration impact overall vitality."
                )
            case .movement:
                return PillarConfig(
                    displayName: "Movement",
                    primaryMetricLabel: "Steps",
                    primaryUnit: "steps",
                    secondaryMetricLabel: nil,
                    secondaryUnit: nil,
                    optimalTargetLabel: "Optimal steps",
                    fallbackExplanation: "Daily movement and activity levels support vitality."
                )
            case .stress:
                return PillarConfig(
                    displayName: "Recovery",
                    primaryMetricLabel: "HRV",
                    primaryUnit: "ms",
                    secondaryMetricLabel: "Resting heart rate",
                    secondaryUnit: "bpm",
                    optimalTargetLabel: "Optimal HRV",
                    fallbackExplanation: "Recovery signals like HRV and resting heart rate indicate stress levels."
                )
            }
        }
    }
    
    // MARK: - State
    
    @State private var selectedWindowDays: Int = 7
    @State private var historyRows: [(date: String, value: Int?)] = []
    @State private var rawMetrics: [(date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)] = []
    @State private var memberAge: Int?
    @State private var optimalTarget: (min: Double, max: Double)?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasMinimumCoverage = false
    @State private var showAskMiyaChat = false
    
    // AI Insight state
    @State private var aiInsightHeadline: String?
    @State private var aiInsightClinicalInterpretation: String?
    @State private var aiInsightDataConnections: String?
    @State private var aiInsightPossibleCauses: [String] = []
    @State private var aiInsightActionSteps: [String] = []
    @State private var aiInsightConfidence: String?
    @State private var aiInsightConfidenceReason: String?
    @State private var isLoadingAIInsight: Bool = false
    @State private var aiInsightError: String?
    @State private var suggestedMessages: [(label: String, text: String)] = []
    @State private var selectedSuggestedMessageIndex = 0
    @State private var showShareSheet = false
    @State private var aiInsightBaselineValue: Double?
    @State private var loadingStep: Int = 0  // For animated loading checklist
    @State private var isSection1Expanded: Bool = true  // What's Happening
    @State private var isSection2Expanded: Bool = false  // The Full Picture
    @State private var isSection3Expanded: Bool = false  // What Might Be Causing This
    @State private var isSection4Expanded: Bool = true  // What To Do Now (always defaults open)
    @State private var feedbackSubmitted: Bool = false
    @State private var feedbackIsHelpful: Bool? = nil
    @State private var aiInsightRecentValue: Double?
    @State private var aiInsightDeviationPercent: Double?
    
    // NEW: Chat-specific state
    @State private var chatMessages: [ChatMessage] = []
    @State private var availablePrompts: [PillPrompt] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var isAITyping = false  // Show animated typing indicator
    @State private var showMessageTemplates = false
    @State private var isInitializing = true
    @State private var chatError: String?
    @State private var alertStateId: String?
    @State private var memberHealthProfile: [String: Any]?  // Fetched member health data for AI context
    @State private var retryCount = 0  // Track retry attempts to prevent infinite loops
    
    private var config: PillarConfig {
        PillarConfig.forPillar(item.pillar)
    }
    
    // MARK: - Computed Properties
    
    private var severityLabel: String {
        switch item.kind {
        case .trend(let ins):
            switch ins.severity {
            case .celebrate: return "Trending up"
            case .watch: return "Watch"
            case .attention: return "Needs attention"
            }
        case .fallback:
            return "Needs attention"
        }
    }
    
    private var slicedHistory: [(date: String, value: Int?)] {
        Array(historyRows.suffix(selectedWindowDays))
    }
    
    private var averageValue: Double? {
        let values = slicedHistory.compactMap { $0.value }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    // MARK: - Real Metrics Computed Properties
    
    private var slicedRawMetrics: [(date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)] {
        Array(rawMetrics.suffix(selectedWindowDays))
    }
    
    private var averageSteps: Double? {
        let values = slicedRawMetrics.compactMap { $0.steps }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    private var averageSleepHours: Double? {
        let values = slicedRawMetrics.compactMap { $0.sleepMinutes }
        guard !values.isEmpty else { return nil }
        let totalMinutes = values.reduce(0, +)
        return Double(totalMinutes) / Double(values.count) / 60.0
    }
    
    private var averageHRV: Double? {
        let values = slicedRawMetrics.compactMap { $0.hrvMs }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0.0) { $0 + $1 }) / Double(values.count)
    }
    
    private var averageRestingHR: Double? {
        let values = slicedRawMetrics.compactMap { $0.restingHr }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0.0) { $0 + $1 }) / Double(values.count)
    }
    
    private var daysBelowOptimal: Int {
        guard let optimal = optimalTarget else { return 0 }
        return slicedRawMetrics.filter { day in
            switch item.pillar {
            case .movement:
                guard let steps = day.steps else { return false }
                return Double(steps) < optimal.min
            case .sleep:
                guard let sleepMinutes = day.sleepMinutes else { return false }
                let sleepHours = Double(sleepMinutes) / 60.0
                return sleepHours < optimal.min
            case .stress:
                guard let hrv = day.hrvMs else { return false }
                return hrv < optimal.min
            }
        }.count
    }
    
    private var longestStreakBelowOptimal: Int {
        guard let optimal = optimalTarget else { return 0 }
        var maxStreak = 0
        var currentStreak = 0
        for day in slicedRawMetrics.reversed() {
            let isBelow: Bool
            switch item.pillar {
            case .movement:
                guard let steps = day.steps else {
                    isBelow = false
                    break
                }
                isBelow = Double(steps) < optimal.min
            case .sleep:
                guard let sleepMinutes = day.sleepMinutes else {
                    isBelow = false
                    break
                }
                let sleepHours = Double(sleepMinutes) / 60.0
                isBelow = sleepHours < optimal.min
            case .stress:
                guard let hrv = day.hrvMs else {
                    isBelow = false
                    break
                }
                isBelow = hrv < optimal.min
            }
            
            if isBelow {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        return maxStreak
    }
    
    private var commitTogetherLabel: String {
        switch item.pillar {
        case .sleep:
            return "Plan a wind-down routine together"
        case .movement:
            return "Commit to walking together daily"
        case .stress:
            return "Do a 5-min reset together"
        }
    }
    
    private var selectedShareText: String {
        guard selectedSuggestedMessageIndex < suggestedMessages.count else {
            return "Hey, just checking in on you."
        }
        return suggestedMessages[selectedSuggestedMessageIndex].text
    }
    
    // MARK: - Formatter Helpers
    
    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: steps)) ?? "\(steps)") steps"
    }
    
    private func formatSleepMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
    
    private func formatHRV(_ hrv: Double) -> String {
        return "\(Int(hrv.rounded())) ms"
    }
    
    private func formatRestingHR(_ hr: Double) -> String {
        return "\(Int(hr.rounded())) bpm"
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        return displayFormatter.string(from: date)
    }
    
    private func formatMetricValue(_ value: Double) -> String {
        let unit = config.primaryUnit
        
        // Format based on metric type
        switch item.pillar {
        case .sleep:
            // Convert minutes to hours
            let hours = value / 60.0
            return String(format: "%.1fh", hours)
        case .movement:
            // Steps
            return String(format: "%.0f", value)
        case .stress:
            // HRV or HR
            if config.primaryMetricLabel.contains("HRV") {
                return String(format: "%.0f ms", value)
            } else {
                return String(format: "%.0f bpm", value)
            }
        }
    }
    
    private func formatOptimalRange(_ optimal: (min: Double, max: Double)) -> String {
        switch item.pillar {
        case .sleep:
            // Convert minutes to hours for sleep
            return String(format: "%.1f-%.1fh", optimal.min, optimal.max)
        case .movement:
            // Steps
            return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) steps"
        case .stress:
            // HRV in ms
            if config.primaryMetricLabel.contains("HRV") {
                return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms"
            } else {
                return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) bpm"
            }
        }
    }
    
    private func getBaselineValue() -> Double? {
        return aiInsightBaselineValue
    }
    
    private func getRecentValue() -> Double? {
        return aiInsightRecentValue
    }
    
    private func getDeviationPercent() -> Double {
        return aiInsightDeviationPercent ?? 0
    }
    
    // MARK: - Helper Methods
    
    private func buildMiyaPayload() -> [String: Any] {
        let sliced = slicedHistory
        let optimalMin = optimalTarget?.min ?? 0.0
        let optimalMax = optimalTarget?.max ?? 0.0
        return [
            "memberName": item.memberName,
            "memberUserId": item.memberUserId ?? "",
            "pillar": item.pillar.rawValue,
            "selectedWindowDays": selectedWindowDays,
            "optimalTarget": ["min": optimalMin, "max": optimalMax],
            "dailyValues": sliced.map { ["date": $0.date, "value": $0.value ?? 0] },
            "summary": [
                "average": averageValue ?? 0,
                "daysBelowOptimal": daysBelowOptimal,
                "longestStreakBelowOptimal": longestStreakBelowOptimal
            ],
            "triggerReason": item.debugWhy ?? config.fallbackExplanation
        ]
    }
    
    private func extractAlertStateId(from debugWhy: String) -> String? {
        // Format: "serverPattern ... alertStateId=<uuid> ..."
        let pattern = "alertStateId=([a-f0-9-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: debugWhy, options: [], range: NSRange(debugWhy.startIndex..., in: debugWhy)),
              let range = Range(match.range(at: 1), in: debugWhy)
        else { return nil }
        return String(debugWhy[range])
    }
    
    private func openWhatsApp(with message: String) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Always try to open WhatsApp directly (bypass canOpenURL which can be unreliable)
        if let url = URL(string: "whatsapp://send?text=\(encoded)") {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    // WhatsApp not installed - open App Store
                    DispatchQueue.main.async {
                        if let appStoreURL = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997") {
                            UIApplication.shared.open(appStoreURL)
                        }
                    }
                }
            }
        }
    }
    
    private func openMessages(with message: String, phoneNumber: String? = nil) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var urlString = "sms:"
        if let phone = phoneNumber {
            urlString += phone
        }
        urlString += "&body=\(encoded)"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Async Data Loading Methods
    
    private func loadHistory() async {
        // Gracefully handle nil memberUserId (no red error box)
        guard let userId = item.memberUserId else {
            await MainActor.run {
                isLoading = false
                loadError = nil
                historyRows = []
                rawMetrics = []
                hasMinimumCoverage = false
            }
            #if DEBUG
            print("📊 FamilyNotificationDetailSheet: No memberUserId for \(item.memberName) - showing graceful state")
            #endif
            return
        }
        
        await MainActor.run {
            isLoading = true
            loadError = nil
            selectedWindowDays = item.triggerWindowDays ?? 7
        }
        
        #if DEBUG
        print("📊 INSIGHT_DETAIL_OPENED: memberName=\(item.memberName) userId=\(userId) pillar=\(item.pillar.rawValue) window=\(selectedWindowDays)")
        print("📊 FamilyNotificationDetailSheet: Loading history for \(item.memberName) (userId: \(userId), pillar: \(item.pillar.rawValue), days: 21)")
        #endif
        
        do {
            // Fetch pillar scores from vitality_scores
            let pillarRows = try await dataManager.fetchUserPillarHistory(
                userId: userId,
                pillar: item.pillar,
                days: 21
            )
            
            // Fetch raw metrics from wearable_daily_metrics
            let wearableRows = try await dataManager.fetchWearableDailyMetricsForUser(userId: userId, days: 21)
            
            // Deduplicate pillar rows by date
            let deduplicatedPillarRows = Dictionary(grouping: pillarRows, by: { $0.date })
                .compactMapValues { dayRows -> (date: String, value: Int?)? in
                    let sorted = dayRows.sorted { ($0.value ?? -1) > ($1.value ?? -1) }
                    return sorted.first
                }
                .values
                .sorted { $0.date < $1.date }
            
            // Convert wearable rows to our format and merge by date
            let rawMetricsDict = Dictionary(grouping: wearableRows, by: { $0.metricDate })
                .compactMapValues { dayRows -> (steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)? in
                    // If multiple rows for same date, prefer rows with more data
                    let sorted = dayRows.sorted { row1, row2 in
                        let count1 = [row1.steps, row1.sleepMinutes, row1.hrvMs, row1.restingHr].compactMap { $0 }.count
                        let count2 = [row2.steps, row2.sleepMinutes, row2.hrvMs, row2.restingHr].compactMap { $0 }.count
                        return count1 > count2
                    }
                    guard let best = sorted.first else { return nil }
                    return (best.steps, best.sleepMinutes, best.hrvMs, best.restingHr)
                }
            
            // Create merged raw metrics array sorted by date
            let mergedRawMetrics = rawMetricsDict.map { (date, metrics) in
                (date: date, steps: metrics.steps, sleepMinutes: metrics.sleepMinutes, hrvMs: metrics.hrvMs, restingHr: metrics.restingHr)
            }.sorted { $0.date < $1.date }
            
            await MainActor.run {
                historyRows = deduplicatedPillarRows
                rawMetrics = mergedRawMetrics
                hasMinimumCoverage = deduplicatedPillarRows.count >= 7
                isLoading = false
                
                #if DEBUG
                print("📊 FamilyNotificationDetailSheet: Loaded \(deduplicatedPillarRows.count) pillar rows, \(mergedRawMetrics.count) raw metric rows")
                if deduplicatedPillarRows.count < 7 {
                    print("  ⚠️ Insufficient coverage: \(deduplicatedPillarRows.count) < 7 days")
                }
                #endif
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
                hasMinimumCoverage = false
                historyRows = []
                rawMetrics = []
            }
            #if DEBUG
            print("❌ FamilyNotificationDetailSheet: Error loading history: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func calculateOptimalTarget() async {
        guard let userId = item.memberUserId else {
            await MainActor.run { optimalTarget = nil }
            return
        }
        
        // Fetch age
        let age = try? await dataManager.fetchMemberAge(userId: userId)
        await MainActor.run { memberAge = age }
        
        guard let age = age else {
            await MainActor.run { optimalTarget = nil }
            return
        }
        
        // Get age group
        let ageGroup = AgeGroup.from(age: age)
        
        // Get optimal range from ScoringSchema based on pillar
        let range: (min: Double, max: Double)?
        switch item.pillar {
        case .movement:
            // Get steps optimal range
            if let stepsDef = vitalityScoringSchema
                .first(where: { $0.id == .movement })?
                .subMetrics.first(where: { $0.id == .steps }),
               let benchmarks = stepsDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        case .sleep:
            // Get sleep duration optimal range
            if let sleepDef = vitalityScoringSchema
                .first(where: { $0.id == .sleep })?
                .subMetrics.first(where: { $0.id == .sleepDuration }),
               let benchmarks = sleepDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        case .stress:
            // Get HRV optimal range
            if let hrvDef = vitalityScoringSchema
                .first(where: { $0.id == .stress })?
                .subMetrics.first(where: { $0.id == .hrv }),
               let benchmarks = hrvDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        }
        
        await MainActor.run { optimalTarget = range }
    }
    
    private func fetchAIInsightIfPossible() async {
        print("🤖 AI_INSIGHT: fetchAIInsightIfPossible() called for \(item.memberName)")
        print("🤖 AI_INSIGHT: debugWhy = \(item.debugWhy ?? "nil")")
        
        // Only fetch for server pattern alerts with an alertStateId
        guard let debugWhy = item.debugWhy else {
            print("❌ AI_INSIGHT: No debugWhy found - exiting")
            return
        }
        
        guard debugWhy.contains("serverPattern") else {
            print("❌ AI_INSIGHT: debugWhy does not contain 'serverPattern' - exiting")
            return
        }
        
        guard let alertStateId = extractAlertStateId(from: debugWhy) else {
            print("❌ AI_INSIGHT: Could not extract alertStateId from debugWhy - exiting")
            return
        }
        
        print("✅ AI_INSIGHT: Found alertStateId = \(alertStateId)")
        
        await MainActor.run {
            isLoadingAIInsight = true
            aiInsightError = nil
        }
        
        do {
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight") else { throw URLError(.badURL) }
            
            print("🌐 AI_INSIGHT: Calling Edge Function at \(url)")
            print("🌐 AI_INSIGHT: Payload = {\"alert_state_id\": \"\(alertStateId)\"}")
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            print("📥 AI_INSIGHT: Response status = \(httpStatus)")
            print("📥 AI_INSIGHT: Response data = \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                print("❌ AI_INSIGHT: Edge Function returned error: \(errBody)")
                throw NSError(domain: "miya_insight", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "AI insight failed (status \(httpStatus)): \(errBody)"])
            }
            
            print("✅ AI_INSIGHT: Successfully received response")
            
            await MainActor.run {
                aiInsightHeadline = obj?["headline"] as? String
                aiInsightClinicalInterpretation = obj?["clinical_interpretation"] as? String
                aiInsightDataConnections = obj?["data_connections"] as? String
                aiInsightPossibleCauses = obj?["possible_causes"] as? [String] ?? []
                aiInsightActionSteps = obj?["action_steps"] as? [String] ?? []
                aiInsightConfidence = obj?["confidence"] as? String
                aiInsightConfidenceReason = obj?["confidence_reason"] as? String
                
                print("📊 AI_INSIGHT: Parsed fields:")
                print("  - headline: \(aiInsightHeadline ?? "nil")")
                print("  - clinical_interpretation: \(aiInsightClinicalInterpretation?.prefix(50) ?? "nil")...")
                print("  - data_connections: \(aiInsightDataConnections?.prefix(50) ?? "nil")...")
                print("  - possible_causes: \(aiInsightPossibleCauses.count) items")
                print("  - action_steps: \(aiInsightActionSteps.count) items")
                
                // Extract evidence data for metric display
                if let evidence = obj?["evidence"] as? [String: Any] {
                    aiInsightBaselineValue = evidence["baseline_value"] as? Double
                    aiInsightRecentValue = evidence["recent_value"] as? Double
                    aiInsightDeviationPercent = evidence["deviation_percent"] as? Double
                    print("  - evidence baseline: \(aiInsightBaselineValue ?? 0)")
                    print("  - evidence recent: \(aiInsightRecentValue ?? 0)")
                    print("  - evidence deviation: \(aiInsightDeviationPercent ?? 0)")
                }
                
                if let ms = obj?["message_suggestions"] as? [[String: Any]] {
                    suggestedMessages = ms.compactMap { d in
                        guard let label = d["label"] as? String, let text = d["text"] as? String else { return nil }
                        return (label: label, text: text)
                    }
                    print("  - message_suggestions: \(suggestedMessages.count) items")
                }
            }
        } catch {
            print("❌ AI_INSIGHT: Error occurred: \(error)")
            print("❌ AI_INSIGHT: Error description: \(error.localizedDescription)")
            print("❌ AI_INSIGHT: Error type: \(type(of: error))")
            if let urlError = error as? URLError {
                print("❌ AI_INSIGHT: URLError code: \(urlError.code)")
            }
            if let nsError = error as? NSError {
                print("❌ AI_INSIGHT: NSError domain: \(nsError.domain)")
                print("❌ AI_INSIGHT: NSError code: \(nsError.code)")
                print("❌ AI_INSIGHT: NSError userInfo: \(nsError.userInfo)")
            }
            await MainActor.run {
                aiInsightError = error.localizedDescription
            }
        }
        
        await MainActor.run { isLoadingAIInsight = false }
    }
    
    // MARK: - Conversation Initialization
    
    private func initializeConversation() async {
        print("🚀 CHAT: initializeConversation started")
        print("🚀 CHAT: debugWhy = \(String(describing: item.debugWhy))")
        
        // Extract alert_state_id from debugWhy
        guard let debugWhy = item.debugWhy,
              debugWhy.contains("serverPattern"),
              let extracted = extractAlertStateId(from: debugWhy) else {
            print("❌ CHAT: Failed to extract alertStateId from debugWhy")
            await MainActor.run {
                chatError = "This notification doesn't have chat support yet."
                isInitializing = false
            }
            return
        }
        
        print("✅ CHAT: Extracted alertStateId = \(extracted)")
        await MainActor.run {
            alertStateId = extracted
        }
        
        // Load data (for any fallback needs)
        await loadHistory()
        await calculateOptimalTarget()
        await fetchAIInsightIfPossible()
        await loadMemberHealthProfile()  // 🔥 NEW: Load health context for AI
        
        // Generate warm opening message
        let openingMessage = generateOpeningMessage()
        
        await MainActor.run {
            chatMessages = [
                ChatMessage(role: .miya, text: openingMessage)
            ]
            
            // Set initial suggested prompts
            availablePrompts = getInitialPrompts()
            
            // Hide loading state
            isInitializing = false
        }
    }
    
    // MARK: - Load Member Health Profile
    
    private func loadMemberHealthProfile() async {
        guard let memberUserId = item.memberUserId else {
            print("⚠️ CHAT: No memberUserId available for health profile")
            return
        }
        
        do {
            // Fetch user profile from database
            struct UserProfileRow: Decodable {
                let user_id: String?
                let gender: String?
                let ethnicity: String?
                let date_of_birth: String?
                let height_cm: Double?
                let weight_kg: Double?
                let risk_band: String?
                let risk_points: Int?
                let optimal_vitality_target: Int?
                let blood_pressure_status: String?
                let diabetes_status: String?
                let smoking_status: String?
                let has_prior_heart_attack: Bool?
                let has_prior_stroke: Bool?
                let family_heart_disease_early: Bool?
                let family_stroke_early: Bool?
                let family_type2_diabetes: Bool?
            }
            
            let supabase = SupabaseConfig.client
            let profiles: [UserProfileRow] = try await supabase
                .from("user_profiles")
                .select("user_id,gender,ethnicity,date_of_birth,height_cm,weight_kg,risk_band,risk_points,optimal_vitality_target,blood_pressure_status,diabetes_status,smoking_status,has_prior_heart_attack,has_prior_stroke,family_heart_disease_early,family_stroke_early,family_type2_diabetes")
                .eq("user_id", value: memberUserId)
                .limit(1)
                .execute()
                .value
            
            guard let profile = profiles.first else {
                print("⚠️ CHAT: No profile found for user \(memberUserId)")
                return
            }
            
            var profileData: [String: Any] = [:]
            
            // Demographics
            if let age = memberAge {
                profileData["age"] = age
            }
            if let gender = profile.gender {
                profileData["gender"] = gender
            }
            if let ethnicity = profile.ethnicity {
                profileData["ethnicity"] = ethnicity
            }
            
            // Physical measurements
            if let heightCm = profile.height_cm {
                profileData["height_cm"] = heightCm
            }
            if let weightKg = profile.weight_kg {
                profileData["weight_kg"] = weightKg
                // Calculate BMI if we have both height and weight
                if let heightCm = profile.height_cm, heightCm > 0 {
                    let heightM = heightCm / 100.0
                    let bmi = weightKg / (heightM * heightM)
                    profileData["bmi"] = String(format: "%.1f", bmi)
                }
            }
            
            // Risk assessment
            if let riskBand = profile.risk_band {
                profileData["risk_band"] = riskBand
            }
            if let riskPoints = profile.risk_points {
                profileData["risk_points"] = riskPoints
            }
            if let optimalTarget = profile.optimal_vitality_target {
                profileData["optimal_vitality_target"] = optimalTarget
            }
            
            // Health conditions
            if let bpStatus = profile.blood_pressure_status {
                profileData["blood_pressure_status"] = bpStatus
            }
            if let diabStatus = profile.diabetes_status {
                profileData["diabetes_status"] = diabStatus
            }
            if let smokingStatus = profile.smoking_status {
                profileData["smoking_status"] = smokingStatus
            }
            if let priorHeartAttack = profile.has_prior_heart_attack {
                profileData["has_prior_heart_attack"] = priorHeartAttack
            }
            if let priorStroke = profile.has_prior_stroke {
                profileData["has_prior_stroke"] = priorStroke
            }
            
            // Family history
            if let familyHeart = profile.family_heart_disease_early {
                profileData["family_heart_disease_early"] = familyHeart
            }
            if let familyStroke = profile.family_stroke_early {
                profileData["family_stroke_early"] = familyStroke
            }
            if let familyDiabetes = profile.family_type2_diabetes {
                profileData["family_type2_diabetes"] = familyDiabetes
            }
            
            await MainActor.run {
                memberHealthProfile = profileData
                print("✅ CHAT: Loaded health profile with \(profileData.count) fields")
            }
            
        } catch {
            print("⚠️ CHAT: Failed to load member health profile: \(error.localizedDescription)")
            // Non-critical - chat will work without health context
        }
    }
    
    // MARK: - Build Chat Payloads
    
    private func buildChatContextPayload() -> [String: Any] {
        // Build comprehensive context for GPT
        
        // Infer metric name and unit from pillar and title
        let metricInfo = inferMetricInfo(pillar: item.pillar, title: item.title)
        
        var context: [String: Any] = [
            "member_name": item.memberName,
            "pillar": item.pillar.rawValue,
            "metric_name": metricInfo.name,
            "metric_unit": metricInfo.unit,
            "alert_headline": item.title,
            "severity": severityLabel,
            "duration_days": parseDuration(from: item.debugWhy)
        ]
        
        // 🔥 NEW: Add comprehensive user health profile context
        // We'll fetch this asynchronously when loading history, store it in state
        if let profileData = memberHealthProfile {
            context["member_health_profile"] = profileData
        }
        
        // Add available metrics data
        if !historyRows.isEmpty {
            let recentData = Array(historyRows.suffix(14)).map { day in
                [
                    "date": day.date,
                    "value": day.value as Any? ?? NSNull()  // null, not 0
                ] as [String : Any]
            }
            context["recent_daily_values"] = recentData
        }
        
        // Add optimal range if available
        if let optMin = optimalTarget?.min, let optMax = optimalTarget?.max {
            context["optimal_range"] = [
                "min": optMin,
                "max": optMax
            ]
        }
        
        // Add AI insight if available
        if let headline = aiInsightHeadline {
            context["ai_insight_headline"] = headline
        }
        if let clinical = aiInsightClinicalInterpretation {
            context["clinical_interpretation"] = clinical
        }
        if let connections = aiInsightDataConnections {
            context["data_connections"] = connections
        }
        
        return context
    }
    
    private func inferMetricInfo(pillar: VitalityPillar, title: String) -> (name: String, unit: String) {
        // NOTE: historyRows contains PILLAR SCORES (0-100) from vitality_scores table
        // These are NOT raw health metrics, they're vitality scores
        
        let titleLower = title.lowercased()
        
        // Check if title explicitly mentions a raw metric
        if titleLower.contains("resting heart rate") || titleLower.contains("rhr") {
            return ("Resting Heart Rate", "bpm")
        } else if titleLower.contains("hrv") || titleLower.contains("variability") {
            return ("Heart Rate Variability", "ms")
        } else if titleLower.contains("steps") {
            return ("Daily Steps", "steps")
        } else if titleLower.contains("active minutes") {
            return ("Active Minutes", "minutes")
        } else if titleLower.contains("sleep duration") || titleLower.contains("hours of sleep") {
            return ("Sleep Duration", "hours")
        }
        
        // Otherwise, it's a pillar vitality score (default case)
        switch pillar {
        case .sleep:
            return ("Sleep Vitality Score", "/100")
        case .movement:
            return ("Movement Vitality Score", "/100")
        case .stress:
            return ("Recovery Vitality Score", "/100")
        }
    }
    
    private func buildChatHistoryPayload() -> [[String: String]] {
        // Send last 10 messages for conversation context
        return Array(chatMessages.suffix(10)).map { msg in
            [
                "role": msg.role == .miya ? "assistant" : "user",
                "text": msg.text
            ]
        }
    }
    
    // MARK: - Send Message to GPT
    
    private func sendMessage(text: String, skipAddingUserMessage: Bool = false) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🗣️ CHAT: sendMessage called with text: '\(trimmedText)', skipAddingUserMessage: \(skipAddingUserMessage)")
        print("🗣️ CHAT: alertStateId = \(String(describing: alertStateId)), retryCount = \(retryCount)")
        
        guard !trimmedText.isEmpty else {
            print("❌ CHAT: Empty text, returning")
            return
        }
        
        guard let alertId = alertStateId else {
            print("❌ CHAT: No alertStateId, returning")
            await MainActor.run {
                chatError = "Unable to connect to AI. Please try reopening this notification."
            }
            return
        }
        
        // Clear input and add user message (unless this is a retry)
        await MainActor.run {
            inputText = ""
            if !skipAddingUserMessage {
                chatMessages.append(ChatMessage(role: .user, text: trimmedText))
                retryCount = 0  // Reset retry counter for new messages
            }
            isSending = true
            isAITyping = true  // Show animated typing indicator
            chatError = nil
        }
        
        do {
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight_chat") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "alert_state_id": alertId,
                "message": trimmedText,
                "context": buildChatContextPayload(),  // Full health context
                "history": buildChatHistoryPayload()   // Conversation history
            ])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ CHAT: Invalid response type")
                throw URLError(.badServerResponse)
            }
            
            print("🔍 CHAT: HTTP status = \(httpResponse.statusCode)")
            
            // Handle 409: Insight not generated yet - generate it first then retry (max 1 retry)
            if httpResponse.statusCode == 409 {
                if retryCount >= 1 {
                    print("❌ CHAT: Max retries reached (409 persists), stopping")
                    let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                    print("❌ CHAT: Error body: \(errorBody)")
                    await MainActor.run {
                        isAITyping = false  // Hide typing indicator
                        chatError = "AI insight couldn't be generated. Please try again later or contact support."
                        isSending = false
                    }
                    return
                }
                
                print("⚠️ CHAT: Insight not generated yet, generating now... (retry \(retryCount + 1)/1)")
                await MainActor.run {
                    retryCount += 1
                }
                await generateInsightAndRetry(alertId: alertId, userMessage: trimmedText)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                print("❌ CHAT: Bad status code \(httpResponse.statusCode): \(errorBody)")
                throw URLError(.badServerResponse)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = json["reply"] as? String else {
                let jsonStr = String(data: data, encoding: .utf8) ?? "No data"
                print("❌ CHAT: Failed to parse response: \(jsonStr)")
                throw URLError(.cannotParseResponse)
            }
            
            print("✅ CHAT: Got reply from AI (\(reply.count) chars)")
            
            // Parse GPT-generated suggested prompts (Option B: Dynamic pills)
            let dynamicPills = extractSuggestedPrompts(from: reply)
            
            // Clean reply by removing the SUGGESTED_PROMPTS section
            let cleanedReply = cleanAIResponse(reply)
            
            // Add GPT response
            await MainActor.run {
                isAITyping = false  // Hide typing indicator
                chatMessages.append(ChatMessage(role: .miya, text: cleanedReply))
                isSending = false
                
                // Update suggested prompts - use GPT-generated if available, fallback to contextual
                if !dynamicPills.isEmpty {
                    print("✅ CHAT: Using \(dynamicPills.count) GPT-generated pills")
                    availablePrompts = dynamicPills
                } else if chatMessages.count > 2 {
                    print("⚠️ CHAT: No GPT pills found, using contextual fallback")
                    availablePrompts = getContextualPrompts()
                }
            }
            
        } catch {
            print("❌ CHAT: Error in sendMessage: \(error.localizedDescription)")
            await MainActor.run {
                isAITyping = false  // Hide typing indicator
                chatError = "Failed to get response. Try again?"
                isSending = false
            }
        }
    }
    
    // MARK: - Generate Insight and Retry
    
    private func generateInsightAndRetry(alertId: String, userMessage: String) async {
        do {
            // Call miya_insight to generate the initial insight
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "alert_state_id": alertId
            ])
            
            print("🔄 CHAT: Calling miya_insight to generate initial insight...")
            let (_, response) = try await URLSession.shared.data(for: req)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ CHAT: Failed to generate insight")
                throw URLError(.badServerResponse)
            }
            
            print("✅ CHAT: Insight generated, now retrying chat...")
            
            // Small delay to ensure insight is cached
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Retry the original message (don't re-add user message to chat)
            await sendMessage(text: userMessage, skipAddingUserMessage: true)
            
        } catch {
            print("❌ CHAT: Error generating insight: \(error.localizedDescription)")
            await MainActor.run {
                isAITyping = false  // Hide typing indicator
                chatError = "Failed to initialize AI. Try again?"
                isSending = false
            }
        }
    }
    
    // MARK: - Dynamic Pill Generation (Option B: GPT-Generated)
    
    private func extractSuggestedPrompts(from aiResponse: String) -> [PillPrompt] {
        // Look for SUGGESTED_PROMPTS: section
        guard let range = aiResponse.range(of: "SUGGESTED_PROMPTS:") else {
            print("⚠️ PILLS: No SUGGESTED_PROMPTS found in AI response")
            return []
        }
        
        let promptsSection = String(aiResponse[range.upperBound...])
        
        // Extract lines that start with "- "
        let lines = promptsSection.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "") }
            .filter { !$0.isEmpty }
        
        print("✅ PILLS: Extracted \(lines.count) suggestions: \(lines)")
        
        // Map to PillPrompts with smart icons
        let pills = lines.prefix(3).map { text -> PillPrompt in
            let icon = selectIconForPrompt(text)
            return PillPrompt(
                icon: icon,
                text: text,
                category: .general
            )
        }
        
        return Array(pills)
    }
    
    private func cleanAIResponse(_ response: String) -> String {
        // Remove SUGGESTED_PROMPTS section from display
        if let range = response.range(of: "SUGGESTED_PROMPTS:") {
            return String(response[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response
    }
    
    private func selectIconForPrompt(_ text: String) -> String {
        let lower = text.lowercased()
        
        // Match keywords to appropriate icons
        if lower.contains("fix") || lower.contains("solve") || lower.contains("help") {
            return "🛠️"
        } else if lower.contains("schedule") || lower.contains("routine") || lower.contains("time") {
            return "⏰"
        } else if lower.contains("exercise") || lower.contains("movement") || lower.contains("walk") {
            return "🏃"
        } else if lower.contains("stress") || lower.contains("relax") || lower.contains("calm") {
            return "🧘"
        } else if lower.contains("sleep") || lower.contains("bedtime") || lower.contains("rest") {
            return "💤"
        } else if lower.contains("data") || lower.contains("chart") || lower.contains("show") {
            return "📊"
        } else if lower.contains("worried") || lower.contains("serious") || lower.contains("concern") {
            return "⚠️"
        } else if lower.contains("long") || lower.contains("when") || lower.contains("improvement") {
            return "⏳"
        } else if lower.contains("cause") || lower.contains("why") || lower.contains("reason") {
            return "🔍"
        } else if lower.contains("reach") || lower.contains("talk") || lower.contains("contact") {
            return "💬"
        } else {
            return "💡"  // Default for questions
        }
    }
    
    private func getContextualPrompts() -> [PillPrompt] {
        let firstName = item.memberName.split(separator: " ").first.map(String.init) ?? item.memberName
        
        // Fallback pills when GPT doesn't provide suggestions
        return [
            PillPrompt(
                icon: "🤝",
                text: "Reach out to \(firstName)",
                category: .reachOut
            ),
            PillPrompt(
                icon: "📅",
                text: "Show day-by-day data",
                category: .general
            ),
            PillPrompt(
                icon: "🔍",
                text: "Tell me more",
                category: .general
            )
        ]
    }
    
    private func generateOpeningMessage() -> String {
        let name = item.memberName
        let firstName = name.split(separator: " ").first.map(String.init) ?? name
        let pillar = item.pillar
        let severity = severityLabel.lowercased()
        
        // Get duration from item (parse from debugWhy or use default)
        let duration = parseDuration(from: item.debugWhy)
        let metricName = config.displayName.lowercased()
        
        // Opening messages that escalate based on duration (severity is secondary)
        // Duration is the primary factor - match on duration ranges first
        switch duration {
        // 3-day patterns (early warning)
        case 1...3:
            return "Hey — I noticed \(firstName)'s \(metricName) has dropped over the last \(duration) days. This is an early warning. Let's talk about it so we can see how you can best support \(firstName)."
        
        // 7-day patterns (needs attention)
        case 4...7:
            return "Hey — \(firstName)'s pattern of lower \(metricName) has been going on for \(duration) days. I can see a drop in their baseline. Let's talk about this pattern and reach out to \(firstName) so we can fix it before it grows."
        
        // 14-day patterns (critical)
        case 8...14:
            return "Hey — \(firstName)'s \(metricName) has been below baseline for \(duration) days now. This needs attention. Let's figure out what's going on and how to help \(firstName) get back on track."
        
        // 21+ day patterns (urgent - long-standing issue)
        case 15...:
            return "Hey — \(firstName)'s \(metricName) has been below baseline for \(duration) days. This pattern has been going on for a while and needs your attention. Let's figure out what's happening and how to best support \(firstName)."
        
        // Fallback (shouldn't reach here, but just in case)
        default:
            return "Hey — I noticed \(firstName)'s \(metricName) has been off lately for about \(duration) days. Let's talk about what's going on and how you can support \(firstName)."
        }
    }
    
    private func parseDuration(from debugWhy: String?) -> Int {
        // Parse duration from debugWhy (multiple possible formats)
        guard let debugWhy = debugWhy else {
            print("⚠️ DURATION: No debugWhy provided, defaulting to 3")
            return 3
        }
        
        print("🔍 DURATION: Parsing from debugWhy: \(debugWhy)")
        
        // Try multiple patterns:
        // 1. Server pattern: "level=7" (most common for server alerts)
        if let range = debugWhy.range(of: #"level=(\d+)"#, options: .regularExpression),
           let match = debugWhy[range].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first {
            print("✅ DURATION: Parsed \(match) days from level=X (server pattern)")
            return match
        }
        
        // 2. Client trend: "consecutiveDays: 7" or "consecutiveDays=7"
        if let range = debugWhy.range(of: #"consecutiveDays[\":\s=]+(\d+)"#, options: .regularExpression),
           let match = debugWhy[range].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first {
            print("✅ DURATION: Parsed \(match) days from consecutiveDays (client trend)")
            return match
        }
        
        // 3. Check item.title for duration clues like "last 7d" or "(last 7d)"
        if item.title.contains("last") || item.body.contains("last") {
            let textToSearch = item.title + " " + item.body
            if let range = textToSearch.range(of: #"last (\d+)d"#, options: .regularExpression),
               let match = textToSearch[range].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first {
                print("✅ DURATION: Parsed \(match) days from title/body 'last Xd'")
                return match
            }
        }
        
        print("⚠️ DURATION: Could not parse, defaulting to 3")
        return 3
    }
    
    private func parseMarkdown(_ markdown: String) -> AttributedString {
        // Parse markdown to AttributedString for bold, bullets, etc.
        do {
            var options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            options.allowsExtendedAttributes = true
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    private func getInitialPrompts() -> [PillPrompt] {
        return [
            PillPrompt(
                icon: "📊",
                text: "Show me the numbers",
                category: .general
            ),
            PillPrompt(
                icon: "💡",
                text: "Why is this happening?",
                category: .general
            ),
            PillPrompt(
                icon: "🎯",
                text: "What can help?",
                category: .general
            )
        ]
    }
    
    // No more hardcoded responses - everything goes through GPT now
    
    private func submitFeedback(isHelpful: Bool) {
        // Extract alert state ID from debugWhy
        guard let debugWhy = item.debugWhy,
              debugWhy.contains("serverPattern"),
              let alertStateId = extractAlertStateId(from: debugWhy)
        else {
            print("❌ FEEDBACK: Could not extract alertStateId")
            return
        }
        
        Task {
            do {
                let supabase = SupabaseConfig.client
                let userId = try await supabase.auth.session.user.id
                
                // Create feedback record
                struct FeedbackInsert: Encodable {
                    let alert_state_id: String
                    let user_id: String
                    let is_helpful: Bool
                }
                
                let feedback = FeedbackInsert(
                    alert_state_id: alertStateId,
                    user_id: userId.uuidString,
                    is_helpful: isHelpful
                )
                
                // Insert feedback into database
                try await supabase
                    .from("alert_insight_feedback")
                    .insert(feedback)
                    .execute()
                
                await MainActor.run {
                    feedbackSubmitted = true
                    feedbackIsHelpful = isHelpful
                }
                
                print("✅ FEEDBACK: Submitted \(isHelpful ? "helpful" : "not helpful") for alert \(alertStateId)")
            } catch {
                print("❌ FEEDBACK: Failed to submit - \(error.localizedDescription)")
                // Don't show error to user, just log it
            }
        }
    }
    
    // MARK: - Body View (Main UI - TO BE COMPLETED)
    //
    // The body view contains ~1400 lines of UI code from DashboardView.swift (lines 4318-4743)
    // including:
    // - NavigationStack with ScrollView
    // - Premium header with gradient
    // - "What's going on" summary card (whatsGoingOnContent)
    // - Reach Out section with message suggestions
    // - Ask Miya button
    // - Segmented control for time windows
    // - Daily breakdown with DisclosureGroups
    // - Actions section with contact buttons
    // - Commit Together CTA
    // - Sheet presentations for AskMiyaChat
    // - Task modifiers for loadHistory, calculateOptimalTarget, fetchAIInsightIfPossible
    //
    // Supporting @ViewBuilder methods needed:
    // - whatsGoingOnContent (lines 3677-3766)
    // - metricsDisplayView (lines 3768-4121)
    // - movementMetricsView (lines 4123-4191)
    // - sleepMetricsView (lines 4193-4261)
    // - stressMetricsView (lines 4263-4316)
    // - dayByDayRows (lines 4917-4924)
    // - dayByDayRow (lines 4926-4952)
    // - dayByDayMetricValue (lines 4954-4996)
    // - dayByDayOptimalIndicator (lines 4998-5055)
    //
    // MANUAL COMPLETION REQUIRED: Copy these sections from DashboardView.swift
    
    // MARK: - Supporting View Builders (Part 1)
    
    @ViewBuilder
    private var whatsGoingOnContent: some View {
        if item.memberUserId == nil {
            // Graceful "no linked account" state
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No linked account yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("\(item.memberName) needs to complete onboarding to see detailed trends.")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else if isLoading {
            HStack(spacing: 12) {
                ActivityIndicator()
                    .animated(true)
                    .style(.regular)
                Text("Loading history...")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 8)
        } else if let error = loadError {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unable to load data")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else if historyRows.count < 7 {
            // Insufficient data state
            let daysAvailable = historyRows.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Need more data")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        if daysAvailable == 0 {
                            Text("We need 7 days to detect a trend. No data is available yet.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("We need 7 days to detect a trend. Only \(daysAvailable) day\(daysAvailable == 1 ? "" : "s") \(daysAvailable == 1 ? "is" : "are") available so far.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else {
            metricsDisplayView
        }
    }
    
    @ViewBuilder
    private var metricsDisplayView: some View {
        // Phase 2: prefer cached/GPT insight when available.
        if let h = aiInsightHeadline, let clinical = aiInsightClinicalInterpretation {
            VStack(alignment: .leading, spacing: 16) {
                // Medical Disclaimer (always visible)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    
                    Text("This insight is AI-generated to help you understand health trends. It is not medical advice and should not replace consultation with a healthcare provider. If you have medical concerns, please consult a doctor.")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                
                // Get baseline and recent values from AI insight evidence
                let baselineVal = getBaselineValue()
                let recentVal = getRecentValue()
                let deviationPct = getDeviationPercent()
                
                // Key metrics card - shows baseline vs current vs optimal prominently
                if let baseline = baselineVal, let recent = recentVal {
                    VStack(spacing: 16) {
                        // Baseline vs Current
                        HStack(spacing: 20) {
                            // Baseline
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Baseline")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Text(formatMetricValue(baseline))
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundColor(.miyaTextPrimary)
                            }
                            
                            // Arrow indicator
                            Image(systemName: deviationPct < 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(deviationPct < 0 ? .red.opacity(0.7) : .green.opacity(0.7))
                                .padding(.top, 12)
                            
                            // Current
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Text(formatMetricValue(recent))
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundColor(deviationPct < 0 ? .red : .green)
                            }
                            
                            Spacer()
                        }
                        
                        // Change indicator
                        if deviationPct != 0 {
                            HStack(spacing: 6) {
                                Image(systemName: deviationPct < 0 ? "arrow.down" : "arrow.up")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(abs(Int(deviationPct * 100)))% change")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(deviationPct < 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(deviationPct < 0 ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                            )
                        }
                        
                        // Optimal range (if available)
                        if let optimal = optimalTarget {
                            Divider()
                            HStack {
                                Text(config.optimalTargetLabel)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.3)
                                Spacer()
                                Text(formatOptimalRange(optimal))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.green.opacity(0.8))
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                
                // Headline
                Text(h)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Section 1: What's Happening (Clinical Interpretation) - DEFAULT EXPANDED
                ExpandableInsightSection(
                    icon: "📊",
                    title: "What's Happening",
                    isExpanded: $isSection1Expanded,
                    backgroundColor: Color.blue.opacity(0.08)
                ) {
                    Text(clinical)
                        .font(.system(size: 16))
                        .foregroundColor(.miyaTextPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Section 2: The Full Picture (Data Connections) - DEFAULT COLLAPSED
                if let dataConnections = aiInsightDataConnections, !dataConnections.isEmpty {
                    ExpandableInsightSection(
                        icon: "🔍",
                        title: "The Full Picture",
                        isExpanded: $isSection2Expanded,
                        backgroundColor: Color.purple.opacity(0.08)
                    ) {
                        Text(dataConnections)
                            .font(.system(size: 16))
                            .foregroundColor(.miyaTextPrimary)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Section 3: What Might Be Causing This - DEFAULT COLLAPSED
                if !aiInsightPossibleCauses.isEmpty {
                    ExpandableInsightSection(
                        icon: "💡",
                        title: "What Might Be Causing This",
                        isExpanded: $isSection3Expanded,
                        backgroundColor: Color.orange.opacity(0.08)
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(aiInsightPossibleCauses.enumerated()), id: \.element) { index, cause in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    Text(cause)
                                        .font(.system(size: 16))
                                        .foregroundColor(.miyaTextPrimary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                
                // Section 4: What To Do Now - DEFAULT EXPANDED (ALWAYS)
                if !aiInsightActionSteps.isEmpty {
                    ExpandableInsightSection(
                        icon: "✅",
                        title: "What To Do Now",
                        isExpanded: $isSection4Expanded,
                        backgroundColor: Color.green.opacity(0.08)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(aiInsightActionSteps.enumerated()), id: \.element) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.green.opacity(0.15))
                                            .frame(width: 26, height: 26)
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                    .padding(.top, 2)
                                    
                                    Text(step)
                                        .font(.system(size: 16))
                                        .foregroundColor(.miyaTextPrimary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                
                // Feedback buttons (after action steps)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Was this insight helpful?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                    
                    if feedbackSubmitted {
                        // Thank you message
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Thank you for your feedback!")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    } else {
                        // Feedback buttons
                        HStack(spacing: 16) {
                            Button {
                                submitFeedback(isHelpful: true)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("👍")
                                        .font(.system(size: 20))
                                    Text("Yes")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                submitFeedback(isHelpful: false)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("👎")
                                        .font(.system(size: 20))
                                    Text("No")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                
                if let c = aiInsightConfidence, let why = aiInsightConfidenceReason, !c.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: c == "high" ? "checkmark.circle.fill" : c == "medium" ? "info.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(c == "high" ? .green : c == "medium" ? .orange : .red)
                        Text("Confidence: \(c) — \(why)")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.top, 4)
                }
                
                if let err = aiInsightError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 6)
        } else if isLoadingAIInsight {
            // Enhanced loading state with animated steps
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Analyzing \(item.memberName)'s health patterns...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    LoadingStepRow(step: 0, currentStep: loadingStep, text: "Reviewing movement data")
                    LoadingStepRow(step: 1, currentStep: loadingStep, text: "Checking sleep patterns")
                    LoadingStepRow(step: 2, currentStep: loadingStep, text: "Analyzing stress indicators")
                    LoadingStepRow(step: 3, currentStep: loadingStep, text: "Connecting the dots")
                }
                .padding(.leading, 8)
                
                Text("This usually takes 10-15 seconds")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.bottom, 8)
            .onAppear {
                // Animate through the steps
                loadingStep = 0
                Task {
                    for i in 0..<4 {
                        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds per step
                        await MainActor.run {
                            loadingStep = i + 1
                        }
                    }
                }
            }
        } else {
            // Headline sentence (pillar-specific fallback)
            let headline: String = {
                switch item.pillar {
                case .movement:
                    return "They're moving less than their optimal level."
                case .sleep:
                    return "Their sleep has been below their optimal level."
                case .stress:
                    return "Recovery signals suggest higher stress recently."
                }
            }()
            
            Text(headline)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
                .padding(.bottom, 12)
        }
        
        // Real metrics display (pillar-specific)
        VStack(spacing: 12) {
            switch item.pillar {
            case .movement:
                movementMetricsView
            case .sleep:
                sleepMetricsView
            case .stress:
                stressMetricsView
            }
        }
    }
    
    @ViewBuilder
    private var movementMetricsView: some View {
        if let avgSteps = averageSteps {
            HStack {
                Text("Average steps (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatSteps(Int(avgSteps.rounded())))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal average steps")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) steps")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal average steps")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
        
        if daysBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Days below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(daysBelowOptimal)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if longestStreakBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Longest streak below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(longestStreakBelowOptimal) days")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var sleepMetricsView: some View {
        if let avgSleep = averageSleepHours {
            HStack {
                Text("Average sleep (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(String(format: "%.1fh", avgSleep))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal sleep")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(String(format: "%.1f-%.1fh", optimal.min, optimal.max))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal sleep")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
        
        if daysBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Nights below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(daysBelowOptimal)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if longestStreakBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Longest streak below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(longestStreakBelowOptimal) nights")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var stressMetricsView: some View {
        if let avgHRV = averageHRV {
            HStack {
                Text("Average HRV (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatHRV(avgHRV))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let avgRHR = averageRestingHR {
            HStack {
                Text("Average resting heart rate (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatRestingHR(avgRHR))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal HRV")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal HRV")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func dayByDayRows(_ rows: [(date: String, value: Int?)]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.reversed()), id: \.date) { row in
                dayByDayRow(row: row)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func dayByDayRow(row: (date: String, value: Int?)) -> some View {
        // Find matching raw metric for this date
        let rawMetric = rawMetrics.first(where: { $0.date == row.date })
        
        HStack(spacing: 16) {
            // Date
            Text(formatDate(row.date))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
                .frame(width: 90, alignment: .leading)
            
            // Real metric value (pillar-specific)
            dayByDayMetricValue(rawMetric: rawMetric)
            
            Spacer()
            
            // Optimal target and indicator
            dayByDayOptimalIndicator(rawMetric: rawMetric)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
    
    @ViewBuilder
    private func dayByDayMetricValue(rawMetric: (date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)?) -> some View {
        switch item.pillar {
        case .movement:
            if let steps = rawMetric?.steps {
                Text(formatSteps(steps))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
        case .sleep:
            if let sleepMinutes = rawMetric?.sleepMinutes {
                Text(formatSleepMinutes(sleepMinutes))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
        case .stress:
            VStack(alignment: .leading, spacing: 2) {
                if let hrv = rawMetric?.hrvMs {
                    Text(formatHRV(hrv))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                }
                if let rhr = rawMetric?.restingHr {
                    Text(formatRestingHR(rhr))
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                if rawMetric?.hrvMs == nil && rawMetric?.restingHr == nil {
                    Text("—")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func dayByDayOptimalIndicator(rawMetric: (date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)?) -> some View {
        if let optimal = optimalTarget {
            let isBelowOptimal: Bool = {
                switch item.pillar {
                case .movement:
                    if let steps = rawMetric?.steps {
                        return Double(steps) < optimal.min
                    } else {
                        return false
                    }
                case .sleep:
                    if let sleepMinutes = rawMetric?.sleepMinutes {
                        let sleepHours = Double(sleepMinutes) / 60.0
                        return sleepHours < optimal.min
                    } else {
                        return false
                    }
                case .stress:
                    if let hrv = rawMetric?.hrvMs {
                        return hrv < optimal.min
                    } else {
                        return false
                    }
                }
            }()
            
            HStack(spacing: 8) {
                switch item.pillar {
                case .movement:
                    Text("Opt: \(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded()))")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                case .sleep:
                    Text(String(format: "Opt: %.1f-%.1fh", optimal.min, optimal.max))
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                case .stress:
                    Text("Opt: \(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                // Indicator
                if rawMetric != nil {
                    Circle()
                        .fill(isBelowOptimal ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        } else {
            if rawMetric == nil {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
    
    // MARK: - Main Body View
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isInitializing {
                    // Loading state - show immediately
                    VStack(spacing: 16) {
                        Spacer()
                        
                        ActivityIndicator()
                            .animated(true)
                            .style(.large)
                        
                        Text("Miya is analyzing \(item.memberName)'s data...")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        // Chat messages area - Custom Whoop-style UI
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(chatMessages) { message in
                                        WhoopStyleBubble(message: message, memberName: item.memberName)
                                            .id(message.id)
                                    }
                                    
                                    // Animated typing indicator while AI responds
                                    if isAITyping {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(Color.blue.opacity(0.1))
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Text("M")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.blue)
                                                )
                                            
                                            HStack(spacing: 6) {
                                                ForEach(0..<3) { index in
                                                    TypingDot(delay: Double(index) * 0.2)
                                                }
                                            }
                                            .padding(14)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(16)
                                        }
                                        .padding(.leading, 16)
                                    }
                                    
                                    // Error display
                                    if let error = chatError {
                                        HStack(spacing: 10) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text(error)
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(12)
                                        .padding(.horizontal)
                                    }
                                }
                                .padding()
                            }
                            .onChange(of: chatMessages.count) { _ in
                                if let last = chatMessages.last {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Pill prompt suggestions (optional shortcuts)
                        if !availablePrompts.isEmpty && !isSending {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availablePrompts) { prompt in
                                        Button {
                                            if prompt.category == .reachOut {
                                                showMessageTemplates = true
                                            } else {
                                                // Send this prompt as a message
                                                Task {
                                                    await sendMessage(text: prompt.text)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text(prompt.icon)
                                                    .font(.system(size: 14))
                                                Text(prompt.text)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color(.systemGray4), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.vertical, 12)
                            
                            Divider()
                        }
                        
                        // Text input field (ALWAYS visible)
                        HStack(spacing: 12) {
                            TextField("Ask Miya anything...", text: $inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(20)
                                .lineLimit(1...4)
                                .disabled(isSending)
                            
                            Button {
                                Task {
                                    await sendMessage(text: inputText)
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .gray : .blue)
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(item.memberName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMessageTemplates) {
                MessageTemplatesSheet(
                    item: item,
                    suggestedMessages: suggestedMessages,
                    onSendMessage: { message, platform in
                        if platform == .whatsapp {
                            openWhatsApp(with: message)
                        } else {
                            openMessages(with: message)
                        }
                        showMessageTemplates = false
                    }
                )
            }
            .task {
                await initializeConversation()
            }
        }
    }
    
    // MARK: - Old Body View (to be removed after testing)
    private var oldBodyView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Premium Header with gradient background
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.memberName) · \(config.displayName)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("\(severityLabel) · Last \(selectedWindowDays) days")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.miyaBackground.opacity(0.5), Color.miyaBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // "What's going on" summary card (premium design)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What's going on")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.bottom, 4)
                        
                        whatsGoingOnContent
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                    
                    // Reach Out Section - ELEVATED DESIGN (only if AI insight loaded)
                    if !suggestedMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            // Header with icon
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reach Out")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.miyaTextPrimary)
                                    Text("Share this insight with \(item.memberName)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                
                                Spacer()
                            }
                            
                            Picker("Message style", selection: $selectedSuggestedMessageIndex) {
                                ForEach(0..<suggestedMessages.count, id: \.self) { idx in
                                    Text(suggestedMessages[idx].label).tag(idx)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Text(selectedShareText)
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextPrimary)
                                .lineSpacing(4)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                            
                            VStack(spacing: 12) {
                                // WhatsApp Button
                                Button {
                                    openWhatsApp(with: selectedShareText)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Send via WhatsApp")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "arrow.up.forward")
                                            .font(.system(size: 14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color(red: 0.15, green: 0.79, blue: 0.47)) // WhatsApp green
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                // Messages/SMS Button
                                Button {
                                    openMessages(with: selectedShareText)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "message.badge.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Send via Text Message")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "arrow.up.forward")
                                            .font(.system(size: 14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                // Keep the generic share sheet as a fallback
                                Button {
                                    showShareSheet = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("More Options...")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.miyaTextPrimary)
                                    .cornerRadius(12)
                                }
                                .sheet(isPresented: $showShareSheet) {
                                    MiyaShareSheetView(activityItems: [selectedShareText])
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    
                    // Ask Miya button (moved here, directly under "What's going on" card)
                    if item.memberUserId != nil {
                        Button {
                            #if DEBUG
                            print("📤 ASK_MIYA_TAPPED: pillar=\(item.pillar.rawValue) window=\(selectedWindowDays) userId=\(item.memberUserId ?? "nil")")
                            #endif
                            let payload = buildMiyaPayload()
                            #if DEBUG
                            print("📤 ASK_MIYA_PAYLOAD: \(payload)")
                            #endif
                            showAskMiyaChat = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.purple)
                                }
                                
                                Text("Ask Miya")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .disabled(item.memberUserId == nil)
                        .opacity(item.memberUserId == nil ? 0.6 : 1.0)
                    }
                    
                    // Segmented control (7/14/21 days)
                    if item.memberUserId != nil && hasMinimumCoverage {
                        Picker("Window", selection: $selectedWindowDays) {
                            Text("Last 7").tag(7)
                            Text("Last 14").tag(14)
                            Text("Last 21").tag(21)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                    }
                    
                    // Expandable trend details (premium design)
                    if item.memberUserId != nil && hasMinimumCoverage {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Daily breakdown")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                                .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                DisclosureGroup {
                                    dayByDayRows(Array(historyRows.suffix(7)))
                                } label: {
                                    Text("Last 7 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                                
                                DisclosureGroup {
                                    dayByDayRows(Array(historyRows.suffix(14)))
                                } label: {
                                    Text("Last 14 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                                
                                DisclosureGroup {
                                    dayByDayRows(historyRows)
                                } label: {
                                    Text("Last 21 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Actions section (premium design)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Actions")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.horizontal, 20)
                        
                        // Contact buttons (premium design with brand colors)
                        VStack(spacing: 10) {
                            Button {
                                // TODO: Open WhatsApp
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.green.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                    
                                    Text("WhatsApp")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                            
                            Button {
                                // TODO: Open Messages
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text("Text")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                            
                            Button {
                                // TODO: Open FaceTime
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text("FaceTime")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                        }
                        .padding(.horizontal, 20)
                        
                        Text("Add contact info to enable")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, -8)
                        
                        // Commit Together (primary CTA)
                        Button {
                            dismiss()
                            onStartRecommendedChallenge()
                        } label: {
                            Text(commitTogetherLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.miyaPrimary, Color.miyaPrimary.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: Color.miyaPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showAskMiyaChat) {
                MiyaInsightChatSheet(alertItem: item)
            }
            .alert("Data loading", isPresented: .constant(false)) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We're building personalized insights based on this data. Check back soon!")
            }
            .task {
                await loadHistory()
                await calculateOptimalTarget()
                await fetchAIInsightIfPossible()
            }
        }
    }
}

// MARK: - Whoop-Style Chat Bubble

struct WhoopStyleBubble: View {
    let message: ChatMessage
    let memberName: String
    
    private func parseMarkdown(_ markdown: String) -> AttributedString {
        // Parse markdown to AttributedString for bold, bullets, etc.
        do {
            var options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            options.allowsExtendedAttributes = true
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .miya {
                // Miya avatar - circular with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("M")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Message bubble - Whoop-style rounded with markdown support
                VStack(alignment: .leading, spacing: 0) {
                    Text(parseMarkdown(message.text))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.primary)
                }
                .padding(14)
                .background(Color(.systemGray6))
                .cornerRadius(18)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
                
                Spacer()
            } else {
                Spacer()
                
                // User message bubble - blue gradient
                Text(message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(18)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.70, alignment: .trailing)
            }
        }
    }
}

// MARK: - Pill Prompt Grid (kept for suggestion shortcuts)

struct PillPromptGrid: View {
    let prompts: [PillPrompt]
    let onTap: (PillPrompt) -> Void
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(prompts) { prompt in
                PillButton(prompt: prompt) {
                    onTap(prompt)
                }
            }
        }
    }
}

struct PillButton: View {
    let prompt: PillPrompt
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(prompt.icon)
                    .font(.system(size: 14))
                Text(prompt.text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Flow layout for pill wrapping (1-2 rows max)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: ProposedViewSize.unspecified)
        }
    }
}

struct FlowResult {
    var size: CGSize = .zero
    var positions: [CGPoint] = []
    
    init(in maxWidth: CGFloat, subviews: FlowLayout.Subviews, spacing: CGFloat) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        
        self.size = CGSize(width: maxWidth, height: y + lineHeight)
    }
}

// MARK: - Helper Components

struct MiyaShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to update
    }
}

struct MiyaInsightChatSheet: View {
    let alertItem: FamilyNotificationItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isSending = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if errorText != nil || messages.isEmpty {
                    VStack(spacing: 12) {
                        if let err = errorText {
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                        if messages.isEmpty {
                            Text("Ask a question about this pattern")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            HStack {
                                if msg.role == "user" {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .trailing)
                                } else {
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .leading)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                    }
                    .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Ask Miya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        errorText = nil
        
        messages.append((role: "user", text: text))
        isSending = true
        defer { isSending = false }
        
        do {
            // Extract alert_state_id from debugWhy (format: "serverPattern ... alertStateId=<uuid> ...")
            guard let debugWhy = alertItem.debugWhy,
                  debugWhy.contains("serverPattern"),
                  let alertStateId = extractAlertStateId(from: debugWhy)
            else {
                errorText = "Ask Miya is available for server pattern alerts."
                return
            }
            
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight_chat") else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId, "message": text])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                throw NSError(domain: "miya_insight_chat", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Chat failed (status \(httpStatus)): \(errBody)"])
            }
            let reply = obj?["reply"] as? String ?? "Sorry — I couldn't generate a response."
            messages.append((role: "assistant", text: reply))
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func extractAlertStateId(from debugWhy: String) -> String? {
        // Format: "serverPattern ... alertStateId=<uuid> ..."
        let pattern = "alertStateId=([a-f0-9-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: debugWhy, options: [], range: NSRange(debugWhy.startIndex..., in: debugWhy)),
              let range = Range(match.range(at: 1), in: debugWhy)
        else { return nil }
        return String(debugWhy[range])
    }
}

// MARK: - Message Templates Sheet

struct MessageTemplatesSheet: View {
    let item: FamilyNotificationItem
    let suggestedMessages: [(label: String, text: String)]
    let onSendMessage: (String, MessagePlatform) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMessageIndex: Int = 0
    @State private var customMessage: String = ""
    @State private var showCustomInput: Bool = false
    
    enum MessagePlatform {
        case whatsapp
        case imessage
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Choose a message to send to \(item.memberName)")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                // Pre-templated messages as pills
                VStack(spacing: 12) {
                    ForEach(suggestedMessages.indices, id: \.self) { index in
                        Button {
                            selectedMessageIndex = index
                            showCustomInput = false
                        } label: {
                            HStack {
                                Text(suggestedMessages[index].text)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if selectedMessageIndex == index && !showCustomInput {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedMessageIndex == index && !showCustomInput
                                          ? Color.blue.opacity(0.1)
                                          : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedMessageIndex == index && !showCustomInput
                                            ? Color.blue
                                            : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Custom message option
                    Button {
                        showCustomInput = true
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Write my own message")
                                .font(.system(size: 15))
                            Spacer()
                            if showCustomInput {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(showCustomInput ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(showCustomInput ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if showCustomInput {
                        TextField("Type your message...", text: $customMessage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Send buttons
                VStack(spacing: 12) {
                    Button {
                        let message = showCustomInput ? customMessage : suggestedMessages[selectedMessageIndex].text
                        onSendMessage(message, .whatsapp)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Send via WhatsApp")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(showCustomInput && customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button {
                        let message = showCustomInput ? customMessage : suggestedMessages[selectedMessageIndex].text
                        onSendMessage(message, .imessage)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Send via iMessage")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(showCustomInput && customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Reach Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Animated Typing Dot
struct TypingDot: View {
    let delay: Double
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.6))
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.4)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
