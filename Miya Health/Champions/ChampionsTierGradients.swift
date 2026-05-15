import SwiftUI

enum MemberTier: String, CaseIterable {
    case vital = "Vital"
    case active = "Active"
    case resilient = "Resilient"
    case thriving = "Thriving"
    case longevity = "Longevity"
    case legacy = "Legacy"

    var gradientColors: [Color] {
        switch self {
        case .vital: return [Color(hex: "9CA3AF"), Color(hex: "6B7280")]
        case .active: return [Color(hex: "D97706"), Color(hex: "92400E")]
        case .resilient: return [Color(hex: "C0C0C0"), Color(hex: "9CA3AF")]
        case .thriving: return [Color(hex: "FBBF24"), Color(hex: "D97706")]
        case .longevity: return [Color(hex: "E5E4E2"), Color(hex: "C0C0C0")]
        case .legacy: return [Color(hex: "374151"), Color(hex: "111827")]
        }
    }

    var pointThreshold: Int {
        switch self {
        case .vital: return 0
        case .active: return 150
        case .resilient: return 450
        case .thriving: return 900
        case .longevity: return 1800
        case .legacy: return 4000
        }
    }

    var nextTier: MemberTier? {
        let all = MemberTier.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    static func tier(for points: Int) -> MemberTier {
        MemberTier.allCases.last(where: { points >= $0.pointThreshold }) ?? .vital
    }
}
