import SwiftUI
import SwiftUIX
import Supabase

// MARK: - Notification System Components
// Extracted from DashboardView.swift - Phase 8 of refactoring
// Split into multiple files for better compilation performance:
// - NotificationModels.swift: Data models
// - FamilyNotificationsCard.swift: Card UI component
// - NotificationDetailComponents.swift: UI components (bubbles, layouts, etc.)
// - NotificationHelpers.swift: Helper functions and share sheet
// - MessageTemplatesSheet.swift: Message templates UI

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
    @State private var memberRelationship: String?  // "Partner", "Parent", "Child", etc.
    @State private var retryCount = 0  // Track retry attempts to prevent infinite loops
    
    // Snooze functionality
    @State private var showSnoozeOptions = false
    @State private var isSnoozingAlert = false
    @State private var snoozeError: String?
    
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
        
        // Fetch relationship (for AI context)
        await fetchMemberRelationship(userId: userId)
        
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
    
    private func fetchMemberRelationship(userId: String) async {
        do {
            let supabase = SupabaseConfig.client
            struct FamilyMemberRow: Decodable {
                let relationship: String?
            }
            
            let row: FamilyMemberRow = try await supabase
                .from("family_members")
                .select("relationship")
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value
            
            await MainActor.run {
                memberRelationship = row.relationship
                print("✅ Fetched relationship: \(row.relationship ?? "nil")")
            }
        } catch {
            print("❌ Error fetching relationship: \(error.localizedDescription)")
        }
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
        
        // Add member relationship if available (e.g., "Partner", "Parent", "Child")
        if let relationship = memberRelationship {
            context["member_relationship"] = relationship
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
    
    // MARK: - Snooze & Dismiss Functions
    
    private func snoozeAlert(days: Int) async {
        guard let alertId = alertStateId else {
            snoozeError = "Unable to snooze: Alert ID not found"
            return
        }
        
        await MainActor.run {
            isSnoozingAlert = true
            snoozeError = nil
        }
        
        do {
            let supabase = SupabaseConfig.client
            
            struct SnoozeResult: Decodable {
                let success: Bool
                let alert_id: String?
                let snooze_until: String?
                let snooze_days: Int?
            }
            
            let result: SnoozeResult = try await supabase
                .rpc("snooze_pattern_alert", params: [
                    "alert_id": AnyJSON.string(alertId),
                    "snooze_for_days": AnyJSON.integer(days)
                ])
                .execute()
                .value
            
            if result.success {
                print("✅ Alert snoozed for \(days) days")
                await MainActor.run {
                    isSnoozingAlert = false
                    dismiss()
                }
            } else {
                throw NSError(domain: "snooze", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to snooze alert"])
            }
        } catch {
            print("❌ Error snoozing alert: \(error.localizedDescription)")
            await MainActor.run {
                isSnoozingAlert = false
                snoozeError = "Failed to snooze alert: \(error.localizedDescription)"
            }
        }
    }
    
    private func dismissAlert() async {
        guard let alertId = alertStateId else {
            snoozeError = "Unable to dismiss: Alert ID not found"
            return
        }
        
        await MainActor.run {
            isSnoozingAlert = true
            snoozeError = nil
        }
        
        do {
            let supabase = SupabaseConfig.client
            
            struct DismissResult: Decodable {
                let success: Bool
                let alert_id: String?
                let dismissed_at: String?
            }
            
            let result: DismissResult = try await supabase
                .rpc("dismiss_pattern_alert", params: [
                    "alert_id": AnyJSON.string(alertId)
                ])
                .execute()
                .value
            
            if result.success {
                print("✅ Alert dismissed permanently")
                await MainActor.run {
                    isSnoozingAlert = false
                    dismiss()
                }
            } else {
                throw NSError(domain: "dismiss", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to dismiss alert"])
            }
        } catch {
            print("❌ Error dismissing alert: \(error.localizedDescription)")
            await MainActor.run {
                isSnoozingAlert = false
                snoozeError = "Failed to dismiss alert: \(error.localizedDescription)"
            }
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
        let firstName = item.memberName.split(separator: " ").first.map(String.init) ?? item.memberName
        
        // ALWAYS start with "Reach out" as the first pill
        var pills: [PillPrompt] = [
            PillPrompt(
                icon: "🤝",
                text: "Reach out to \(firstName)",
                category: .reachOut
            )
        ]
        
        // Look for SUGGESTED_PROMPTS: section
        guard let range = aiResponse.range(of: "SUGGESTED_PROMPTS:") else {
            print("⚠️ PILLS: No SUGGESTED_PROMPTS found in AI response")
            return pills  // Return just "Reach out" if no suggestions
        }
        
        let promptsSection = String(aiResponse[range.upperBound...])
        
        // Extract lines that start with "- "
        let lines = promptsSection.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "") }
            .filter { !$0.isEmpty }
        
        print("✅ PILLS: Extracted \(lines.count) suggestions: \(lines)")
        
        // Add up to 2 more pills from AI suggestions (total 3 pills including "Reach out")
        let dynamicPills = lines.prefix(2).map { text -> PillPrompt in
            let icon = selectIconForPrompt(text)
            return PillPrompt(
                icon: icon,
                text: text,
                category: .general
            )
        }
        
        pills.append(contentsOf: dynamicPills)
        return pills
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
        let firstName = item.memberName.split(separator: " ").first.map(String.init) ?? item.memberName
        let pillar = item.pillar
        let severity = severityLabel.lowercased()
        
        // Get relationship-aware references
        let (memberRef, memberPossessive) = getRelationshipReferences()
        
        // Get duration from item (parse from debugWhy or use default)
        let duration = parseDuration(from: item.debugWhy)
        let metricName = config.displayName.lowercased()
        
        // Opening messages that escalate based on duration (severity is secondary)
        // Duration is the primary factor - match on duration ranges first
        switch duration {
        // 3-day patterns (early warning)
        case 1...3:
            return "Hey — I noticed \(memberPossessive) \(metricName) has dropped over the last \(duration) days. This is an early warning. Let's talk about it so we can see how you can best support \(memberRef)."
        
        // 7-day patterns (needs attention)
        case 4...7:
            return "Hey — \(memberPossessive) pattern of lower \(metricName) has been going on for \(duration) days. I can see a drop in their baseline. Let's talk about this pattern and reach out to \(memberRef) so we can fix it before it grows."
        
        // 14-day patterns (critical)
        case 8...14:
            return "Hey — \(memberPossessive) \(metricName) has been below baseline for \(duration) days now. This needs attention. Let's figure out what's going on and how to help \(memberRef) get back on track."
        
        // 21+ day patterns (urgent - long-standing issue)
        case 15...:
            return "Hey — \(memberPossessive) \(metricName) has been below baseline for \(duration) days. This pattern has been going on for a while and needs your attention. Let's figure out what's happening and how to best support \(memberRef)."
        
        // Fallback (shouldn't reach here, but just in case)
        default:
            return "Hey — I noticed \(memberPossessive) \(metricName) has been off lately for about \(duration) days. Let's talk about what's going on and how you can support \(memberRef)."
        }
    }
    
    private func getRelationshipReferences() -> (memberRef: String, memberPossessive: String) {
        let firstName = item.memberName.split(separator: " ").first.map(String.init) ?? item.memberName
        
        // Use relationship if available, otherwise fall back to name
        guard let relationship = memberRelationship?.lowercased() else {
            return (firstName, "\(firstName)'s")
        }
        
        switch relationship {
        case "partner", "wife", "husband":
            // For partner/wife/husband, use "your wife" or "your husband" or "your partner"
            if relationship == "wife" {
                return ("your wife", "your wife's")
            } else if relationship == "husband" {
                return ("your husband", "your husband's")
            } else {
                return ("your partner", "your partner's")
            }
        case "parent":
            return ("your parent", "your parent's")
        case "child":
            return ("your child", "your child's")
        case "sibling":
            return ("your sibling", "your sibling's")
        case "grandparent":
            return ("your grandparent", "your grandparent's")
        default:
            // For "Other" or unknown, use name
            return (firstName, "\(firstName)'s")
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
        let firstName = item.memberName.split(separator: " ").first.map(String.init) ?? item.memberName
        
        // ALWAYS start with "Reach out" as the first pill
        return [
            PillPrompt(
                icon: "🤝",
                text: "Reach out to \(firstName)",
                category: .reachOut
            ),
            PillPrompt(
                icon: "📊",
                text: "Show me the numbers",
                category: .general
            ),
            PillPrompt(
                icon: "💡",
                text: "Why is this happening?",
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
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.5))
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
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.5))
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
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.5))
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
                .background(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.5))
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
                            .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
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
                    .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
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
                .fill(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.5))
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
        AnyView(
            NavigationStack {
                mainContent
            }
            .navigationTitle(item.memberName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if alertStateId != nil {
                        Button {
                            showSnoozeOptions = true
                        } label: {
                            Image(systemName: "bell.slash")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Snooze this alert", isPresented: $showSnoozeOptions, titleVisibility: .visible) {
                Button("Snooze for 1 day") {
                    Task { await snoozeAlert(days: 1) }
                }
                Button("Snooze for 3 days") {
                    Task { await snoozeAlert(days: 3) }
                }
                Button("Snooze for 7 days") {
                    Task { await snoozeAlert(days: 7) }
                }
                Button("Dismiss permanently") {
                    Task { await dismissAlert() }
                }
                .foregroundColor(.red)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how long to hide this alert. You can always view it again in your family's health history.")
            }
            .alert("Snooze Error", isPresented: .constant(snoozeError != nil)) {
                Button("OK") { snoozeError = nil }
            } message: {
                if let error = snoozeError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showMessageTemplates) {
                messageTemplatesSheetView
            }
            .task {
                await initializeConversation()
            }
        )
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if isInitializing {
            loadingView
        } else {
            chatContentView
        }
    }
    
    private var loadingView: some View {
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
    }
    
    private var chatContentView: some View {
        VStack(spacing: 0) {
            chatMessagesView
            Divider()
            if !availablePrompts.isEmpty && !isSending {
                promptSuggestionsView
                Divider()
            }
            textInputView
        }
    }
    
    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(chatMessages) { message in
                        WhoopStyleBubble(message: message, memberName: item.memberName)
                            .id(message.id)
                    }
                    
                    if isAITyping {
                        typingIndicatorView
                    }
                    
                    if let error = chatError {
                        errorView(error)
                    }
                }
                .padding()
            }
            .onChange(of: chatMessages.count) { oldValue, newValue in
                if let last = chatMessages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var typingIndicatorView: some View {
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
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(16)
        }
        .padding(.leading, 16)
    }
    
    @ViewBuilder
    private func errorView(_ error: String) -> some View {
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
    
    private var promptSuggestionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availablePrompts) { prompt in
                    Button {
                        if prompt.category == .reachOut {
                            showMessageTemplates = true
                        } else {
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
                        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(red: 0.82, green: 0.82, blue: 0.84), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
    
    private var textInputView: some View {
        HStack(spacing: 12) {
            TextField("Ask Miya anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(red: 0.95, green: 0.95, blue: 0.97))
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
    
    private var messageTemplatesSheetView: some View {
        MessageTemplatesSheet(
            item: item,
            suggestedMessages: suggestedMessages,
            onSendMessage: { [self] message, platform in
                if platform == .whatsapp {
                    openWhatsApp(with: message)
                } else {
                    openMessages(with: message)
                }
                showMessageTemplates = false
            }
        )
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
                                        .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
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
                                    .background(Color(red: 0.90, green: 0.90, blue: 0.92))
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