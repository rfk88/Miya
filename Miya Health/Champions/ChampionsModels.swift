import SwiftUI

// MARK: - Member

struct ChampionMember: Identifiable {
    let id: String
    let name: String
    /// Profile image URL when available (app uses `ProfileAvatarView`, not `UIImage`).
    let avatarURL: String?
    let accentColor: Color
    let totalPoints: Int

    var tier: MemberTier { MemberTier.tier(for: totalPoints) }

    var initial: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first else { return "?" }
        return String(c).uppercased()
    }

    /// Two-letter initials for `ProfileAvatarView`.
    var initialsDisplay: String {
        let parts = name.split(separator: " ").map(String.init)
        let a = parts.first?.first.map { String($0) } ?? ""
        let b = parts.dropFirst().first?.first.map { String($0) } ?? ""
        let s = (a + b).uppercased()
        return s.isEmpty ? "?" : s
    }

    var pointsToNextTier: Int? {
        guard let next = tier.nextTier else { return nil }
        return next.pointThreshold - totalPoints
    }

    var tierProgress: Double {
        guard let next = tier.nextTier else { return 1.0 }
        let range = next.pointThreshold - tier.pointThreshold
        guard range > 0 else { return 1.0 }
        let earned = totalPoints - tier.pointThreshold
        return min(Double(earned) / Double(range), 1.0)
    }
}

// MARK: - Category

enum ChampionCategoryType: String, CaseIterable, Identifiable {
    case vitality
    case sleep
    case movement
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vitality: return "Vitality MVP"
        case .sleep: return "Sleep MVP"
        case .movement: return "Movement MVP"
        case .recovery: return "Best Recovery"
        }
    }

    var icon: String {
        switch self {
        case .vitality: return "crown.fill"
        case .sleep: return "moon.fill"
        case .movement: return "figure.run"
        case .recovery: return "heart.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .vitality: return Color(hex: "F59E0B")
        case .sleep: return Color(hex: "8B5CF6")
        case .movement: return Color(hex: "10B981")
        case .recovery: return Color(hex: "EF4444")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .vitality: return Color(hex: "FFFBEB")
        case .sleep: return Color(hex: "F5F3FF")
        case .movement: return Color(hex: "ECFDF5")
        case .recovery: return Color(hex: "FEF2F2")
        }
    }

    var unit: String {
        switch self {
        case .vitality: return "%"
        default: return ""
        }
    }
}

enum MemberStatus {
    case leading
    case close
    case trailing
}

struct CategoryMemberRow: Identifiable {
    let id: String
    let status: MemberStatus
    let displayValue: String
}

struct ChampionCategory: Identifiable {
    let id: ChampionCategoryType
    var rows: [CategoryMemberRow]

    var leader: CategoryMemberRow? { rows.first }
}

// MARK: - Season

struct SeasonInfo {
    let name: String
    let weekNumber: Int
    let totalWeeks: Int
    let daysRemaining: Int
}

// MARK: - Root

struct ChampionsData {
    let season: SeasonInfo
    let categories: [ChampionCategory]
    let members: [ChampionMember]
    let isLive: Bool

    func member(for id: String) -> ChampionMember? {
        members.first { $0.id.lowercased() == id.lowercased() }
    }

    var membersSortedByPoints: [ChampionMember] {
        members.sorted { $0.totalPoints > $1.totalPoints }
    }
}
