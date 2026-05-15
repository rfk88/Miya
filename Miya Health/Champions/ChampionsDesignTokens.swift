import SwiftUI

/// Design tokens for Champions card + sheet (spec §2). Uses `Color(hex:)`; asset catalog can mirror these later.
enum ChampionsTokens {
    // MARK: Primary
    static let teal = Color(hex: "00B4B4")
    static let tealSubtle = Color(hex: "00B4B4").opacity(0.1)
    static let tealRow = Color(hex: "00B4B4").opacity(0.05)

    // MARK: Amber
    static let amber = Color(hex: "F59E0B")
    static let amberText = Color(hex: "D97706")
    static let amberSubtle = Color(hex: "F59E0B").opacity(0.1)
    static let amberRow = Color(hex: "F59E0B").opacity(0.03)

    // MARK: Text
    static let textPrimary = Color(hex: "0F172A")
    static let textSecondary = Color(hex: "64748B")
    static let textMuted = Color(hex: "94A3B8")
    static let textHint = Color(hex: "CBD5E1")

    // MARK: Surfaces
    static let surfaceCard = Color.white
    static let surfaceApp = Color(hex: "F8FAFC")
    static let surfaceSheet = Color.white
    static let surfaceChip = Color(hex: "F1F5F9")

    // MARK: Borders
    static let borderLight = Color(hex: "F1F5F9")
    static let borderSheet = Color(hex: "F8FAFC")
    static let cardBorder = Color(hex: "00B4B4").opacity(0.1)

    // MARK: Live / overlay
    static let liveGreen = Color(hex: "22C55E")
    static let sheetOverlay = Color.black.opacity(0.45)

    // MARK: Category icon wells + accents
    static let vitalityBg = Color(hex: "FFFBEB")
    static let sleepBg = Color(hex: "F5F3FF")
    static let movementBg = Color(hex: "ECFDF5")
    static let recoveryBg = Color(hex: "FEF2F2")

    static let vitalityCol = Color(hex: "F59E0B")
    static let sleepCol = Color(hex: "8B5CF6")
    static let movementCol = Color(hex: "10B981")
    static let recoveryCol = Color(hex: "EF4444")

    // MARK: Trophy
    static let trophyBg = Color(hex: "FFFBEB")
    static let trophyCol = Color(hex: "F59E0B")

    static let sheetHandle = Color(hex: "E2E8F0")

    // MARK: Typography (SF Pro via system)
    static let cardTitle = Font.system(size: 16, weight: .bold)
    static let cardLiveLabel = Font.system(size: 11, weight: .medium)
    static let cardDaysLeft = Font.system(size: 12, weight: .regular)
    static let cardCatLabel = Font.system(size: 12, weight: .medium)
    static let cardLeaderName = Font.system(size: 13, weight: .semibold)
    static let cardScore = Font.system(size: 13, weight: .bold)
    static let cardTapLabel = Font.system(size: 12, weight: .semibold)

    static let sheetTitle = Font.system(size: 18, weight: .bold)
    static let sheetLive = Font.system(size: 11, weight: .medium)
    static let sheetSubtitle = Font.system(size: 12, weight: .regular)

    static let sectionName = Font.system(size: 15, weight: .semibold)
    static let sectionLeader = Font.system(size: 13, weight: .medium)

    static let rowRank = Font.system(size: 11, weight: .bold)
    static let rowName = Font.system(size: 14, weight: .semibold)
    static let rowTier = Font.system(size: 11, weight: .regular)
    static let rowScore = Font.system(size: 16, weight: .bold)
    static let pillText = Font.system(size: 11, weight: .semibold)

    static let seasonTitle = Font.system(size: 15, weight: .semibold)
    static let seasonSub = Font.system(size: 11, weight: .regular)
    static let seasonName = Font.system(size: 14, weight: .semibold)
    static let seasonTier = Font.system(size: 11, weight: .regular)
    static let seasonRemain = Font.system(size: 11, weight: .regular)
    static let seasonPtsNum = Font.system(size: 20, weight: .heavy)
    static let seasonPtsUnit = Font.system(size: 10, weight: .medium)

    static let seasonRank = Font.system(size: 12, weight: .bold)

    // MARK: Spacing / layout
    static let cardPaddingH: CGFloat = 16
    static let cardPaddingTop: CGFloat = 16
    static let cardPaddingBottom: CGFloat = 14
    static let cardRadius: CGFloat = 20
    static let cardBorderWidth: CGFloat = 1
    static let cardCategoryGap: CGFloat = 9
    static let cardRowIconSize: CGFloat = 30
    static let cardRowIconRadius: CGFloat = 9
    static let cardRowIconInner: CGFloat = 15
    static let cardCatLabelWidth: CGFloat = 92
    static let cardAvatarSize: CGFloat = 22
    static let cardFooterAvatarSize: CGFloat = 28
    static let cardFooterAvatarOverlap: CGFloat = -8

    static let sheetHandleWidth: CGFloat = 36
    static let sheetHandleHeight: CGFloat = 4
    static let sheetHandleRadius: CGFloat = 2
    static let sheetHandlePadT: CGFloat = 10
    static let sheetHandlePadB: CGFloat = 2
    static let sheetHeaderPadH: CGFloat = 20
    static let sheetHeaderPadT: CGFloat = 10
    static let sheetHeaderPadB: CGFloat = 12
    static let sheetTopRadius: CGFloat = 28
    static let sheetMaxHeightPct: CGFloat = 0.88
    static let sheetCloseBtnSize: CGFloat = 32

    static let sectionPadH: CGFloat = 20
    static let sectionPadV: CGFloat = 13
    static let sectionIconSize: CGFloat = 38
    static let sectionIconRadius: CGFloat = 12
    static let sectionIconInner: CGFloat = 18
    static let sectionLeaderAvatar: CGFloat = 26

    static let rowPadH: CGFloat = 10
    static let rowPadV: CGFloat = 9
    static let rowRadius: CGFloat = 12
    static let rowMarginBottom: CGFloat = 4
    static let rowLeftBorder: CGFloat = 3
    static let rowRankWidth: CGFloat = 18
    static let rowAvatarSize: CGFloat = 34
    static let rowScoreMinWidth: CGFloat = 36
    static let rowScoreMarginR: CGFloat = 8
    static let expandedPadH: CGFloat = 20
    static let expandedPadBottom: CGFloat = 14

    static let seasonRowMarginB: CGFloat = 16
    static let seasonAvatarSize: CGFloat = 36
    static let seasonProgressH: CGFloat = 4
    static let seasonProgressPadL: CGFloat = 28
    static let seasonBottomPad: CGFloat = 40

    static let avatarBorderWidth: CGFloat = 2

    /// Fallback initials backgrounds when no photo (distinct, spec-adjacent).
    static let memberAccentPalette: [Color] = [
        Color(hex: "00B4B4"),
        Color(hex: "8B5CF6"),
        Color(hex: "10B981"),
        Color(hex: "F59E0B"),
        Color(hex: "EF4444"),
        Color(hex: "64748B")
    ]
}
