import Foundation

/// Maps `user_profiles` vitality pillar scores (0–100) to profile card copy. Pure logic — unit tested.
enum MemberProfilePillarPresentation {
    /// Builds card content from stored pillar score (same source as dashboard / family vitality).
    static func pillarData(fromStoredScore score: Int, displayName: String) -> ProfilePillarData {
        let status: PillarStatus
        switch score {
        case 80...100: status = .above
        case 60..<80: status = .stable
        default: status = .below
        }
        return ProfilePillarData(
            value: "\(score)",
            status: status,
            changeText: "Out of 100",
            context: "\(displayName) pillar · from your wearables"
        )
    }

    /// Prefer stored score when present (≥ 0); otherwise legacy raw-metric row.
    static func pillarData(stored: Int?, raw: ProfilePillarData?, displayName: String) -> ProfilePillarData? {
        if let s = stored, s >= 0 {
            return pillarData(fromStoredScore: s, displayName: displayName)
        }
        return raw
    }
}
