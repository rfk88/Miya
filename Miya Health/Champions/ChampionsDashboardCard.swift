import SwiftUI
import UIKit

struct ChampionsDashboardCard: View {
    let data: ChampionsData?
    var isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            Group {
                if isLoading {
                    loadingBody
                } else if let data {
                    cardBody(data: data)
                } else {
                    EmptyView()
                }
            }
        }
        .buttonStyle(ChampionsPressScaleStyle())
        .disabled(isLoading || data == nil)
    }

    @ViewBuilder
    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: ChampionsTokens.cardCategoryGap) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ChampionsTokens.surfaceChip)
                    .frame(width: 120, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(ChampionsTokens.surfaceChip)
                    .frame(width: 80, height: 14)
            }
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: ChampionsTokens.cardRowIconRadius)
                        .fill(ChampionsTokens.surfaceChip)
                        .frame(width: ChampionsTokens.cardRowIconSize, height: ChampionsTokens.cardRowIconSize)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ChampionsTokens.surfaceChip)
                        .frame(width: ChampionsTokens.cardCatLabelWidth, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ChampionsTokens.surfaceChip)
                        .frame(width: 72, height: 14)
                }
            }
        }
        .padding(.horizontal, ChampionsTokens.cardPaddingH)
        .padding(.top, ChampionsTokens.cardPaddingTop)
        .padding(.bottom, ChampionsTokens.cardPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChampionsTokens.surfaceCard)
        .cornerRadius(ChampionsTokens.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: ChampionsTokens.cardRadius)
                .strokeBorder(ChampionsTokens.cardBorder, lineWidth: ChampionsTokens.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 10)
        .modifier(ChampionsShimmerModifier())
    }

    @ViewBuilder
    private func cardBody(data: ChampionsData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow(data: data)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: ChampionsTokens.cardCategoryGap) {
                ForEach(ChampionCategoryType.allCases, id: \.self) { cat in
                    if let category = data.categories.first(where: { $0.id == cat }),
                       let leader = category.leader,
                       let member = data.member(for: leader.id) {
                        categoryRow(category: cat, member: member, leader: leader)
                    }
                }
            }

            Rectangle()
                .fill(ChampionsTokens.borderLight)
                .frame(height: 1)
                .padding(.top, 13)
                .padding(.bottom, 11)

            footerRow(data: data)
        }
        .padding(.horizontal, ChampionsTokens.cardPaddingH)
        .padding(.top, ChampionsTokens.cardPaddingTop)
        .padding(.bottom, ChampionsTokens.cardPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChampionsTokens.surfaceCard)
        .cornerRadius(ChampionsTokens.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: ChampionsTokens.cardRadius)
                .strokeBorder(ChampionsTokens.cardBorder, lineWidth: ChampionsTokens.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 10)
        .modifier(ChampionsShimmerModifier())
    }

    private func headerRow(data: ChampionsData) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text("CHAMPIONS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.miyaHeroAccentTeal)
                if data.isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ChampionsTokens.liveGreen)
                            .frame(width: 6, height: 6)
                            .modifier(ChampionsLivePulseModifier())
                        Text("Live")
                            .font(ChampionsTokens.cardLiveLabel)
                            .foregroundColor(.miyaDashboardTextSecond)
                    }
                }
            }
            Spacer()
            HStack(spacing: 2) {
                Text("\(data.season.daysRemaining) days left")
                    .font(ChampionsTokens.cardDaysLeft)
                    .foregroundColor(Color.miyaDashboardTextSecond.opacity(0.7))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.miyaDashboardTextSecond.opacity(0.7))
            }
        }
    }

    private func categoryRow(category: ChampionCategoryType, member: ChampionMember, leader: CategoryMemberRow) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(category.backgroundColor)
                    .frame(width: ChampionsTokens.cardRowIconSize, height: ChampionsTokens.cardRowIconSize)
                Image(systemName: category.icon)
                    .font(.system(size: ChampionsTokens.cardRowIconInner, weight: .semibold))
                    .foregroundColor(category.accentColor)
            }
            Text(category.displayName)
                .font(ChampionsTokens.cardCatLabel)
                .foregroundColor(.miyaDashboardTextSecond)
                .frame(width: ChampionsTokens.cardCatLabelWidth, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 6) {
                ChampionsMemberAvatar(member: member, size: ChampionsTokens.cardAvatarSize)
                Text(member.name.components(separatedBy: " ").first ?? member.name)
                    .font(ChampionsTokens.cardLeaderName)
                    .foregroundColor(.miyaDashboardTextPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(leader.displayValue + category.unit)
                .font(ChampionsTokens.cardScore)
                .foregroundColor(.miyaHeroAccentTeal)
                .multilineTextAlignment(.trailing)
        }
    }

    private func footerRow(data: ChampionsData) -> some View {
        HStack {
            overlappingAvatars(members: data.members)
            Spacer()
            Text("Tap to explore")
                .font(ChampionsTokens.cardTapLabel)
                .foregroundColor(.miyaHeroAccentTeal)
        }
    }

    private func overlappingAvatars(members: [ChampionMember]) -> some View {
        let ordered = members.sorted { $0.totalPoints > $1.totalPoints }
        let step: CGFloat = 20
        return ZStack(alignment: .leading) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, member in
                ChampionsMemberAvatar(member: member, size: ChampionsTokens.cardFooterAvatarSize)
                    .offset(x: CGFloat(index) * step)
                    .zIndex(Double(ordered.count - index))
            }
        }
        .frame(width: CGFloat(max(ordered.count, 1)) * step + 8, height: ChampionsTokens.cardFooterAvatarSize)
    }
}
