import SwiftUI
import Supabase

// MARK: - Family Member Profile (New Design)
struct FamilyMemberProfileView: View {
    let memberUserId: String
    let memberName: String
    let familyId: String
    
    // Loading / error
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    
    // Vitality
    @State private var vitalityScore: Int = 0
    @State private var vitalityLabel: String = ""
    @State private var vitalityTrendDelta: Int = 0
    
    // Alerts
    @State private var alerts: [PatternAlert] = []
    @State private var selectedAlert: PatternAlert?
    @State private var showAlertDetail: Bool = false
    
    // Pillars
    @State private var sleepData: ProfilePillarData?
    @State private var movementData: ProfilePillarData?
    @State private var stressData: ProfilePillarData?
    
    // Animation
    @State private var animateProgress: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaCreamBg.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    healthScoreSection
                    alertsSection
                    pillarsSection
                    trendsSection
                    askMiyaSection
                    currentChallengeSection
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
            await fetchMemberData()
        }
        .sheet(isPresented: $showAlertDetail) {
            if let alert = selectedAlert {
                // TODO: Integrate with FamilyNotificationDetailSheet when available
                VStack(spacing: 16) {
                    Text(alert.title)
                        .font(.headline)
                    Text(alert.summary)
                        .font(.subheadline)
                        .foregroundColor(.miyaTextSecondary)
                    Button("Close") { showAlertDetail = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationDetents([.medium])
            }
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
                    Text(initials(from: memberName))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(memberName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Text("Member in your family")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
            
            Spacer()
        }
    }
    
    var healthScoreSection: some View {
        HealthScoreCard(
            memberName: memberName,
            score: vitalityScore,
            statusText: vitalityLabel,
            trendDelta: vitalityTrendDelta,
            animateProgress: animateProgress
        )
    }
    
    var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("⚠️ Health Alerts")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
            }
            
            if alerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ No active health alerts")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaSageDark)
                    Text("All metrics within normal range")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(20)
                .background(Color.miyaCardWhite)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            } else {
                ForEach(alerts) { alert in
                    AlertCardView(alert: alert) {
                        selectedAlert = alert
                        showAlertDetail = true
                    }
                }
            }
        }
    }
    
    var pillarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 Health Pillars (Last 7 days)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
            
            if let sleep = sleepData {
                PillarCardView(
                    icon: "🌙",
                    title: "Sleep",
                    value: sleep.value,
                    status: sleep.status,
                    changeText: sleep.changeText,
                    context: sleep.context,
                    pillarType: .sleep
                )
            }
            
            if let movement = movementData {
                PillarCardView(
                    icon: "🚶",
                    title: "Movement",
                    value: movement.value,
                    status: movement.status,
                    changeText: movement.changeText,
                    context: movement.context,
                    pillarType: .movement
                )
            }
            
            if let stress = stressData {
                PillarCardView(
                    icon: "💗",
                    title: "Recovery",
                    value: stress.value,
                    status: stress.status,
                    changeText: stress.changeText,
                    context: stress.context,
                    pillarType: .stress
                )
            }
        }
    }
    
    var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📈 Explore Trends")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
            
            VStack(spacing: 8) {
                trendsLink(title: "Movement history →")
                trendsLink(title: "Sleep patterns →")
                trendsLink(title: "Stress insights →")
                trendsLink(title: "All past alerts →")
            }
            .padding(12)
            .background(Color.miyaCardWhite)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
    
    var askMiyaSection: some View {
        Button {
            // TODO: Integrate with Miya chat for the member
            print("Ask Miya about \(memberName)")
        } label: {
            HStack(spacing: 10) {
                Text("🤖")
                Text("Ask Miya about \(memberName)")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.miyaSage, Color.miyaSageLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
    }
    
    var currentChallengeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current challenge")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextSecondary)
            
            VStack(spacing: 8) {
                Image(systemName: "trophy")
                    .font(.system(size: 24))
                    .foregroundColor(.miyaTextSecondary)
                
                Text("No active challenge for \(memberName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("Start a new family challenge from the main dashboard and \(memberName)’s streak and dots will show here.")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    // Placeholder action
                } label: {
                    Text("Challenge \(memberName)")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.miyaSage)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .padding(20)
        .background(Color.miyaCardWhite)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
    
    func trendsLink(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.miyaSage)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.miyaSage)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.miyaSurfaceGrey)
        .cornerRadius(8)
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
        
        let vitality = await vitalityTask
        let alertsResult = await alertsTask
        let metrics = await metricsTask
        
        await MainActor.run {
            vitalityScore = vitality.score
            vitalityLabel = vitality.label
            vitalityTrendDelta = vitality.trendDelta
            alerts = alertsResult
            sleepData = metrics.sleep
            movementData = metrics.movement
            stressData = metrics.stress
            isLoading = false
            animateProgress = true
        }
    }
    
    func fetchVitality() async -> (score: Int, label: String, trendDelta: Int) {
        struct VitalityProfileRow: Decodable {
            let vitality_score_current: Int?
            let vitality_score_updated_at: String?
            let optimal_vitality_target: Int?
            let vitality_progress_score_current: Int?
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
            
            let row = rows.first
            let score = row?.vitality_score_current ?? 0
            let label = labelForScore(score)
            let trend = row?.vitality_progress_score_current ?? 0
            return (score, label, trend)
        } catch {
            print("❌ Profile: Failed to fetch vitality for \(memberUserId): \(error.localizedDescription)")
            return (0, "No data", 0)
        }
    }
    
    func fetchAlerts() async -> [PatternAlert] {
        do {
            let supabase = SupabaseConfig.client
            struct AlertRow: Decodable {
                let id: String
                let member_user_id: String
                let metric_type: String
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
                    severity: row.severity ?? "watch",
                    summary: alertSummary(metric: row.metric_type, deviation: row.deviation_percent, baseline: row.baseline_value, recent: row.recent_value)
                )
            }
        } catch {
            print("❌ Profile: Failed to fetch alerts: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchDailyMetrics() async -> (sleep: ProfilePillarData?, movement: ProfilePillarData?, stress: ProfilePillarData?) {
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
            
            return (sleep, movement, stress)
        } catch {
            print("❌ Profile: Failed to fetch daily metrics: \(error.localizedDescription)")
            return (nil, nil, nil)
        }
    }
}

// MARK: - Helpers
private extension FamilyMemberProfileView {
    func labelForScore(_ score: Int) -> String {
        switch score {
        case 80...100: return "Thriving 🌟"
        case 60..<80: return "Doing well"
        case 40..<60: return "Needs attention ⚠️"
        default: return "Focus needed"
        }
    }
    
    func alertSummary(metric: String, deviation: Double?, baseline: Double?, recent: Double?) -> String {
        guard let deviation = deviation, let baseline = baseline, let recent = recent else {
            return "\(metric.capitalized) alert"
        }
        let percent = Int((deviation) * 100)
        return "\(metric.capitalized) changed \(percent)% (current \(formatNumber(recent)) vs baseline \(formatNumber(baseline)))"
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
    let severity: String
    let summary: String
    
    var title: String {
        switch metricType.lowercased() {
        case "steps": return "Movement Alert"
        case "sleep_minutes": return "Sleep Alert"
        case "hrv_ms": return "Stress Alert"
        case "resting_hr": return "Resting HR Alert"
        default: return "Health Alert"
        }
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

// MARK: - Components
private struct HealthScoreCard: View {
    let memberName: String
    let score: Int
    let statusText: String
    let trendDelta: Int
    let animateProgress: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(memberName)’s Health")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Text("\(score) 🌟")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.miyaSage)
            }
            
            Text(statusText)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
            
            ProgressBar(progress: animateProgress ? CGFloat(max(0, min(score, 100))) / 100.0 : 0)
                .frame(height: 8)
            
            HStack {
                Text("\(score) out of 100 • Optimal range")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextTertiary)
                Spacer()
                if trendDelta != 0 {
                    let isUp = trendDelta > 0
                    HStack(spacing: 6) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        Text("\(isUp ? "Up" : "Down") \(abs(trendDelta)) points from last week")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isUp ? .miyaSage : .miyaTerracotta)
                }
            }
            .font(.system(size: 14))
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
