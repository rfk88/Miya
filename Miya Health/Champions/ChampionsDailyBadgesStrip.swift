import SwiftUI

/// Compact “Today” daily champions below the main Champions card; preserves `BadgeDetailSheet` drill-in.
struct ChampionsDailyBadgesStrip: View {
    let daily: [BadgeEngine.Winner]
    let onBadgeTapped: (BadgeEngine.Winner) -> Void

    @ViewBuilder
    var body: some View {
        if daily.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(ChampionsTokens.sectionName)
                    .foregroundColor(ChampionsTokens.textPrimary)
                    .kerning(-0.15)

                VStack(spacing: 8) {
                    ForEach(daily) { w in
                        Button {
                            onBadgeTapped(w)
                        } label: {
                            ChampionsDailyBadgeRow(winner: w)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(ChampionsTokens.cardPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChampionsTokens.surfaceCard)
            .cornerRadius(ChampionsTokens.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: ChampionsTokens.cardRadius)
                    .strokeBorder(ChampionsTokens.borderLight, lineWidth: 1)
            )
        }
    }
}

private struct ChampionsDailyBadgeRow: View {
    let winner: BadgeEngine.Winner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: winner.badgeType))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconTint(for: winner.badgeType))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: winner.badgeType))
                    .font(ChampionsTokens.cardCatLabel)
                    .foregroundColor(ChampionsTokens.textPrimary)
                Text(winner.winnerName)
                    .font(ChampionsTokens.sectionLeader)
                    .foregroundColor(ChampionsTokens.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ChampionsTokens.textHint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ChampionsTokens.surfaceChip.opacity(0.5))
        .cornerRadius(12)
    }

    private func title(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep": return "Most Sleep"
        case "daily_most_movement": return "Most Movement"
        case "daily_most_stressfree": return "Best Recovery"
        default: return badgeType.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func iconName(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep": return "moon.fill"
        case "daily_most_movement": return "figure.run"
        case "daily_most_stressfree": return "heart.fill"
        default: return "rosette"
        }
    }

    private func iconTint(for badgeType: String) -> Color {
        switch badgeType {
        case "daily_most_sleep": return ChampionsTokens.sleepCol
        case "daily_most_movement": return ChampionsTokens.movementCol
        case "daily_most_stressfree": return ChampionsTokens.recoveryCol
        default: return ChampionsTokens.teal
        }
    }
}
