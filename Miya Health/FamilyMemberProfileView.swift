import SwiftUI
import Supabase
import Charts

// MARK: - Family Member Profile (New Design)
struct FamilyMemberProfileView: View {
    let memberUserId: String
    let memberName: String
    let familyId: String
    let isCurrentUser: Bool
    let previewMock: Bool
    init(
        memberUserId: String,
        memberName: String,
        familyId: String,
        isCurrentUser: Bool,
        previewMock: Bool = false
    ) {
        self.memberUserId = memberUserId
        self.memberName = memberName
        self.familyId = familyId
        self.isCurrentUser = isCurrentUser
        self.previewMock = previewMock
    }
    
    @EnvironmentObject private var dataManager: DataManager
    
    // Loading / error
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    
    // Vitality
    @State private var vitalityScore: Int = 0
    @State private var vitalityLabel: String = ""
    @State private var vitalityTrendDelta: Int = 0
    @State private var vitalityHasMinimumData: Bool = true
    
    // Alerts
    @State private var alerts: [PatternAlert] = []
    @State private var selectedAlert: PatternAlert? = nil
    @State private var showAlertsSheet: Bool = false
    
    // AI insight for selected alert (loaded when user taps "View insight")
    @State private var aiInsightHeadline: String? = nil
    @State private var aiInsightClinicalInterpretation: String? = nil
    @State private var aiInsightPossibleCauses: [String] = []
    @State private var aiInsightActionSteps: [String] = []
    @State private var isLoadingAIInsight: Bool = false
    @State private var aiInsightError: String? = nil
    
    // Pillars
    @State private var sleepData: ProfilePillarData?
    @State private var movementData: ProfilePillarData?
    @State private var stressData: ProfilePillarData?

    // How many distinct days in the last 7 have any wearable metrics
    @State private var daysWithMetricsLast7: Int = 0

    /// Date of the most recent metric row for this user (yyyy-MM-dd from DB). Used for freshness label.
    @State private var lastMetricDate: Date?

    // Dive deeper sheet
    @State private var selectedPillarForDive: PillarType? = nil
    
    // Animation
    @State private var animateProgress: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaCreamBg.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    healthScoreSection
                    pillarsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            
            if isLoading {
                ProgressView("Loading \(memberName)’s data...")
                    .padding(16)
                    .background(Color.miyaCardWhite)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            } else if let err = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.miyaTerracotta)
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background(Color.miyaCardWhite)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
        }
        .navigationTitle("\(memberName)’s Health")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // ✅ Xcode Preview mock data (no Supabase)
            if previewMock || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                await MainActor.run {
                    isLoading = false
                    loadError = nil

                    vitalityScore = 80
                    vitalityLabel = "Thriving"
                    vitalityTrendDelta = 3

                    alerts = [
                        PatternAlert(
                            id: "preview-alert-1",
                            metricType: "sleep_minutes",
                            patternType: "drop_vs_baseline",
                            currentLevel: 3,
                            severity: "watch",
                            summary: "Sleep changed -15% (current 360 vs baseline 420)",
                            baselineValue: 420,
                            recentValue: 360,
                            deviationPercent: -0.15
                        )
                    ]

                    sleepData = ProfilePillarData(
                        value: "7.2 hours",
                        status: .stable,
                        changeText: "→ 2% • Stable",
                        context: "Sleep vs baseline"
                    )

                    movementData = ProfilePillarData(
                        value: "9,092 steps",
                        status: .stable,
                        changeText: "→ 1% • Stable",
                        context: "Movement vs baseline"
                    )

                    stressData = ProfilePillarData(
                        value: "63 ms HRV",
                        status: .below,
                        changeText: "↓ 6% • Below baseline",
                        context: "Recovery vs baseline"
                    )

                    daysWithMetricsLast7 = 7
                    lastMetricDate = Date()
                    animateProgress = true
                }
                return
            }

            await self.fetchMemberData()
        }
        .sheet(isPresented: $showAlertsSheet) {
            // Alerts drawer: list first, then detail when one is selected
            NavigationStack {
                if let alert = selectedAlert {
                    AlertInsightDetailView(
                        alert: alert,
                        memberName: memberName,
                        aiInsightHeadline: aiInsightHeadline,
                        aiInsightClinicalInterpretation: aiInsightClinicalInterpretation,
                        aiInsightPossibleCauses: aiInsightPossibleCauses,
                        aiInsightActionSteps: aiInsightActionSteps,
                        isLoadingAIInsight: isLoadingAIInsight,
                        aiInsightError: aiInsightError,
                        whyThisIsAnAlertText: whyThisIsAnAlert(alert: alert, memberName: memberName)
                    )
                    .padding()
                    .navigationTitle("Health Alert")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back") {
                                selectedAlert = nil
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                selectedAlert = nil
                                showAlertsSheet = false
                            }
                        }
                    }
                    .task(id: alert.id) {
                        await self.fetchAIInsight(alertStateId: alert.id)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Health alerts")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)

                        if alerts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No active health alerts")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaSageDark)

                                Text("All metrics within normal range")
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(16)
                            .background(Color.miyaCardWhite)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(alerts) { alert in
                                        AlertCardView(alert: alert) {
                                            selectedAlert = alert
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .navigationTitle("Alerts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                showAlertsSheet = false
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPillarForDive) { pillar in
            PillarDiveDeeperSheet(
                memberUserId: memberUserId,
                memberName: memberName,
                vitalityScore: vitalityScore,
                vitalityDeltaPercent: vitalityTrendDelta,
                pillar: pillar,
                movement: movementData,
                sleep: sleepData,
                recovery: stressData
            )
        }
    }
}

// MARK: - Sections
private extension FamilyMemberProfileView {

    var headerSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.miyaCardWhite)
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .stroke(Color.miyaSageLight, lineWidth: 2)
                )
                .overlay(
                    Text(self.initials(from: memberName))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(memberName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Text(isCurrentUser ? "This is your profile" : "Member in your family")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }

            Spacer()

            if !alerts.isEmpty {
                Button {
                    selectedAlert = nil
                    showAlertsSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.yellow)

                        Text("\(min(alerts.count, 9))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -8)
                    }
                    .padding(6)
                    .background(Circle().fill(Color.miyaCardWhite))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var healthScoreSection: some View {
        HealthScoreCard(
            memberName: memberName,
            score: vitalityScore,
            statusText: vitalityLabel,
            trendDelta: vitalityTrendDelta,
            hasMinimumData: vitalityHasMinimumData,
            animateProgress: animateProgress,
            onAskMiya: {
                selectedPillarForDive = .overview
            }
        )
    }

    var pillarsSection: some View {
        let dataFreshness = freshness(for: lastMetricDate)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("📊 Health Pillars (Last 7 days)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
            
            let days = daysWithMetricsLast7
            
            if dataFreshness == .none {
                Text(
                    isCurrentUser
                    ? "We haven’t seen any wearable data for you yet. Wear your Apple Watch for a few days and we’ll start showing your Movement, Sleep and Recovery."
                    : "We haven’t seen any wearable data for \(memberName) yet. Once \(memberName) wears their device for a few days, we’ll start showing their Movement, Sleep and Recovery here."
                )
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if dataFreshness == .stale {
                // Data exists but is older than 7 days – show pillars and honest stale message
                VStack(spacing: 10) {
                    if let movement = movementData {
                        ThinPillarRow(
                            title: "Movement",
                            value: movement.value,
                            status: movement.status,
                            changeText: movement.changeText,
                            context: movement.context,
                            onTap: {
                                selectedPillarForDive = .movement
                            }
                        )
                    }
                    if let sleep = sleepData {
                        ThinPillarRow(
                            title: "Sleep",
                            value: sleep.value,
                            status: sleep.status,
                            changeText: sleep.changeText,
                            context: sleep.context,
                            onTap: {
                                selectedPillarForDive = .sleep
                            }
                        )
                    }
                    if let recovery = stressData {
                        ThinPillarRow(
                            title: "Recovery",
                            value: recovery.value,
                            status: recovery.status,
                            changeText: recovery.changeText,
                            context: recovery.context,
                            onTap: {
                                selectedPillarForDive = .recovery
                            }
                        )
                    }
                }
                Text("Most recent data is more than a week old.")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextTertiary)
            } else {
                // Fresh data (at least one day in last 7 calendar days) – always show pillar rows
                VStack(spacing: 10) {
                    if let movement = movementData {
                        ThinPillarRow(
                            title: "Movement",
                            value: movement.value,
                            status: movement.status,
                            changeText: movement.changeText,
                            context: movement.context,
                            onTap: {
                                selectedPillarForDive = .movement
                            }
                        )
                    }
                    if let sleep = sleepData {
                        ThinPillarRow(
                            title: "Sleep",
                            value: sleep.value,
                            status: sleep.status,
                            changeText: sleep.changeText,
                            context: sleep.context,
                            onTap: {
                                selectedPillarForDive = .sleep
                            }
                        )
                    }
                    if let recovery = stressData {
                        ThinPillarRow(
                            title: "Recovery",
                            value: recovery.value,
                            status: recovery.status,
                            changeText: recovery.changeText,
                            context: recovery.context,
                            onTap: {
                                selectedPillarForDive = .recovery
                            }
                        )
                    }
                }
                if days < 7 {
                    Text("Based on the last \(days) day\(days == 1 ? "" : "s") of data.")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextTertiary)
                } else {
                    Text("Scores show how your last 7 days compare to your usual pattern.")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextTertiary)
                }
            }
        }
    }
}

// MARK: - Data Fetching
private extension FamilyMemberProfileView {
    func fetchMemberData() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        
        async let vitalityTask = fetchVitality()
        async let alertsTask = fetchAlerts()
        async let metricsTask = fetchDailyMetrics()
        async let lastMetricTask = fetchLastMetricDate()
        
        let vitality = await vitalityTask
        let alertsResult = await alertsTask
        let metrics = await metricsTask
        let lastDate = await lastMetricTask
        
        await MainActor.run {
            vitalityScore = vitality.score
            vitalityLabel = vitality.label
            vitalityTrendDelta = vitality.trendDelta
            vitalityHasMinimumData = vitality.hasMinimumData
            alerts = alertsResult
            sleepData = metrics.sleep
            movementData = metrics.movement
            stressData = metrics.stress
            daysWithMetricsLast7 = metrics.days
            lastMetricDate = lastDate
            isLoading = false
            animateProgress = true
        }
    }
    
    @MainActor
    func fetchVitality() async -> (score: Int, label: String, trendDelta: Int, hasMinimumData: Bool) {
        struct VitalityProfileRow: Decodable {
            let vitality_score_current: Int?
            let vitality_score_updated_at: String?
            let optimal_vitality_target: Int?
            let vitality_progress_score_current: Int?
        }
        
        struct VitalityScoreRow: Decodable {
            let score_date: String?
        }
        
        do {
            let supabase = SupabaseConfig.client
            let rows: [VitalityProfileRow] = try await supabase
                .from("user_profiles")
                .select("vitality_score_current, vitality_score_updated_at, optimal_vitality_target, vitality_progress_score_current")
                .eq("user_id", value: memberUserId)
                .limit(1)
                .execute()
                .value

            // Check how many days of vitality scores exist (for 7-day minimum)
            let scoreRows: [VitalityScoreRow] = try await supabase
                .from("vitality_scores")
                .select("score_date")
                .eq("user_id", value: memberUserId)
                .order("score_date", ascending: false)
                .limit(30)
                .execute()
                .value
            
            let hasMinimumData = scoreRows.count >= 7

            let row = rows.first
            let score = row?.vitality_score_current ?? 0
            let label = labelForScore(score)
            let deltaPercent = (try? await dataManager.fetchUserWeeklyVitalityDeltaPercent(userId: memberUserId)) ?? 0
            return (score, label, deltaPercent, hasMinimumData)
        } catch {
            print("❌ Profile: Failed to fetch vitality for \(memberUserId): \(error.localizedDescription)")
            return (0, "No data", 0, false)
        }
    }
    
    func fetchAlerts() async -> [PatternAlert] {
        do {
            let supabase = SupabaseConfig.client
            struct AlertRow: Decodable {
                let id: String
                let member_user_id: String
                let metric_type: String
                let pattern_type: String?
                let current_level: Int?
                let severity: String?
                let deviation_percent: Double?
                let baseline_value: Double?
                let recent_value: Double?
            }
            
            let rows: [AlertRow] = try await supabase
                .rpc("get_family_pattern_alerts", params: ["family_id": AnyJSON.string(familyId)])
                .execute()
                .value
            
            let filtered = rows.filter { $0.member_user_id.lowercased() == memberUserId.lowercased() }
            
            return filtered.map { row in
                PatternAlert(
                    id: row.id,
                    metricType: row.metric_type,
                    patternType: row.pattern_type,
                    currentLevel: row.current_level,
                    severity: row.severity ?? "watch",
                    summary: alertSummary(metric: row.metric_type, deviation: row.deviation_percent, baseline: row.baseline_value, recent: row.recent_value),
                    baselineValue: row.baseline_value,
                    recentValue: row.recent_value,
                    deviationPercent: row.deviation_percent
                )
            }
        } catch {
            print("❌ Profile: Failed to fetch alerts: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchDailyMetrics() async -> (sleep: ProfilePillarData?, movement: ProfilePillarData?, stress: ProfilePillarData?, days: Int) {
        struct MetricRow: Decodable {
            let metric_date: String?
            let steps: Int?
            let sleep_minutes: Int?
            let hrv_ms: Double?
            let resting_hr: Double?
        }
        
        do {
            let supabase = SupabaseConfig.client
            let rows: [MetricRow] = try await supabase
                .from("wearable_daily_metrics")
                .select("metric_date, steps, sleep_minutes, hrv_ms, resting_hr")
                .eq("user_id", value: memberUserId)
                .order("metric_date", ascending: false)
                .limit(21)
                .execute()
                .value
            
            let sorted = rows.compactMap { $0 }.prefix(21)
            let recent = Array(sorted.prefix(7))
            let baseline = Array(sorted.dropFirst(7))
            
            // Distinct days with any metrics in the last 7 entries
            let recentDaysWithMetrics = Set(
                recent.compactMap { $0.metric_date }
            ).count
            
            let sleep = computePillar(
                recentValues: recent.compactMap { $0.sleep_minutes }.map(Double.init),
                baselineValues: baseline.compactMap { $0.sleep_minutes }.map(Double.init),
                valueFormatter: { minutes in
                    let hours = minutes / 60.0
                    return String(format: "%.1f hours", hours)
                },
                contextLabel: "Sleep"
            )
            
            let movement = computePillar(
                recentValues: recent.compactMap { $0.steps }.map(Double.init),
                baselineValues: baseline.compactMap { $0.steps }.map(Double.init),
                valueFormatter: { steps in "\(Int(steps)) steps" },
                contextLabel: "Movement"
            )
            
            let stress = computePillar(
                recentValues: recent.compactMap { $0.hrv_ms },
                baselineValues: baseline.compactMap { $0.hrv_ms },
                valueFormatter: { hrv in "\(Int(hrv.rounded())) ms HRV" },
                contextLabel: "Recovery"
            )
            
            return (sleep, movement, stress, recentDaysWithMetrics)
        } catch {
            print("❌ Profile: Failed to fetch daily metrics: \(error.localizedDescription)")
            return (nil, nil, nil, 0)
        }
    }
    
    /// Returns the date of the most recent metric row for this user (max metric_date), or nil if none.
    func fetchLastMetricDate() async -> Date? {
        struct LastDateRow: Decodable {
            let metric_date: String?
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        do {
            let rows: [LastDateRow] = try await SupabaseConfig.client
                .from("wearable_daily_metrics")
                .select("metric_date")
                .eq("user_id", value: memberUserId)
                .order("metric_date", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let dateString = rows.first?.metric_date else { return nil }
            return formatter.date(from: dateString)
        } catch {
            print("❌ Profile: Failed to fetch last metric date: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches AI-generated insight for a pattern alert (headline, clinical interpretation, possible causes, action steps).
    /// Uses the miya_insight Edge Function; result is cached server-side.
    func fetchAIInsight(alertStateId: String) async {
        await MainActor.run {
            aiInsightHeadline = nil
            aiInsightClinicalInterpretation = nil
            aiInsightPossibleCauses = []
            aiInsightActionSteps = []
            aiInsightError = nil
            isLoadingAIInsight = true
        }
        do {
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
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId])
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                throw NSError(domain: "miya_insight", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: errBody])
            }
            await MainActor.run {
                aiInsightHeadline = obj?["headline"] as? String
                aiInsightClinicalInterpretation = obj?["clinical_interpretation"] as? String
                aiInsightPossibleCauses = obj?["possible_causes"] as? [String] ?? []
                aiInsightActionSteps = obj?["action_steps"] as? [String] ?? []
            }
        } catch {
            await MainActor.run {
                aiInsightError = error.localizedDescription
            }
        }
        await MainActor.run { isLoadingAIInsight = false }
    }
}

// MARK: - Data freshness (last metric date)

/// Classifies whether profile pillar data is current, old, or missing.
enum DataFreshness {
    case none   // no data at all
    case fresh  // at least one day within the last 7 calendar days
    case stale  // data exists but all days are older than 7 days
}

private func freshness(for lastMetricDate: Date?) -> DataFreshness {
    guard let last = lastMetricDate else { return .none }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let comps = calendar.dateComponents([.day], from: last, to: today)
    let diff = comps.day ?? Int.max
    if diff <= 6 { return .fresh }
    return .stale
}

// MARK: - Helpers

/// Short explanation of why this alert was triggered, tied to notification triggers (baseline + duration).
private func whyThisIsAnAlert(alert: PatternAlert, memberName: String) -> String {
    let pillar = displayNameForMetricType(alert.metricType)
    let direction: String
    if (alert.patternType ?? "").lowercased().contains("rise") {
        direction = "above"
    } else {
        direction = "below"
    }
    let days = alert.currentLevel ?? 3
    return "\(pillar) has been \(direction) \(memberName)'s baseline for \(days)+ days. We send alerts when a metric stays \(direction) baseline so the right people can check in early."
}

/// Maps raw metric_type from the backend to user-facing pillar names. Used for alert title and summary.
private func displayNameForMetricType(_ metricType: String) -> String {
    switch metricType.lowercased() {
    case "steps", "movement_minutes": return "Movement"
    case "sleep_minutes", "deep_sleep_minutes", "sleep_efficiency_pct": return "Sleep"
    case "hrv_ms", "resting_hr": return "Recovery"
    default:
        return metricType
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }
}

private extension FamilyMemberProfileView {
    func labelForScore(_ score: Int) -> String {
        switch score {
        case 80...100: return "Thriving"
        case 60..<80: return "Doing well"
        case 40..<60: return "Needs attention ⚠️"
        default: return "Focus needed"
        }
    }
    
    func alertSummary(metric: String, deviation: Double?, baseline: Double?, recent: Double?) -> String {
        let name = displayNameForMetricType(metric)
        guard let deviation = deviation, let baseline = baseline, let recent = recent else {
            return "\(name) alert"
        }
        let percent = Int((deviation) * 100)
        return "\(name) changed \(percent)% (current \(formatNumber(recent)) vs baseline \(formatNumber(baseline)))"
    }
    
    func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.0f", value)
    }
    
    func computePillar(
        recentValues: [Double],
        baselineValues: [Double],
        valueFormatter: (Double) -> String,
        contextLabel: String
    ) -> ProfilePillarData? {
        guard let recentAvg = recentValues.average else { return nil }
        let baselineAvg = baselineValues.average
        let changePercent: Int
        if let base = baselineAvg, base > 0 {
            changePercent = Int(((recentAvg - base) / base) * 100)
        } else {
            changePercent = 0
        }
        
        let status: PillarStatus
        if changePercent > 5 {
            status = .above
        } else if changePercent < -5 {
            status = .below
        } else {
            status = .stable
        }
        
        let arrow = changePercent > 0 ? "↑" : (changePercent < 0 ? "↓" : "→")
        let changeText = "\(arrow) \(abs(changePercent))% • \(statusText(status))"
        let context = baselineAvg != nil ? "\(contextLabel) vs baseline" : "Limited data"
        
        return ProfilePillarData(
            value: valueFormatter(recentAvg),
            status: status,
            changeText: changeText,
            context: context
        )
    }
    
    func statusText(_ status: PillarStatus) -> String {
        switch status {
        case .above: return "Above baseline"
        case .stable: return "Stable"
        case .below: return "Below baseline"
        }
    }
    
    func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last  = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combo = (first + last)
        return combo.isEmpty ? String(name.prefix(1)).uppercased() : combo.uppercased()
    }
}

// MARK: - Models
struct PatternAlert: Identifiable {
    let id: String
    let metricType: String
    let patternType: String?
    let currentLevel: Int?
    let severity: String
    let summary: String
    let baselineValue: Double?
    let recentValue: Double?
    let deviationPercent: Double?
    
    var title: String {
        "\(displayNameForMetricType(metricType)) Alert"
    }
}

struct ProfilePillarData {
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
}

enum PillarStatus {
    case above, stable, below
}

enum PillarType: Identifiable {
    case overview
    case movement
    case sleep
    case recovery

    var id: String {
        switch self {
        case .overview: return "overview"
        case .movement: return "movement"
        case .sleep: return "sleep"
        case .recovery: return "recovery"
        }
    }
}

// MARK: - Components
private struct HealthScoreCard: View {
    let memberName: String
    let score: Int
    let statusText: String
    let trendDelta: Int
    let hasMinimumData: Bool
    let animateProgress: Bool
    let onAskMiya: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(memberName)’s Health")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Text("\(score)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.miyaSage)
            }
            
            HStack(alignment: .firstTextBaseline) {
                Text(statusText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)

                Spacer()

                // Only show trend if we have at least 7 days of data
                if hasMinimumData {
                    let showTrend = abs(trendDelta) >= 6
                    if showTrend {
                        let isUp = trendDelta > 0
                        HStack(spacing: 6) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            Text("\(isUp ? "Up" : "Down") \(abs(trendDelta))% from last week")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isUp ? .miyaSage : .miyaTerracotta)
                    }
                } else {
                    Text("Building baseline...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressBar(progress: animateProgress ? CGFloat(max(0, min(score, 100))) / 100.0 : 0)
                .frame(height: 8)
            
            if let onAskMiya {
                Button(action: onAskMiya) {
                    HStack(spacing: 10) {
                        Text("🤖")

                        Text("See how \(memberName) is doing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.miyaSage.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

private struct ProgressBar: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.miyaSurfaceGrey)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color.miyaSageDark, Color.miyaSageLight], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * progress)
                    .animation(.easeOut(duration: 1.0), value: progress)
            }
        }
    }
}

private struct AlertCardView: View {
    let alert: PatternAlert
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.miyaTerracottaDark)
                    Spacer()
                    Text(alert.severity.capitalized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTerracottaDark)
                }
                
                Text(alert.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
                
                HStack(spacing: 6) {
                    Text("View insight")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTerracotta)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTerracotta)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.miyaTerracotta.opacity(0.05), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.miyaTerracotta, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct AlertInsightDetailView: View {
    let alert: PatternAlert
    let memberName: String
    let aiInsightHeadline: String?
    let aiInsightClinicalInterpretation: String?
    let aiInsightPossibleCauses: [String]
    let aiInsightActionSteps: [String]
    let isLoadingAIInsight: Bool
    let aiInsightError: String?
    let whyThisIsAnAlertText: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Overview
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    Text(alert.summary)
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                // Why this is an alert (relates to notification triggers)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why this is an alert")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(whyThisIsAnAlertText)
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.miyaSurfaceGrey.opacity(0.6))
                .cornerRadius(12)
                
                // Deeper insights (AI-generated)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Deeper insights")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    if isLoadingAIInsight {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading insights…")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(.vertical, 16)
                    } else if let error = aiInsightError {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.miyaTerracotta)
                            Text("We couldn’t load the full insight right now. \(error)")
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.miyaTerracotta.opacity(0.08))
                        .cornerRadius(12)
                    } else if let headline = aiInsightHeadline, let clinical = aiInsightClinicalInterpretation {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(headline)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(clinical)
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !aiInsightPossibleCauses.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Possible causes")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.miyaTextPrimary)
                                    ForEach(Array(aiInsightPossibleCauses.enumerated()), id: \.offset) { _, cause in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundColor(.miyaTextSecondary)
                                            Text(cause)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextSecondary)
                                        }
                                    }
                                }
                            }
                            if !aiInsightActionSteps.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Suggested steps")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.miyaTextPrimary)
                                    ForEach(Array(aiInsightActionSteps.enumerated()), id: \.offset) { i, step in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(i + 1).")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.miyaSageDark)
                                            Text(step)
                                                .font(.system(size: 14))
                                                .foregroundColor(.miyaTextSecondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.miyaCardWhite)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    }
                }
                
                Spacer(minLength: 24)
            }
        }
    }
}

private struct PillarCardView: View {
    let icon: String
    let title: String
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
    let pillarType: PillarType
    
    enum PillarType {
        case sleep, movement, stress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
            }
            
            HStack(spacing: 8) {
                statusIcon
                Text(changeText)
                    .font(.system(size: 14))
            }
            .foregroundColor(.miyaTextSecondary)
            
            Text(context)
                .font(.system(size: 13))
                .foregroundColor(.miyaTextTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(gradientBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
    
    private var gradientBackground: LinearGradient {
        switch pillarType {
        case .sleep:
            return LinearGradient(colors: [Color.miyaLavender.opacity(0.08), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .movement:
            if status == .below {
                return LinearGradient(colors: [Color.miyaTerracotta.opacity(0.08), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                return LinearGradient(colors: [Color.miyaSage.opacity(0.08), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .stress:
            return LinearGradient(colors: [Color.miyaSkyBlue.opacity(0.08), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var borderColor: Color {
        switch pillarType {
        case .sleep:
            return Color.miyaLavender
        case .movement:
            if status == .below { return Color.miyaTerracotta } else { return Color.miyaSage }
        case .stress:
            return status == .below ? Color.miyaTerracotta : Color.miyaSkyBlue
        }
    }
    
    private var statusIcon: some View {
        let arrow: String
        let color: Color
        switch status {
        case .above:
            arrow = "arrow.up"
            color = .miyaSage
        case .stable:
            arrow = "arrow.right"
            color = .miyaSkyBlue
        case .below:
            arrow = "arrow.down"
            color = .miyaTerracotta
        }
        
        return Image(systemName: arrow)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(color)
    }
}

// MARK: - Utils
private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        let total = reduce(0, +)
        return total / Double(count)
    }
}

// MARK: - Weekly Vitality % Change (week-over-week)
extension DataManager {
    /// Returns rounded % change between current 7-day avg vs previous 7-day avg of `vitality_scores.total_score`.
    /// - Notes:
    ///   - Current week = last 7 days (including today)
    ///   - Previous week = 7 days before that
    ///   - Returns nil if not enough data or previous avg is 0.
    func fetchUserWeeklyVitalityDeltaPercent(userId: String) async throws -> Int? {
        struct VitalityTotalRow: Decodable {
            let score_date: String
            let total_score: Int?
        }

        // Build the last 14 calendar days (inclusive of today)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func dateString(for offsetDaysAgo: Int) -> String {
            let d = calendar.date(byAdding: .day, value: -offsetDaysAgo, to: today) ?? today
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            return df.string(from: d)
        }

        let cutoffString = dateString(for: 13) // 14-day window: today-13 ... today

        let supabase = SupabaseConfig.client
        let rows: [VitalityTotalRow] = try await supabase
            .from("vitality_scores")
            .select("score_date, total_score")
            .eq("user_id", value: userId)
            .gte("score_date", value: cutoffString)
            .order("score_date", ascending: true)
            .execute()
            .value

        // Map for lookup by date string
        var byDate: [String: Int] = [:]
        for r in rows {
            if let v = r.total_score {
                byDate[r.score_date] = v
            }
        }

        // Current week: 0...6 days ago, Previous week: 7...13 days ago
        var currentWeek: [Int] = []
        var previousWeek: [Int] = []

        for dayAgo in 0...6 {
            let key = dateString(for: dayAgo)
            if let v = byDate[key] { currentWeek.append(v) }
        }
        for dayAgo in 7...13 {
            let key = dateString(for: dayAgo)
            if let v = byDate[key] { previousWeek.append(v) }
        }

        // Need enough data to be meaningful
        guard currentWeek.count >= 3, previousWeek.count >= 3 else { return nil }

        func avg(_ xs: [Int]) -> Double {
            Double(xs.reduce(0, +)) / Double(xs.count)
        }

        let currentAvg = avg(currentWeek)
        let previousAvg = avg(previousWeek)
        guard previousAvg > 0 else { return nil }

        let delta = ((currentAvg - previousAvg) / previousAvg) * 100.0
        return Int(delta.rounded())
    }
}
#Preview("Family Member Profile Preview") {
    NavigationStack {
        FamilyMemberProfileView(
            memberUserId: "preview-user",
            memberName: "Rami",
            familyId: "preview-family",
            isCurrentUser: false,
            previewMock: true
        )
        .onAppear {
            // Inject preview-only fake UI state
        }
    }
}

// MARK: - Pillar (Whoop/Apple-style UI variants)
private struct MovementHeroPillarCard: View {
    let icon: String
    let title: String
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
    let pillarType: PillarCardView.PillarType

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(icon)
                    .font(.system(size: 22))

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                StatusChip(status: status, text: statusLabel)
            }

            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.miyaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline) {
                Text(changeText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)

                Spacer()

                Text(context)
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextTertiary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var background: LinearGradient {
        switch pillarType {
        case .movement:
            return LinearGradient(
                colors: [Color.miyaSage.opacity(0.14), Color.miyaCardWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sleep:
            return LinearGradient(
                colors: [Color.miyaLavender.opacity(0.14), Color.miyaCardWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .stress:
            return LinearGradient(
                colors: [Color.miyaSkyBlue.opacity(0.14), Color.miyaCardWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch pillarType {
        case .movement: return Color.miyaSage
        case .sleep: return Color.miyaLavender
        case .stress: return Color.miyaSkyBlue
        }
    }

    private var statusLabel: String {
        switch status {
        case .above: return "Above"
        case .stable: return "Stable"
        case .below: return "Below"
        }
    }
}

private struct CompactPillarCard: View {
    let icon: String
    let title: String
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
    let pillarType: PillarType
    let onDiveDeeper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(icon)
                        .font(.system(size: 18))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                StatusChip(status: status, text: statusLabel)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.miyaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(changeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
                .lineLimit(1)

            Button(action: onDiveDeeper) {
                Text("Dive deeper →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.miyaTextTertiary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private var borderColor: Color {
        switch pillarType {
        case .sleep: return Color.miyaLavender
        case .movement: return Color.miyaSage
        case .recovery: return Color.miyaSkyBlue
        case .overview:
            return Color.miyaSageLight
        }
    }

    private var statusLabel: String {
        switch status {
        case .above: return "Above"
        case .stable: return "Stable"
        case .below: return "Below"
        }
    }
}

private struct StatusChip: View {
    let status: PillarStatus
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .foregroundColor(foreground)
            .background(foreground.opacity(0.12))
            .cornerRadius(999)
    }

    private var foreground: Color {
        switch status {
        case .above: return .miyaSage
        case .stable: return .miyaSkyBlue
        case .below: return .miyaTerracotta
        }
    }
}
private struct ThinPillarRow: View {
    let title: String
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)

                    Spacer(minLength: 10)

                    StatusChip(status: status, text: statusLabel)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(changeText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.miyaTextTertiary)
                }

                Text(context)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.miyaTextTertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.miyaCardWhite)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        switch title {
        case "Sleep":
            return Color.miyaLavender
        case "Recovery":
            return Color.miyaSkyBlue
        default:
            return Color.miyaSage
        }
    }

    private var statusLabel: String {
        switch status {
        case .above: return "Above"
        case .stable: return "Stable"
        case .below: return "Below"
        }
    }
}



private struct PillarDiveDeeperSheet: View {
    let memberUserId: String
    let memberName: String
    let vitalityScore: Int
    let vitalityDeltaPercent: Int
    let pillar: PillarType
    let movement: ProfilePillarData?
    let sleep: ProfilePillarData?
    let recovery: ProfilePillarData?

    @EnvironmentObject private var dataManager: DataManager

    private enum PillarRange: Int, CaseIterable, Identifiable {
        case days30 = 30
        case days60 = 60
        case days90 = 90
        var id: Int { rawValue }
        var label: String { "\(rawValue)d" }
    }

    private struct ChartPoint: Identifiable {
        let id: String
        let date: Date
        let value: Int
    }

    private enum Trend { case improving, stable, declining }
    private enum DataQuality { case high, medium, low }

    @State private var selectedRange: PillarRange = .days30
    @State private var history: [(date: String, value: Int?)] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil

    // Structured chat state
    @State private var chatInput: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var selectedIntent: String? = nil
    @State private var isSending: Bool = false
    @State private var scrollToBottomTrigger: Int = 0
    @State private var showPills: Bool = true  // Control pill visibility
    
    // Dynamic pills state
    @State private var dynamicPills: [Pill] = []
    @State private var usedPillIds: Set<String> = []

    // Structured chat message model
    private struct ChatMessage: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        let intent: String?
    }

    // MARK: - Member Overview Facts (Structured, deterministic)
    private struct MemberOverviewFacts: Encodable {
        let memberId: String
        let memberName: String

        let vitalityScore: Int
        let vitalityDeltaPercent: Int

        let sleepValue: String?
        let sleepChangeText: String?

        let movementValue: String?
        let movementChangeText: String?

        let recoveryValue: String?
        let recoveryChangeText: String?
    }

    private var memberOverviewFacts: MemberOverviewFacts {
        MemberOverviewFacts(
            memberId: memberUserId,
            memberName: memberName,
            vitalityScore: vitalityScore,
            vitalityDeltaPercent: vitalityDeltaPercent,

            sleepValue: sleep?.value,
            sleepChangeText: sleep?.changeText,

            movementValue: movement?.value,
            movementChangeText: movement?.changeText,

            recoveryValue: recovery?.value,
            recoveryChangeText: recovery?.changeText
        )
    }
    // MARK: - Send message to member-specific Miya chat
    @MainActor
    private func sendMessage(intent: String?) async {
        guard !messages.isEmpty else { return }

        isSending = true

        do {
            // Encode structured facts deterministically (no AI generation here)
            let factsData = try JSONEncoder().encode(memberOverviewFacts)
            let factsJSON = String(data: factsData, encoding: .utf8) ?? "{}"

            let payloadMessages: [ArloMemberChatAPI.APIMessage] = messages.map { msg in
                ArloMemberChatAPI.APIMessage(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.text
                )
            }

            let reply = try await ArloMemberChatAPI.sendMemberOverview(
                memberUserId: memberUserId,
                memberName: memberName,
                intent: intent,
                factsJSON: factsJSON,
                messages: payloadMessages
            )

            await MainActor.run {
                isSending = false
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: reply.reply,
                        intent: intent
                    )
                )
                
                // Update dynamic pills from backend
                if let suggestedPrompts = reply.suggested_prompts {
                    dynamicPills = suggestedPrompts.map { prompt in
                        Pill(id: prompt.id, title: prompt.title, intent: prompt.intent)
                    }
                }
                
                // Mark current pill/intent as used (both ID and intent to catch all variations)
                if let currentIntent = intent {
                    usedPillIds.insert(currentIntent)
                    // Also mark shorter ID versions (e.g., "well" from "member_doing_well")
                    if currentIntent.starts(with: "member_") {
                        let shortId = currentIntent.replacingOccurrences(of: "member_", with: "")
                            .replacingOccurrences(of: "doing_", with: "")
                            .replacingOccurrences(of: "needs_", with: "")
                        usedPillIds.insert(shortId)
                    }
                }
                
                showPills = true  // Show pills after assistant responds
                scrollToBottomTrigger += 1
            }
        } catch {
            await MainActor.run {
                isSending = false
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "Sorry — I couldn’t load insights right now.",
                        intent: intent
                    )
                )
                scrollToBottomTrigger += 1
            }
        }
    }

    // MARK: - Overview Pills (deterministic)
    private struct Pill: Identifiable {
        let id: String
        let title: String
        let intent: String
    }

    // Static initial pills (fallback when no dynamic pills)
    private var staticInitialPills: [Pill] {
        var pills: [Pill] = []

        pills.append(.init(id: "well", title: "What is \(memberName) doing well?", intent: "member_doing_well"))
        pills.append(.init(id: "support", title: "Where does \(memberName) need support?", intent: "member_needs_support"))

        if sleep != nil {
            pills.append(.init(id: "sleep", title: "How is \(memberName)’s sleep?", intent: "member_sleep"))
        }
        if movement != nil {
            pills.append(.init(id: "move", title: "How is \(memberName)’s movement?", intent: "member_movement"))
        }
        if recovery != nil {
            pills.append(.init(id: "rec", title: "How is \(memberName)’s recovery?", intent: "member_recovery"))
        }

        return Array(pills.prefix(4))
    }
    
    // Dynamic pills with used pill filtering
    private var displayedPills: [Pill] {
        // Use dynamic pills if available, otherwise fallback to static
        let pillsToShow = dynamicPills.isEmpty ? staticInitialPills : dynamicPills
        // Filter out pills that have been used (by ID or intent)
        return pillsToShow.filter { pill in
            !usedPillIds.contains(pill.id) && !usedPillIds.contains(pill.intent)
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if pillar == .overview {
                    // Overview UI (no chart)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                overviewSummaryCard

                                // Messages with pills anchored to last assistant message
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(messages) { msg in
                                        VStack(alignment: msg.role == .assistant ? .leading : .trailing, spacing: 8) {
                                            HStack {
                                                if msg.role == .user {
                                                    Spacer(minLength: 0)
                                                }

                                                Text(msg.text)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.miyaTextPrimary)
                                                    .padding(12)
                                                    .background(
                                                        msg.role == .assistant
                                                        ? Color.miyaSage.opacity(0.15)
                                                        : Color.miyaSurfaceGrey.opacity(0.35)
                                                    )
                                                    .cornerRadius(14)
                                                    .frame(maxWidth: .infinity, alignment: msg.role == .assistant ? .leading : .trailing)

                                                if msg.role == .assistant {
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                            
                                            // Pills anchored to LAST assistant message only
                                            if msg.role == .assistant,
                                               msg.id == messages.last?.id,
                                               showPills {
                                                overviewPillBar
                                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                        }
                                    }

                                    if isSending {
                                        HStack {
                                            TypingIndicatorBubble()
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }

                                Spacer(minLength: 40)

                                Color.clear.frame(height: 1).id("overviewChatBottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: scrollToBottomTrigger) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("overviewChatBottom", anchor: .bottom)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        Divider().opacity(0.18)
                        HStack(spacing: 10) {
                            TextField("Write a reply…", text: $chatInput)
                                .font(.system(size: 15))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.miyaSurfaceGrey.opacity(0.16))
                                .cornerRadius(16)

                            Button(action: {
                                let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }

                                let intentTag = selectedIntent
                                
                                // Hide pills when user sends text message
                                showPills = false

                                messages.append(
                                    ChatMessage(
                                        role: .user,
                                        text: trimmed,
                                        intent: intentTag
                                    )
                                )
                                chatInput = ""
                                selectedIntent = nil

                                Task { await sendMessage(intent: intentTag) }
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(.miyaSage)
                            }
                            .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.miyaCardWhite.ignoresSafeArea(edges: .bottom))
                    }

                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            rangeSelector
                            chartCard
                            insightsCard
                            Spacer(minLength: 28)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            // Seed opening message for chat if empty
            if pillar == .overview && messages.isEmpty {
                messages = [
                    ChatMessage(
                        role: .assistant,
                        text: "I'm here to help with \(memberName)'s health. What would you like to know?",
                        intent: nil
                    )
                ]
                showPills = true
            }
            
            guard pillar != .overview else { return }
            await loadHistory(days: 90)
        }
        .onChange(of: pillar) { _, newValue in
            guard newValue != .overview else { return }
            Task { await loadHistory(days: 90) }
        }
        .onChange(of: memberUserId) { _, _ in
            guard pillar != .overview else { return }
            Task { await loadHistory(days: 90) }
        }
    }

    // MARK: - Overview Pill Bar
    private var overviewPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(displayedPills) { pill in
                    Button {
                        let intent = pill.intent
                        selectedIntent = intent
                        
                        // Mark pill as used (both ID and intent)
                        usedPillIds.insert(pill.id)
                        usedPillIds.insert(pill.intent)
                        
                        // Hide pills immediately on tap
                        showPills = false

                        // 1) append user bubble immediately
                        messages.append(
                            ChatMessage(
                                role: .user,
                                text: pill.title,
                                intent: intent
                            )
                        )

                        // 2) clear the input (optional)
                        chatInput = ""

                        // 3) scroll to bottom so new message and reply are in view
                        scrollToBottomTrigger += 1

                        // 4) trigger send immediately
                        Task { await sendMessage(intent: intent) }
                    } label: {
                        Text(pill.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.miyaCardWhite)
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Range selector
    private var rangeSelector: some View {
        HStack(spacing: 10) {
            Text("Trend")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Spacer()

            Picker("Range", selection: $selectedRange) {
                ForEach(PillarRange.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }

    // MARK: - Chart
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chartTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                Text("Last \(selectedRange.rawValue) days")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading chart…")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(.vertical, 18)

            } else if let err = loadError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn’t load trend")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTerracottaDark)
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(.vertical, 12)

            } else if chartPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Not enough data yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Text("Wear and sync consistently to see a clearer trend here.")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(.vertical, 12)

            } else {
                Chart {
                    ForEach(chartPoints) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value("Score", p.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accentColor)

                        AreaMark(
                            x: .value("Date", p.date),
                            y: .value("Score", p.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.22), accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                        AxisTick().foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month().day(), centered: true)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.miyaTextTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                        AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                        AxisTick().foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel() {
                            if let iv = v.as(Int.self) {
                                Text("\(iv)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.miyaTextTertiary)
                            }
                        }
                    }
                }
                .frame(height: 190)
            }
        }
        .padding(16)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Insights (deterministic)
    private var insightsCard: some View {
        let (trend, quality) = computeTrendAndQuality()
        let summary = insightText(trend: trend, quality: quality)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Insights")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                if quality == .low {
                    Text("Limited data")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.miyaTextTertiary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.miyaSurfaceGrey.opacity(0.5))
                        .cornerRadius(999)
                }
            }

            Text(summary)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Data loading
    private func loadHistory(days: Int) async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        do {
            let vp = vitalityPillar(for: pillar)
            let rows = try await dataManager.fetchUserPillarHistory(
                userId: memberUserId,
                pillar: vp,
                days: days
            )

            await MainActor.run {
                history = rows // already ascending by date
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = (error as NSError).localizedDescription
            }
        }
    }

    // MARK: - Derived: points
    private var chartPoints: [ChartPoint] {
        let slice = sliceHistory(for: selectedRange)
        return slice.compactMap { item in
            guard let v = item.value else { return nil }
            guard let d = dateFormatter.date(from: item.date) else { return nil }
            return ChartPoint(id: item.date, date: d, value: v)
        }
    }

    private func sliceHistory(for range: PillarRange) -> [(date: String, value: Int?)] {
        guard !history.isEmpty else { return [] }
        let n = min(range.rawValue, history.count)
        return Array(history.suffix(n)) // most recent N, still ascending inside the slice
    }

    // MARK: - Trend + quality
    private func computeTrendAndQuality() -> (Trend, DataQuality) {
        if isLoading || loadError != nil {
            return (.stable, .low)
        }

        let slice = sliceHistory(for: selectedRange)
        let values = slice.compactMap { $0.value }

        let ratio: Double = slice.isEmpty ? 0 : Double(values.count) / Double(slice.count)
        let quality: DataQuality
        if ratio >= 0.8 { quality = .high }
        else if ratio >= 0.5 { quality = .medium }
        else { quality = .low }

        guard values.count >= 3 else {
            return (.stable, quality)
        }

        let half = max(1, values.count / 2)
        let prior = Array(values.prefix(values.count - half))
        let recent = Array(values.suffix(half))

        let delta = average(recent) - average(prior)

        if delta >= 3 { return (.improving, quality) }
        if delta <= -3 { return (.declining, quality) }
        return (.stable, quality)
    }

    private func average(_ ints: [Int]) -> Double {
        guard !ints.isEmpty else { return 0 }
        return Double(ints.reduce(0, +)) / Double(ints.count)
    }

    private func insightText(trend: Trend, quality: DataQuality) -> String {
        let prefix = (quality == .low) ? "Based on limited data so far. " : ""

        // If not enough usable values, return pillar-specific low-data guidance.
        let slice = sliceHistory(for: selectedRange)
        let valuesCount = slice.compactMap { $0.value }.count
        if valuesCount < 3 {
            switch pillar {
            case .movement:
                return "Not enough movement trend data yet. Keep syncing daily and you’ll start seeing patterns here soon."
            case .sleep:
                return "Not enough sleep trend data yet. Keep wearing your device at night to build a clearer picture."
            case .recovery:
                return "Not enough recovery trend data yet. As more days sync, you’ll see how strain and rest are interacting."
            case .overview:
                return "Not enough data yet."
            }
        }

        switch pillar {
        case .movement:
            switch trend {
            case .improving:
                return prefix + "Movement is trending up — consistency is paying off. Keep a simple baseline (steps) and 2–3 purposeful sessions per week to hold the gains."
            case .stable:
                return prefix + "Movement is steady. One small upgrade: add a 10–15 minute walk on non-training days — it compounds fast."
            case .declining:
                return prefix + "Movement has dipped versus earlier weeks. A realistic fix is 2–3 short walks this week to stop the slide before it becomes a pattern."
            }

        case .sleep:
            switch trend {
            case .improving:
                return prefix + "Sleep is improving across this window. Protect a consistent wind-down and keep the last hour calmer (lower light, fewer screens)."
            case .stable:
                return prefix + "Sleep is stable. If you want to push it up, anchor bedtime and keep caffeine earlier in the day."
            case .declining:
                return prefix + "Sleep has slipped. Two simple fixes: pull bedtime 20–30 minutes earlier and reduce stimulation late evening to avoid carrying the day into bed."
            }

        case .recovery:
            switch trend {
            case .improving:
                return prefix + "Recovery is trending up — your body is handling strain better. Keep sleep steady and avoid stacking hard days back-to-back."
            case .stable:
                return prefix + "Recovery is steady. The biggest levers are sleep consistency and matching intensity to how you feel on lower-energy days."
            case .declining:
                return prefix + "Recovery has come down, often from higher strain or less rest. Prioritise sleep and add an easier day before increasing training volume."
            }

        case .overview:
            return prefix + "Overall patterns look stable."
        }
    }

    // MARK: - Mapping
    private func vitalityPillar(for pillar: PillarType) -> VitalityPillar {
        switch pillar {
        case .sleep: return .sleep
        case .movement: return .movement
        case .recovery: return .stress
        case .overview: return .movement // not used
        }
    }

    // MARK: - Header / Styling
    private var chartTitle: String {
        switch pillar {
        case .movement: return "Movement score"
        case .sleep: return "Sleep score"
        case .recovery: return "Recovery score"
        case .overview: return "Overview"
        }
    }

    private var sheetTitle: String {
        switch pillar {
        case .overview: return "\(memberName) • Overview"
        case .movement: return "Movement"
        case .sleep: return "Sleep"
        case .recovery: return "Recovery"
        }
    }

    private var accentColor: Color {
        switch pillar {
        case .movement: return .miyaSage
        case .sleep: return .miyaLavender
        case .recovery: return .miyaSkyBlue
        case .overview: return .miyaSageLight
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color.miyaSage.opacity(0.65),
                Color.miyaSageLight.opacity(0.45),
                Color.miyaCreamBg
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.14))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            HStack {
                Text(sheetTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                if pillar == .overview {
                    Text("Last 7–30 days")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                } else {
                    Text("Last \(selectedRange.rawValue) days")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.35)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Overview card (kept)
    private var overviewSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(memberName)’s health overview")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            Text(overviewText)
                .font(.system(size: 14))
                .foregroundColor(.miyaTextSecondary)
        }
        .padding(16)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var overviewText: String {
        let movementSentence = movement != nil ? "Movement has been consistent." : "Movement data is limited."
        let sleepSentence = sleep != nil ? "Sleep has been averaging \(sleep?.value ?? "—")." : "Sleep data is limited."
        let recoverySentence = recovery != nil
            ? "Recovery has been trending down slightly, which may reflect increased strain or reduced rest."
            : "Recovery data is limited."

        return """
        Over the last few weeks, \(memberName)’s overall health has remained relatively stable.

        \(movementSentence) \(sleepSentence) \(recoverySentence)

        Is there anything specific you’d like to dive into?
        """
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }
}

// MARK: - Typing Indicator
private struct TypingIndicatorBubble: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6).opacity(dotOpacity(0))
            Circle().frame(width: 6, height: 6).opacity(dotOpacity(1))
            Circle().frame(width: 6, height: 6).opacity(dotOpacity(2))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotOpacity(_ index: Int) -> Double {
        let base = Double(phase)
        let offset = Double(index) * 0.25
        return 0.25 + 0.75 * (0.5 + 0.5 * sin((base + offset) * .pi * 2))
    }
}

