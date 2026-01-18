import SwiftUI

// MARK: - VITALITY FACTOR DETAIL SHEET

struct VitalityFactorDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let factor: VitalityFactor
    let dataManager: DataManager
    
    @State private var memberDetails: [PillarMemberDetail] = []
    @State private var isLoading = true
    @State private var hasAnyBackfilledData = false
    @State private var oldestSourceAgeInDays: Int = 0
    
    // Map factor name to pillar
    private var pillar: VitalityPillar {
        switch factor.name.lowercased() {
        case "sleep": return .sleep
        case "activity": return .movement
        case "recovery": return .stress
        default: return .sleep
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Title row (icon + name)
                    HStack(spacing: 8) {
                        Image(systemName: factor.iconName)
                            .font(.system(size: 20))
                        Text(factor.name)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .foregroundColor(.miyaTextPrimary)
                    
                    // Description
                    Text(factor.description)
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Backfill banner (if any data was backfilled)
                    if hasAnyBackfilledData {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            Text("Some data estimated from \(oldestSourceAgeInDays)d ago")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(8)
                        .padding(.top, 4)
                    }
                    
                    // Action plan
                    Text("Action plan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                        .padding(.top, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(factor.actionPlan, id: \.self) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(step)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Family members with trends and sub-metrics
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else if memberDetails.isEmpty {
                        Text("No data available for family members")
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .padding(.top, 8)
                    } else {
                        Text("Family \(factor.name.lowercased()) trends")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(memberDetails) { detail in
                                memberDetailCard(detail: detail)
                            }
                        }
                    }
                    
                    Spacer(minLength: 12)
                }
                .padding(20)
            }
            .navigationTitle(factor.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadMemberDetails()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadMemberDetails() async {
        isLoading = true
        
        // Get member user IDs
        let memberIds = factor.memberScores.compactMap { $0.userId }.filter { !$0.isEmpty }
        guard !memberIds.isEmpty else {
            await MainActor.run {
                memberDetails = []
                isLoading = false
            }
            return
        }
        
        do {
            // Fetch daily details for all members
            let dailyDetails = try await dataManager.fetchFamilyMemberDailyDetails(
                memberIds: memberIds,
                pillar: pillar,
                days: 14
            )
            
            // Process each member
            var processedDetails: [PillarMemberDetail] = []
            var globalOldestAge = 0
            
            for member in factor.memberScores {
                guard let userId = member.userId?.lowercased(),
                      let memberData = dailyDetails[userId] else {
                    continue
                }
                
                // Convert to DailyDataPoint format
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                let dataPoints = memberData.map { row in
                    DailyDataPoint(
                        date: row.date,
                        value: row.pillarScore.map { Double($0) },
                        subMetrics: row.subMetrics
                    )
                }
                
                // Run backfill
                let (filled, metadata) = DataBackfillEngine.backfillSeries(
                    dataPoints,
                    recencyLimitDays: 3,
                    targetWindowDays: 7
                )
                
                // Get last 7 days (target window)
                let last7Days = Array(filled.suffix(7))
                
                // Compute trend: compare last 3 days avg vs previous 4 days avg
                let trend = computeTrend(from: last7Days)
                
                // Get today's data (most recent)
                let todayData = last7Days.last
                
                // Build sub-metrics for display
                let subMetrics = buildSubMetrics(
                    from: todayData,
                    pillar: pillar
                )
                
                // Check if this member has backfilled data
                let memberHasBackfill = metadata.totalDaysBackfilled > 0 || subMetrics.contains { $0.isBackfilled }
                let memberOldestAge = max(metadata.oldestSourceAgeInDays, subMetrics.compactMap { $0.sourceAgeInDays }.max() ?? 0)
                
                globalOldestAge = max(globalOldestAge, memberOldestAge)
                
                let detail = PillarMemberDetail(
                    member: member,
                    todayScore: todayData?.value.map { Int($0) },
                    trendDirection: trend.direction,
                    trendPercentChange: trend.percentChange,
                    subMetrics: subMetrics,
                    hasBackfilledData: memberHasBackfill,
                    oldestSourceAgeInDays: memberOldestAge > 0 ? memberOldestAge : nil
                )
                
                processedDetails.append(detail)
            }
            
            await MainActor.run {
                memberDetails = processedDetails
                hasAnyBackfilledData = globalOldestAge > 0
                oldestSourceAgeInDays = globalOldestAge
                isLoading = false
            }
        } catch {
            print("❌ VitalityFactorDetailSheet: Failed to load member details: \(error.localizedDescription)")
            await MainActor.run {
                memberDetails = []
                isLoading = false
            }
        }
    }
    
    // MARK: - Trend Computation
    
    private func computeTrend(from last7Days: [BackfilledDataPoint]) -> (direction: TrendDirection, percentChange: Double?) {
        guard last7Days.count >= 7 else {
            return (.stable, nil)
        }
        
        // Last 3 days
        let recent = last7Days.suffix(3).compactMap { $0.value }
        // Previous 4 days
        let previous = Array(last7Days.prefix(4)).compactMap { $0.value }
        
        guard !recent.isEmpty && !previous.isEmpty else {
            return (.stable, nil)
        }
        
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let previousAvg = previous.reduce(0, +) / Double(previous.count)
        
        guard previousAvg > 0 else {
            return (.stable, nil)
        }
        
        let percentChange = ((recentAvg - previousAvg) / previousAvg) * 100.0
        
        if percentChange > 5 {
            return (.up, percentChange)
        } else if percentChange < -5 {
            return (.down, percentChange)
        } else {
            return (.stable, percentChange)
        }
    }
    
    // MARK: - Sub-Metrics Building
    
    private func buildSubMetrics(from data: BackfilledDataPoint?, pillar: VitalityPillar) -> [SubMetric] {
        guard let data = data else { return [] }
        
        var metrics: [SubMetric] = []
        
        switch pillar {
        case .sleep:
            if let sleepMinutes = data.subMetrics["sleep_minutes"] {
                let hours = sleepMinutes.value / 60.0
                metrics.append(SubMetric(
                    name: "Sleep Duration",
                    value: String(format: "%.1f hours", hours),
                    isBackfilled: sleepMinutes.isBackfilled,
                    sourceAgeInDays: sleepMinutes.ageInDays
                ))
            }
            if let deepSleep = data.subMetrics["deep_sleep_minutes"] {
                metrics.append(SubMetric(
                    name: "Deep Sleep",
                    value: "\(Int(deepSleep.value)) min",
                    isBackfilled: deepSleep.isBackfilled,
                    sourceAgeInDays: deepSleep.ageInDays
                ))
            }
            if let remSleep = data.subMetrics["rem_sleep_minutes"] {
                metrics.append(SubMetric(
                    name: "REM Sleep",
                    value: "\(Int(remSleep.value)) min",
                    isBackfilled: remSleep.isBackfilled,
                    sourceAgeInDays: remSleep.ageInDays
                ))
            }
            if let efficiency = data.subMetrics["sleep_efficiency_pct"] {
                metrics.append(SubMetric(
                    name: "Efficiency",
                    value: String(format: "%.0f%%", efficiency.value),
                    isBackfilled: efficiency.isBackfilled,
                    sourceAgeInDays: efficiency.ageInDays
                ))
            }
            
        case .movement:
            if let steps = data.subMetrics["steps"] {
                metrics.append(SubMetric(
                    name: "Steps",
                    value: String(format: "%d steps", Int(steps.value)),
                    isBackfilled: steps.isBackfilled,
                    sourceAgeInDays: steps.ageInDays
                ))
            }
            if let movementMinutes = data.subMetrics["movement_minutes"] {
                metrics.append(SubMetric(
                    name: "Active Minutes",
                    value: "\(Int(movementMinutes.value)) min",
                    isBackfilled: movementMinutes.isBackfilled,
                    sourceAgeInDays: movementMinutes.ageInDays
                ))
            }
            
        case .stress:
            if let hrv = data.subMetrics["hrv_ms"] {
                metrics.append(SubMetric(
                    name: "HRV",
                    value: String(format: "%.0f ms", hrv.value),
                    isBackfilled: hrv.isBackfilled,
                    sourceAgeInDays: hrv.ageInDays
                ))
            }
            if let restingHr = data.subMetrics["resting_hr"] {
                metrics.append(SubMetric(
                    name: "Resting HR",
                    value: String(format: "%.0f bpm", restingHr.value),
                    isBackfilled: restingHr.isBackfilled,
                    sourceAgeInDays: restingHr.ageInDays
                ))
            }
        }
        
        return metrics
    }
    
    // MARK: - UI Components
    
    private func memberDetailCard(detail: PillarMemberDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar, Name, Score, Trend
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.miyaBackground)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(detail.member.initials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(detail.member.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        if detail.hasBackfilledData {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                        }
                    }
                    
                    if let score = detail.todayScore {
                        Text("\(score)%")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    } else {
                        Text("No data")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                
                Spacer()
                
                // Trend badge
                trendBadge(direction: detail.trendDirection, percentChange: detail.trendPercentChange)
            }
            
            // Sub-metrics grid
            if !detail.subMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(detail.subMetrics.enumerated()), id: \.offset) { _, metric in
                        HStack(spacing: 8) {
                            if metric.isBackfilled {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.orange.opacity(0.7))
                                    .font(.system(size: 10))
                            }
                            Text(metric.name)
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            Spacer()
                            Text(metric.value)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.miyaTextPrimary)
                        }
                    }
                }
                .padding(.leading, 52) // Align with name
            }
            
            // Backfill notice (if applicable)
            if let age = detail.oldestSourceAgeInDays, age > 0 {
                Text("Data from \(age) day\(age == 1 ? "" : "s") ago")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.leading, 52)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.3))
        .cornerRadius(10)
    }
    
    private func trendBadge(direction: TrendDirection, percentChange: Double?) -> some View {
        let (icon, color, text) = {
            switch direction {
            case .up:
                return ("arrow.up", Color.green, percentChange.map { String(format: "+%.0f%%", $0) } ?? "+")
            case .down:
                return ("arrow.down", Color.red, percentChange.map { String(format: "%.0f%%", $0) } ?? "-")
            case .stable:
                return ("arrow.right", Color.gray, "→")
            }
        }()
        
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}
