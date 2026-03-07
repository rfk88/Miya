import SwiftUI

// MARK: - FAMILY BADGES COMPONENTS
// Extracted from DashboardView.swift to reduce file size and improve maintainability

// MARK: - FAMILY BADGES CARD (Daily + Weekly)

struct FamilyBadgesCard: View {
    let daily: [BadgeEngine.Winner]
    let weekly: [BadgeEngine.Winner]
    let weekStart: String?
    let weekEnd: String?
    var isLoading: Bool = false
    let onBadgeTapped: (BadgeEngine.Winner) -> Void
    
    @State private var isWeeklyExpanded: Bool = false
    
    private func title(for badgeType: String) -> String {
        switch badgeType {
        // Daily
        case "daily_most_sleep": return "Most Sleep"
        case "daily_most_movement": return "Most Movement"
        case "daily_most_stressfree": return "Best Recovery"
        // Weekly
        case "weekly_vitality_mvp": return "Vitality MVP"
        case "weekly_sleep_mvp": return "Sleep Champion"
        case "weekly_movement_mvp": return "Move Champion"
        case "weekly_stressfree_mvp": return "Stress-free MVP"
        case "weekly_family_anchor": return "Family anchor"
        case "weekly_consistency_mvp": return "Consistency MVP"
        case "weekly_balanced_week": return "Balanced week"
        case "weekly_biggest_comeback_day": return "Biggest comeback"
        case "weekly_sleep_streak_leader": return "Sleep streak"
        case "weekly_movement_streak_leader": return "Movement streak"
        case "weekly_stress_streak_leader": return "Stress streak"
        case "weekly_data_champion": return "Data champion"
        default: return badgeType.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    private func iconName(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep", "weekly_sleep_mvp", "weekly_sleep_streak_leader":
            return "moon.fill"
        case "daily_most_movement", "weekly_movement_mvp", "weekly_movement_streak_leader":
            return "figure.walk"
        case "daily_most_stressfree", "weekly_stressfree_mvp", "weekly_stress_streak_leader":
            return "heart.fill"
        case "weekly_consistency_mvp":
            return "metronome"
        case "weekly_family_anchor":
            return "shield.fill"
        case "weekly_balanced_week":
            return "circle.grid.cross.fill"
        case "weekly_biggest_comeback_day":
            return "arrow.up.right"
        case "weekly_data_champion":
            return "chart.bar.fill"
        case "weekly_vitality_mvp":
            return "crown.fill"
        default:
            return "rosette"
        }
    }
    
    private func weeklySorted(_ winners: [BadgeEngine.Winner]) -> [BadgeEngine.Winner] {
        // Stable order with Vitality MVP featured first
        let order = BadgeEngine.WeeklyBadgeType.allCases.map(\.rawValue)
        return winners.sorted { a, b in
            let ia = order.firstIndex(of: a.badgeType) ?? 999
            let ib = order.firstIndex(of: b.badgeType) ?? 999
            return ia < ib
        }
    }
    
    private func formatDelta(from meta: [String: Any]) -> String? {
        // Prefer percentage increase
        if let percentIncrease = meta["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            if rounded == 0 { return nil }
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
        // Fallback to delta (for backwards compatibility)
        if let d = meta["delta"] as? Double {
            let rounded = Int(d.rounded())
            if rounded == 0 { return nil }
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
        if let i = meta["delta"] as? Int {
            if i == 0 { return nil }
            return i > 0 ? "+\(i)" : "\(i)"
        }
        return nil
    }

    var body: some View {
        let weeklyOrdered = weeklySorted(weekly)
        let featured = weeklyOrdered.first(where: { $0.badgeType == "weekly_vitality_mvp" }) ?? weeklyOrdered.first
        let rest = weeklyOrdered.filter { $0.id != featured?.id }
        
        VStack(alignment: .leading, spacing: 16) {
            // Header (exact match to screenshot)
            HStack(spacing: 6) {
                Text("Champions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                if let weekStart, let weekEnd, !weekly.isEmpty {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    Text("\(weekStart) – \(weekEnd) UTC")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                Spacer()
            }
            
            // Empty state — only shown once the first computation has finished (isLoading=false),
            // so the card doesn't flash "No champions yet" while data is still being fetched.
            if daily.isEmpty && weekly.isEmpty && !isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No champions yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    
                    Text("Add daily vitality scores to start awarding Today + Weekly champions.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            
            // Featured Vitality MVP card (exact match to screenshot)
            if let featured {
                FeaturedVitalityCard(
                    winnerName: featured.winnerName,
                    deltaText: formatDelta(from: featured.metadata),
                    subtitle: formatVitalitySubtitle(from: featured.metadata)
                )
                .onTapGesture {
                    onBadgeTapped(featured)
                }
            }
            
            // Today section (exact match to screenshot)
            if !daily.isEmpty {
                Text("Today")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    .padding(.top, 4)
                
                VStack(spacing: 8) {
                    ForEach(daily) { w in
                        ChampionRow(
                            title: title(for: w.badgeType),
                            winnerName: w.winnerName,
                            iconName: iconName(for: w.badgeType),
                            valueText: formatDailyValue(for: w.badgeType, metadata: w.metadata),
                            contextText: "(improved from yesterday)"
                        )
                        .onTapGesture {
                            onBadgeTapped(w)
                        }
                    }
                }
                .padding(.top, 8)
            }
            
            // This week section (exact match to screenshot)
            if !weekly.isEmpty {
                HStack {
                    Text("This week")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
                .padding(.top, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isWeeklyExpanded.toggle()
                    }
                }
                
                if isWeeklyExpanded {
                    VStack(spacing: 8) {
                        ForEach(rest) { w in
                            ChampionRow(
                                title: title(for: w.badgeType),
                                winnerName: w.winnerName,
                                iconName: iconName(for: w.badgeType),
                                valueText: formatWeeklyValue(for: w.badgeType, metadata: w.metadata),
                                contextText: formatContextText(for: w.badgeType)
                            )
                            .onTapGesture {
                                onBadgeTapped(w)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 8) {
                        ForEach(rest.prefix(2)) { w in
                            ChampionRow(
                                title: title(for: w.badgeType),
                                winnerName: w.winnerName,
                                iconName: iconName(for: w.badgeType),
                                valueText: formatWeeklyValue(for: w.badgeType, metadata: w.metadata),
                                contextText: formatContextText(for: w.badgeType)
                            )
                            .onTapGesture {
                                onBadgeTapped(w)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
    
    // Helper functions for formatting values
    private func formatDailyValue(for badgeType: String, metadata: [String: Any]) -> String {
        // Format as percentage increase from personal baseline with "score" suffix
        if let percentIncrease = metadata["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)% score"
        }
        // Fallback for old format (shouldn't happen after migration)
        if let value = metadata["value"] as? Int {
            return "+\(value)% score"
        }
        return ""
    }
    
    private func formatWeeklyValue(for badgeType: String, metadata: [String: Any]) -> String {
        // Format based on badge type
        switch badgeType {
        case "weekly_family_anchor":
            // Show average score
            if let thisAvg = metadata["thisAvg"] as? Double {
                let rounded = Int(thisAvg.rounded())
                return "\(rounded)/100 avg"
            }
            return ""
        case "weekly_consistency_mvp":
            // Show standard deviation
            if let stddev = metadata["stddev"] as? Double {
                let rounded = Int(stddev.rounded())
                return "±\(rounded) pts"
            }
            return ""
        case "weekly_balanced_week":
            // Show balance score
            if let balance = metadata["balance"] as? Double {
                let rounded = Int(balance.rounded())
                return "\(rounded)/100"
            }
            return ""
        default:
            // Format as percentage increase from previous week
            if let percentIncrease = metadata["percentIncrease"] as? Double {
                let rounded = Int(percentIncrease.rounded())
                return "+\(rounded)% score"
            }
            // Fallback for old format (delta-based)
            if let delta = metadata["delta"] as? Double, let prevAvg = metadata["prevAvg"] as? Double, prevAvg > 0 {
                let percentIncrease = (delta / prevAvg) * 100.0
                let rounded = Int(percentIncrease.rounded())
                return "+\(rounded)% score"
            }
            // Last resort fallback
            if let delta = metadata["delta"] as? Double {
                let deltaInt = Int(delta.rounded())
                return "\(deltaInt > 0 ? "+" : "")\(deltaInt) pts"
            }
            return ""
        }
    }
    
    private func formatContextText(for badgeType: String) -> String {
        switch badgeType {
        case "weekly_vitality_mvp", "weekly_sleep_mvp", "weekly_movement_mvp", "weekly_stressfree_mvp":
            return "(biggest meaningful improvement vs last week)"
        case "weekly_family_anchor":
            return "(highest sustained average this week)"
        case "weekly_consistency_mvp":
            return "(most stable this week)"
        case "weekly_balanced_week":
            return "(best cross-pillar balance this week)"
        case "weekly_biggest_comeback_day":
            return "(largest smoothed day-to-day rebound)"
        case "weekly_sleep_streak_leader", "weekly_movement_streak_leader", "weekly_stress_streak_leader":
            return "(longest strong-score streak)"
        case "weekly_data_champion":
            return "(most complete tracked days)"
        default:
            return ""
        }
    }
    
    private func formatVitalitySubtitle(from metadata: [String: Any]) -> String {
        // Format as percentage increase
        if let percentIncrease = metadata["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)% vitality this week"
        }
        // Fallback for old format
        if let delta = metadata["delta"] as? Double, let prevAvg = metadata["prevAvg"] as? Double, prevAvg > 0 {
            let percentIncrease = (delta / prevAvg) * 100.0
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)% vitality this week"
        }
        if let delta = metadata["delta"] as? Double {
            let deltaInt = Int(delta.rounded())
            return "+\(deltaInt) vitality points this week"
        }
        return ""
    }
}

// MARK: - Featured Vitality MVP Card (exact match to screenshot)
private struct FeaturedVitalityCard: View {
    let winnerName: String
    let deltaText: String?
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Trophy icon
            Image(systemName: "crown.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Vitality MVP")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                // Name pill
                Text(winnerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.top, 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // "This week" pill
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                // Delta value with arrow
                if let deltaText, !deltaText.isEmpty {
                    HStack(spacing: 4) {
                        Text(deltaText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DashboardDesign.primaryTextColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
        )
    }
}

// MARK: - Champion Row (exact match to screenshot - Today and This week rows)
private struct ChampionRow: View {
    let title: String
    let winnerName: String
    let iconName: String
    let valueText: String
    let contextText: String?
    
    init(title: String, winnerName: String, iconName: String, valueText: String, contextText: String? = nil) {
        self.title = title
        self.winnerName = winnerName
        self.iconName = iconName
        self.valueText = valueText
        self.contextText = contextText
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon (colored, matching dashboard)
            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundColor(iconColor(for: iconName))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                Text(winnerName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                
                if let contextText, !contextText.isEmpty {
                    Text(contextText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Value with arrow
            HStack(spacing: 4) {
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 4,
            x: 0,
            y: 1
        )
    }
    
    private func iconColor(for iconName: String) -> Color {
        switch iconName {
        case "moon.fill": return Color.purple
        case "figure.walk": return Color.green
        case "heart.fill": return Color.orange
        case "crown.fill": return Color.blue
        case "shield.fill": return Color.blue
        case "metronome": return Color.blue
        case "circle.grid.cross.fill": return Color.blue
        default: return Color.blue
        }
    }
}

// MARK: - BADGE DETAIL SHEET

struct BadgeDetailSheet: View {
    let winner: BadgeEngine.Winner
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with icon and title
                    HStack(spacing: 16) {
                        Image(systemName: iconName(for: winner.badgeType))
                            .font(.system(size: 40))
                            .foregroundColor(iconColor(for: winner.badgeType))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: winner.badgeType))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(DashboardDesign.primaryTextColor)
                            
                            Text(winner.winnerName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DashboardDesign.secondaryTextColor)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    // Narrative insight (no section title)
                    Text(narrativeInsight(for: winner))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Motivational message
                    Text(motivationalMessage(for: winner.badgeType))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle("Badge Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func title(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep": return "Most Sleep"
        case "daily_most_movement": return "Most Movement"
        case "daily_most_stressfree": return "Best Recovery"
        case "weekly_vitality_mvp": return "Vitality MVP"
        case "weekly_sleep_mvp": return "Sleep Champion"
        case "weekly_movement_mvp": return "Move Champion"
        case "weekly_stressfree_mvp": return "Stress-free MVP"
        case "weekly_family_anchor": return "Family Anchor"
        case "weekly_consistency_mvp": return "Consistency MVP"
        case "weekly_balanced_week": return "Balanced Week"
        case "weekly_biggest_comeback_day": return "Biggest Comeback"
        case "weekly_sleep_streak_leader": return "Sleep Streak"
        case "weekly_movement_streak_leader": return "Movement Streak"
        case "weekly_stress_streak_leader": return "Stress Streak"
        case "weekly_data_champion": return "Data Champion"
        default: return badgeType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func iconName(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep", "weekly_sleep_mvp", "weekly_sleep_streak_leader":
            return "moon.fill"
        case "daily_most_movement", "weekly_movement_mvp", "weekly_movement_streak_leader":
            return "figure.walk"
        case "daily_most_stressfree", "weekly_stressfree_mvp", "weekly_stress_streak_leader":
            return "heart.fill"
        case "weekly_consistency_mvp":
            return "metronome"
        case "weekly_family_anchor":
            return "shield.fill"
        case "weekly_balanced_week":
            return "circle.grid.cross.fill"
        case "weekly_biggest_comeback_day":
            return "arrow.up.right"
        case "weekly_data_champion":
            return "chart.bar.fill"
        case "weekly_vitality_mvp":
            return "crown.fill"
        default:
            return "rosette"
        }
    }
    
    private func iconColor(for badgeType: String) -> Color {
        switch badgeType {
        case "daily_most_sleep", "weekly_sleep_mvp", "weekly_sleep_streak_leader":
            return Color.purple
        case "daily_most_movement", "weekly_movement_mvp", "weekly_movement_streak_leader":
            return Color.green
        case "daily_most_stressfree", "weekly_stressfree_mvp", "weekly_stress_streak_leader":
            return Color.orange
        default:
            return Color.blue
        }
    }
    
    private func narrativeInsight(for winner: BadgeEngine.Winner) -> String {
        let meta = winner.metadata
        
        switch winner.badgeType {
        // Daily badges - show % improvement from yesterday
        case "daily_most_sleep":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let baselineDays = meta["historyDays"] as? Int ?? 0
                let today = meta["todayValue"] as? Int ?? 0
                let baseline = Int((meta["baselineAverage"] as? Double ?? 0).rounded())
                return "Your sleep score is +\(Int(percentIncrease.rounded()))% above your recent \(baselineDays)-day baseline (\(today) vs \(baseline)). This was the strongest meaningful sleep lift today."
            }
            return "Your sleep score had the strongest meaningful lift today versus your recent baseline."
            
        case "daily_most_movement":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let baselineDays = meta["historyDays"] as? Int ?? 0
                let today = meta["todayValue"] as? Int ?? 0
                let baseline = Int((meta["baselineAverage"] as? Double ?? 0).rounded())
                return "Your activity score is +\(Int(percentIncrease.rounded()))% above your recent \(baselineDays)-day baseline (\(today) vs \(baseline)). This was the strongest meaningful activity lift today."
            }
            return "Your activity score had the strongest meaningful lift today versus your recent baseline."
            
        case "daily_most_stressfree":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let baselineDays = meta["historyDays"] as? Int ?? 0
                let today = meta["todayValue"] as? Int ?? 0
                let baseline = Int((meta["baselineAverage"] as? Double ?? 0).rounded())
                return "Your recovery score is +\(Int(percentIncrease.rounded()))% above your recent \(baselineDays)-day baseline (\(today) vs \(baseline)). This was the strongest meaningful recovery lift today."
            }
            return "Your recovery score had the strongest meaningful lift today versus your recent baseline."
        
        // Weekly improvement badges - show % improvement from last week
        case "weekly_vitality_mvp":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let thisWeek = Int((meta["thisAvg"] as? Double ?? 0).rounded())
                let prevWeek = Int((meta["prevAvg"] as? Double ?? 0).rounded())
                let thisDays = meta["thisWeekDays"] as? Int ?? 0
                let prevDays = meta["prevWeekDays"] as? Int ?? 0
                return "Your overall vitality average is +\(Int(percentIncrease.rounded()))% versus last week (\(thisWeek) vs \(prevWeek)), with \(thisDays) tracked days this week and \(prevDays) last week."
            }
            return "You had the strongest meaningful week-over-week vitality improvement."
            
        case "weekly_sleep_mvp":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let thisWeek = Int((meta["thisAvg"] as? Double ?? 0).rounded())
                let prevWeek = Int((meta["prevAvg"] as? Double ?? 0).rounded())
                return "Your sleep average improved +\(Int(percentIncrease.rounded()))% week-over-week (\(thisWeek) vs \(prevWeek)), the strongest meaningful lift in your family."
            }
            return "You had the strongest meaningful sleep improvement versus last week."
            
        case "weekly_movement_mvp":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let thisWeek = Int((meta["thisAvg"] as? Double ?? 0).rounded())
                let prevWeek = Int((meta["prevAvg"] as? Double ?? 0).rounded())
                return "Your activity average improved +\(Int(percentIncrease.rounded()))% week-over-week (\(thisWeek) vs \(prevWeek)), the strongest meaningful lift in your family."
            }
            return "You had the strongest meaningful activity improvement versus last week."
            
        case "weekly_stressfree_mvp":
            if let percentIncrease = meta["percentIncrease"] as? Double {
                let thisWeek = Int((meta["thisAvg"] as? Double ?? 0).rounded())
                let prevWeek = Int((meta["prevAvg"] as? Double ?? 0).rounded())
                return "Your recovery average improved +\(Int(percentIncrease.rounded()))% week-over-week (\(thisWeek) vs \(prevWeek)), the strongest meaningful lift in your family."
            }
            return "You had the strongest meaningful recovery improvement versus last week."
        
        // Family Anchor - highest average
        case "weekly_family_anchor":
            let thisWeek = Int((meta["thisAvg"] as? Double ?? 0).rounded())
            return "You had the highest sustained vitality average this week (\(thisWeek)/100), setting the benchmark for the family."
        
        // Consistency MVP - show stability
        case "weekly_consistency_mvp":
            if let stddev = meta["stddev"] as? Double {
                return "Your scores were the most stable this week, with only ±\(Int(stddev.rounded())) points of variation across your tracked days."
            }
            return "Your vitality scores were the most stable this week with minimal ups and downs!"
        
        // Balanced Week - all pillars strong
        case "weekly_balanced_week":
            let sleep = Int((meta["sleepAvg"] as? Double ?? 0).rounded())
            let movement = Int((meta["movementAvg"] as? Double ?? 0).rounded())
            let stress = Int((meta["stressAvg"] as? Double ?? 0).rounded())
            return "You had the strongest all-round week: Sleep \(sleep), Activity \(movement), Recovery \(stress). Your lowest pillar score was the highest balanced floor in the family."
        
        // Biggest Comeback - single day improvement
        case "weekly_biggest_comeback_day":
            if let maxDelta = meta["maxDelta"] as? Int {
                return "You posted the biggest smoothed day-to-day rebound this week at +\(maxDelta) points, indicating a real comeback rather than one-day noise."
            }
            return "You had the biggest smoothed day-to-day improvement this week."
        
        // Streak badges - days above threshold
        case "weekly_sleep_streak_leader":
            if let streakDays = meta["streakDays"] as? Int {
                return "You held the longest sleep streak this week: \(streakDays) consecutive day(s) at or above the strong-score threshold."
            }
            return "You had the longest streak of days with strong sleep scores!"
            
        case "weekly_movement_streak_leader":
            if let streakDays = meta["streakDays"] as? Int {
                return "You held the longest activity streak this week: \(streakDays) consecutive day(s) at or above the strong-score threshold."
            }
            return "You had the longest streak of days with strong activity scores!"
            
        case "weekly_stress_streak_leader":
            if let streakDays = meta["streakDays"] as? Int {
                return "You held the longest recovery streak this week: \(streakDays) consecutive day(s) at or above the strong-score threshold."
            }
            return "You had the longest streak of days with strong recovery scores!"
        
        // Data Champion - most complete days
        case "weekly_data_champion":
            if let days = meta["daysWith2PlusPillars"] as? Int {
                return "You had the most complete tracking this week, with \(days) day(s) that included at least two pillars."
            }
            return "You had the most days with complete health data this week!"
        
        default:
            return "You earned this badge for outstanding performance!"
        }
    }
    
    private func motivationalMessage(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep", "weekly_sleep_mvp", "weekly_sleep_streak_leader":
            return "Keep prioritizing rest! Great job!"
        case "daily_most_movement", "weekly_movement_mvp", "weekly_movement_streak_leader":
            return "Keep moving! You're doing amazing!"
        case "daily_most_stressfree", "weekly_stressfree_mvp", "weekly_stress_streak_leader":
            return "Your recovery is on point! Keep it up!"
        case "weekly_vitality_mvp":
            return "You're setting a great example for the family!"
        case "weekly_family_anchor":
            return "You're the steady rock keeping the family healthy. Keep it up!"
        case "weekly_consistency_mvp":
            return "Consistency is key to long-term health. Great job!"
        case "weekly_balanced_week":
            return "All three pillars strong! This is the ideal."
        case "weekly_biggest_comeback_day":
            return "What a comeback! Keep that momentum going!"
        case "weekly_data_champion":
            return "Thanks for keeping your data complete! It helps everyone."
        default:
            return "Keep up the excellent work!"
        }
    }
}
