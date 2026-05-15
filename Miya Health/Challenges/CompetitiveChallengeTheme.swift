//
//  CompetitiveChallengeTheme.swift
//  Miya Health
//
//  Adapts the competitive-challenge UI tokens (from the design spec) to Miya's
//  existing light dashboard palette. No view should hard-code hex values; always
//  reference these properties so a future palette change is single-source.
//

import SwiftUI

/// Token surface for the Phase B competitive-challenge UI.
///
/// **Design rules** (do not break in views):
/// - Light surfaces only. No `Color.black` backgrounds, no `Color.white.opacity()` on near-black.
/// - "You" reads as Miya teal (primary). "Opponent" reads as Miya amber (secondary).
/// - Pillar focus uses the existing dashboard pillar accents. Steps gets its own teal-leaning accent.
/// - Radii and typography are theme-agnostic and ported as-is from the spec.
enum CompetitiveChallengeTheme {

    // MARK: Surfaces
    static let sheetBackground = Color.miyaDashboardBg
    static let cardSurface = Color.miyaCardWhite
    static let cardSurfaceMuted = Color.miyaSurfaceGrey
    static let cardBorder = Color.black.opacity(0.08)

    // MARK: Text
    static let textPrimary = Color.miyaDashboardTextPrimary
    static let textSecondary = Color.miyaDashboardTextSecond
    static let textMuted = Color.miyaTextTertiary

    // MARK: Semantic accents
    /// "You" / leader-positive / accept.
    static let youAccent = Color.miyaPrimary
    /// "You" soft tint background for chips and lead pills.
    static let youAccentSoft = Color.miyaPrimary.opacity(0.12)
    /// Rival / urgency / pending-clock / opponent ahead.
    static let rivalAccent = Color.miyaSecondary
    static let rivalAccentSoft = Color.miyaSecondary.opacity(0.14)

    /// Neutral chip background used for ties, idle states, future-day placeholders.
    static let neutralChip = Color.miyaTextTertiary.opacity(0.18)

    // MARK: Focus accents
    static let focusSleep = Color.miyaSleepAccent
    static let focusActivity = Color.miyaActivityAccent
    static let focusRecovery = Color.miyaRecoveryAccent
    /// Steps is the fourth lane and not in the dashboard pillar palette; use a clear distinct teal
    /// drawn from the existing hero teal family so it still feels Miya.
    static let focusSteps = Color.miyaHeroTealStart

    // MARK: Radii
    static let radiusSm: CGFloat = 10
    static let radiusMd: CGFloat = 14
    static let radiusLg: CGFloat = 18
    static let radiusXl: CGFloat = 22

    // MARK: Type scale (from spec, theme-agnostic)
    static let displayScoreFont = Font.system(size: 42, weight: .heavy, design: .rounded)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let subtextFont = Font.system(size: 12, weight: .regular)

    /// Section labels: 11pt semibold, tracking 0.8, uppercase.
    static func sectionLabelFont() -> Font { .system(size: 11, weight: .semibold) }
}

// MARK: - Convenience modifier for section labels

extension View {
    /// Applies the spec's section-label treatment using Miya tokens.
    func competitiveSectionLabel() -> some View {
        self.font(CompetitiveChallengeTheme.sectionLabelFont())
            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
            .kerning(0.8)
            .textCase(.uppercase)
    }
}
