//
//  CompetitiveChallengeComponents.swift
//  Miya Health
//
//  Reusable building blocks shared by the composer, pending, active, and result
//  screens. All visuals are tuned for Miya's light dashboard palette; do not add
//  views here that assume a dark theme.
//

import Combine
import SwiftUI

// MARK: - Avatar circle

/// Initials avatar used wherever a participant is shown.
struct CompetitiveAvatarCircle: View {
    let initials: String
    let tint: Color
    var size: CGFloat = 44
    var isDimmed: Bool = false

    var body: some View {
        Circle()
            .fill(tint.opacity(isDimmed ? 0.35 : 1.0))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityHidden(true)
            )
            .accessibilityLabel(Text(initials))
    }
}

// MARK: - Animated score display

/// Smoothly count-up score with tabular digits. Use `.id(challengeId)` from the parent if
/// the score should re-animate when switching challenges; otherwise it animates once on appear.
struct CompetitiveScoreDisplay: View {
    let value: Double
    let focus: ChallengeFocus
    var color: Color = CompetitiveChallengeTheme.textPrimary
    var size: CGFloat = 42

    @State private var displayed: Double = 0

    var body: some View {
        Text(focus.formatScore(displayed))
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundColor(color)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear {
                // Spec: ~900ms easeOut count-up. Reset to 0 first to make the motion visible.
                displayed = 0
                withAnimation(.easeOut(duration: 0.9)) {
                    displayed = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.45)) {
                    displayed = newValue
                }
            }
    }
}

// MARK: - Card container

/// Light card surface with hairline border. Replaces the spec's dark `DarkCard`.
struct CompetitiveCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = CompetitiveChallengeTheme.radiusLg
    var background: Color = CompetitiveChallengeTheme.cardSurface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(CompetitiveChallengeTheme.cardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Member pill (composer)

/// Toggleable pill used in the composer's WHO grid.
struct CompetitiveMemberPill: View {
    let displayName: String
    let initials: String
    let avatarTint: Color
    let isSelected: Bool
    let isDisabled: Bool
    var disabledReason: String? = nil
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            onTap()
        }) {
            HStack(spacing: 10) {
                CompetitiveAvatarCircle(initials: initials, tint: avatarTint, size: 28, isDimmed: isDisabled)
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        isDisabled
                            ? CompetitiveChallengeTheme.textMuted
                            : (isSelected ? CompetitiveChallengeTheme.textPrimary : CompetitiveChallengeTheme.textSecondary)
                    )
                    .lineLimit(1)
                if isDisabled, let disabledReason {
                    Text(disabledReason)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CompetitiveChallengeTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CompetitiveChallengeTheme.neutralChip, in: Capsule())
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(CompetitiveChallengeTheme.youAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? CompetitiveChallengeTheme.youAccentSoft
                    : CompetitiveChallengeTheme.cardSurfaceMuted
            )
            .overlay(
                RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                    .strokeBorder(
                        isSelected ? CompetitiveChallengeTheme.youAccent : CompetitiveChallengeTheme.cardBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isDisabled ? 0.55 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Focus card (2×2 grid)

/// Tappable card representing a `ChallengeFocus`. Selected uses the focus accent;
/// unselected uses muted neutrals.
struct CompetitiveFocusCard: View {
    let focus: ChallengeFocus
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: focus.sfSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? focus.accent : CompetitiveChallengeTheme.textMuted)
                Text(focus.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? CompetitiveChallengeTheme.textPrimary : CompetitiveChallengeTheme.textSecondary)
                Text(focus.scoringRule)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? focus.accent : CompetitiveChallengeTheme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 110)
            .background(isSelected ? focus.accent.opacity(0.10) : CompetitiveChallengeTheme.cardSurfaceMuted)
            .overlay(
                RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous)
                    .strokeBorder(
                        isSelected ? focus.accent : CompetitiveChallengeTheme.cardBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: CompetitiveChallengeTheme.radiusMd, style: .continuous))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(focus.displayName). \(focus.scoringRule)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Avatar stack (VS banner / brawl)

/// Overlapping avatar stack with a "+N" overflow badge when participants > 3.
struct CompetitiveAvatarStack: View {
    let avatars: [(initials: String, tint: Color, dimmed: Bool)]
    var size: CGFloat = 48

    private var visibleCount: Int { min(avatars.count, 3) }
    private var overflowCount: Int { max(0, avatars.count - 3) }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { index, avatar in
                CompetitiveAvatarCircle(initials: avatar.initials, tint: avatar.tint, size: size, isDimmed: avatar.dimmed)
                    .overlay(
                        Circle().stroke(CompetitiveChallengeTheme.sheetBackground, lineWidth: 2)
                    )
                    .offset(x: CGFloat(index) * (size * 0.55))
                    .zIndex(Double(avatars.count - index))
            }
            if overflowCount > 0 {
                Circle()
                    .fill(CompetitiveChallengeTheme.neutralChip)
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(overflowCount)")
                            .font(.system(size: size * 0.30, weight: .bold))
                            .foregroundColor(CompetitiveChallengeTheme.textPrimary)
                    )
                    .overlay(
                        Circle().stroke(CompetitiveChallengeTheme.sheetBackground, lineWidth: 2)
                    )
                    .offset(x: CGFloat(3) * (size * 0.55))
                    .zIndex(0)
            }
        }
        .frame(
            width: size + CGFloat(max(0, min(avatars.count, overflowCount > 0 ? 4 : 3) - 1)) * (size * 0.55),
            height: size,
            alignment: .leading
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Lead pill

/// Capsule pill summarising who is ahead and by how much.
struct CompetitiveLeadPill: View {
    enum State: Hashable {
        case youAhead(margin: Double)
        case opponentAhead(name: String, margin: Double)
        case tied
        case unknown
    }

    let state: State
    let focus: ChallengeFocus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.8))
        .animation(.easeInOut(duration: 0.3), value: label)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        switch state {
        case .youAhead(let margin):
            return "You lead by \(focus.formatScore(margin)) \(focus.scoreUnit)"
        case .opponentAhead(let name, let margin):
            return "\(name) leads by \(focus.formatScore(margin)) \(focus.scoreUnit)"
        case .tied:
            return "Neck and neck"
        case .unknown:
            return "Waiting for data"
        }
    }

    private var iconName: String {
        switch state {
        case .youAhead: return "arrow.up.right"
        case .opponentAhead: return "arrow.down.right"
        case .tied: return "equal"
        case .unknown: return "hourglass"
        }
    }

    private var background: Color {
        switch state {
        case .youAhead:        return CompetitiveChallengeTheme.youAccentSoft
        case .opponentAhead:   return CompetitiveChallengeTheme.rivalAccentSoft
        case .tied, .unknown:  return CompetitiveChallengeTheme.neutralChip
        }
    }

    private var foreground: Color {
        switch state {
        case .youAhead:       return CompetitiveChallengeTheme.youAccent
        case .opponentAhead:  return CompetitiveChallengeTheme.rivalAccent
        case .tied, .unknown: return CompetitiveChallengeTheme.textSecondary
        }
    }

    private var border: Color {
        switch state {
        case .youAhead:        return CompetitiveChallengeTheme.youAccent.opacity(0.4)
        case .opponentAhead:   return CompetitiveChallengeTheme.rivalAccent.opacity(0.4)
        case .tied, .unknown:  return CompetitiveChallengeTheme.cardBorder
        }
    }
}

// MARK: - Animated waiting dots

/// Trailing dots animator for pending screens: "Waiting for Rami" → cycles 1..3 dots every 0.6s.
struct CompetitiveWaitingDots: View {
    @State private var count: Int = 1
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: count))
            .font(.system(size: 24, weight: .heavy))
            .foregroundColor(CompetitiveChallengeTheme.textSecondary)
            .frame(width: 32, alignment: .leading)
            .onReceive(timer) { _ in
                count = count >= 3 ? 1 : count + 1
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Week tracker dots (active screen)

struct CompetitiveWeekStrip: View {
    /// 7 values aligned Mon..Sun. `nil` = no data; for the current day, pass the rendered value.
    let values: [Double?]
    /// Index of today's column (Mon=0..Sun=6). Pass `nil` if the user is outside the window.
    let todayIndex: Int?
    let focus: ChallengeFocus

    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 6) {
                    dayDot(index: i)
                    Text(labels[i])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textColor(for: i))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayDot(index: Int) -> some View {
        let isToday = (index == todayIndex)
        let isPast  = (todayIndex.map { index < $0 } ?? false) || values[index] != nil
        let hasValue = values[index] != nil

        ZStack {
            Circle()
                .fill(fill(for: index, isToday: isToday, isPast: isPast, hasValue: hasValue))
                .overlay(
                    Circle().strokeBorder(stroke(for: index, isToday: isToday, isPast: isPast), lineWidth: 1)
                )
            if isToday {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            } else if hasValue {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(focus.accent)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func fill(for index: Int, isToday: Bool, isPast: Bool, hasValue: Bool) -> Color {
        if isToday { return focus.accent }
        if hasValue || isPast { return focus.accent.opacity(0.18) }
        return CompetitiveChallengeTheme.cardSurfaceMuted
    }

    private func stroke(for index: Int, isToday: Bool, isPast: Bool) -> Color {
        if isToday { return focus.accent }
        if isPast  { return focus.accent.opacity(0.35) }
        return CompetitiveChallengeTheme.cardBorder
    }

    private func textColor(for index: Int) -> Color {
        if index == todayIndex { return CompetitiveChallengeTheme.textPrimary }
        if values[index] != nil { return CompetitiveChallengeTheme.textPrimary }
        return CompetitiveChallengeTheme.textMuted
    }
}
