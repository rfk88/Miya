import SwiftUI

// MARK: - DashboardView Share Text Extension
// Extracted from DashboardView.swift for better organization and compilation performance

extension DashboardView {
    // MARK: - Share text builder

    internal func prepareShareText() {
        let sleep = vitalityFactors.first(where: { $0.name == "Sleep" })?.percent
        let activity = vitalityFactors.first(where: { $0.name == "Activity" })?.percent
        let stress = vitalityFactors.first(where: { $0.name == "Recovery" })?.percent

        let familyScoreText: String = {
            if let score = familyVitalityScore { return "\(score)/100" }
            return "N/A"
        }()

        shareText = """
        Our Family Vitality Score this week: \(familyScoreText)

        Sleep: \(sleep.map(String.init) ?? "N/A")
        Activity: \(activity.map(String.init) ?? "N/A")
        Stress: \(stress.map(String.init) ?? "N/A")

        One family. One mission.
        Shared from Miya Health.
        """
    }
}
