import SwiftUI

// MARK: - FAMILY BADGES COMPONENTS
// Extracted from DashboardView.swift to reduce file size and improve maintainability
// Champions dashboard card lives in `Champions/`; this file retains `BadgeDetailSheet` for daily badge drill-in.

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
