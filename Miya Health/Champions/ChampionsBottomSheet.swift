import SwiftUI
import UIKit

struct ChampionsBottomSheet: View {
    let data: ChampionsData
    @Binding var isPresented: Bool
    @Binding var dragOffset: CGFloat

    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    @State private var expandedSections: Set<ChampionCategoryType> = []
    @State private var isSeasonExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            sheetChrome
                .gesture(dismissDragGesture)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(ChampionCategoryType.allCases, id: \.self) { cat in
                        if let category = data.categories.first(where: { $0.id == cat }) {
                            categorySection(category: category)
                        }
                    }
                    seasonSection
                }
                .padding(.bottom, ChampionsTokens.seasonBottomPad)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: screenHeight * ChampionsTokens.sheetMaxHeightPct, alignment: .top)
        .background(ChampionsTokens.surfaceSheet)
        .clipShape(RoundedRectangle(cornerRadius: ChampionsTokens.sheetTopRadius, style: .continuous))
        .offset(y: dragOffset)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        isPresented = false
                    }
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var sheetChrome: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: ChampionsTokens.sheetHandleRadius)
                .fill(ChampionsTokens.sheetHandle)
                .frame(width: ChampionsTokens.sheetHandleWidth, height: ChampionsTokens.sheetHandleHeight)
                .padding(.top, ChampionsTokens.sheetHandlePadT)
                .padding(.bottom, ChampionsTokens.sheetHandlePadB)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Champions")
                            .font(ChampionsTokens.sheetTitle)
                            .foregroundColor(ChampionsTokens.textPrimary)
                            .kerning(-0.36)
                        if data.isLive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(ChampionsTokens.liveGreen)
                                    .frame(width: 6, height: 6)
                                    .modifier(ChampionsLivePulseModifier())
                                Text("Live")
                                    .font(ChampionsTokens.sheetLive)
                                    .foregroundColor(ChampionsTokens.textSecondary)
                            }
                        }
                    }
                    Text("Week \(data.season.weekNumber) · \(data.season.name) · \(data.season.daysRemaining) days left")
                        .font(ChampionsTokens.sheetSubtitle)
                        .foregroundColor(ChampionsTokens.textMuted)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ChampionsTokens.textSecondary)
                        .frame(width: ChampionsTokens.sheetCloseBtnSize, height: ChampionsTokens.sheetCloseBtnSize)
                        .background(ChampionsTokens.surfaceChip)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ChampionsTokens.sheetHeaderPadH)
            .padding(.top, ChampionsTokens.sheetHeaderPadT)
            .padding(.bottom, ChampionsTokens.sheetHeaderPadB)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ChampionsTokens.borderSheet)
                    .frame(height: 1)
            }
        }
    }

    private func categorySection(category: ChampionCategory) -> some View {
        let isExpanded = expandedSections.contains(category.id)
        return VStack(spacing: 0) {
            collapsedCategoryHeader(category: category, isExpanded: isExpanded)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.42)) {
                        if expandedSections.contains(category.id) {
                            expandedSections.remove(category.id)
                        } else {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            expandedSections.insert(category.id)
                        }
                    }
                }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(category.rows.enumerated()), id: \.element.id) { index, row in
                        if let member = data.member(for: row.id) {
                            expandedMemberRow(
                                category: category.id,
                                member: member,
                                row: row,
                                rank: index + 1,
                                index: index
                            )
                        }
                    }
                }
                .padding(.horizontal, ChampionsTokens.expandedPadH)
                .padding(.bottom, ChampionsTokens.expandedPadBottom)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.42), value: isExpanded)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChampionsTokens.borderSheet)
                .frame(height: 1)
        }
    }

    private func collapsedCategoryHeader(category: ChampionCategory, isExpanded: Bool) -> some View {
        let cat = category.id
        let leader = category.leader.flatMap { data.member(for: $0.id) }
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: ChampionsTokens.sectionIconRadius)
                    .fill(cat.backgroundColor)
                    .frame(width: ChampionsTokens.sectionIconSize, height: ChampionsTokens.sectionIconSize)
                Image(systemName: cat.icon)
                    .font(.system(size: ChampionsTokens.sectionIconInner, weight: .semibold))
                    .foregroundColor(cat.accentColor)
            }
            Text(cat.displayName)
                .font(ChampionsTokens.sectionName)
                .foregroundColor(ChampionsTokens.textPrimary)
                .kerning(-0.15)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let leader {
                HStack(spacing: 7) {
                    ChampionsMemberAvatar(member: leader, size: ChampionsTokens.sectionLeaderAvatar)
                    Text(leader.name.components(separatedBy: " ").first ?? leader.name)
                        .font(ChampionsTokens.sectionLeader)
                        .foregroundColor(ChampionsTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ChampionsTokens.textHint)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .padding(.horizontal, ChampionsTokens.sectionPadH)
        .padding(.vertical, ChampionsTokens.sectionPadV)
    }

    private func expandedMemberRow(
        category: ChampionCategoryType,
        member: ChampionMember,
        row: CategoryMemberRow,
        rank: Int,
        index: Int
    ) -> some View {
        let delay = Double(index) * 0.065
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(ChampionsTokens.rowRank)
                .foregroundColor(ChampionsTokens.textHint)
                .frame(width: ChampionsTokens.rowRankWidth, alignment: .center)

            ChampionsMemberAvatar(member: member, size: ChampionsTokens.rowAvatarSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(ChampionsTokens.rowName)
                        .foregroundColor(ChampionsTokens.textPrimary)
                    ChampionsHexBadge(tier: member.tier, size: 14)
                        .modifier(ChampionsBadgePopModifier(delay: delay + 0.12))
                }
                Text(member.tier.rawValue)
                    .font(ChampionsTokens.rowTier)
                    .foregroundColor(ChampionsTokens.textMuted)
            }

            Spacer()

            Text(row.displayValue + category.unit)
                .font(ChampionsTokens.rowScore)
                .foregroundColor(row.status == .leading ? ChampionsTokens.teal : ChampionsTokens.textMuted)
                .frame(minWidth: ChampionsTokens.rowScoreMinWidth, alignment: .trailing)
                .padding(.trailing, ChampionsTokens.rowScoreMarginR)

            ChampionsStatusPill(status: row.status)
        }
        .padding(.vertical, ChampionsTokens.rowPadV)
        .padding(.horizontal, ChampionsTokens.rowPadH)
        .background(championsRowBackground(for: row.status))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(championsLeftBorderColor(for: row.status))
                .frame(width: ChampionsTokens.rowLeftBorder)
        }
        .cornerRadius(ChampionsTokens.rowRadius)
        .padding(.bottom, ChampionsTokens.rowMarginBottom)
        .modifier(ChampionsRowStaggerModifier(delay: delay))
    }

    private var seasonSection: some View {
        VStack(spacing: 0) {
            seasonCollapsedHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        if isSeasonExpanded {
                            isSeasonExpanded = false
                        } else {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isSeasonExpanded = true
                        }
                    }
                }

            if isSeasonExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(data.membersSortedByPoints.enumerated()), id: \.element.id) { index, member in
                        ChampionsSeasonMemberRow(member: member, rank: index + 1, index: index)
                    }
                }
                .padding(.horizontal, ChampionsTokens.expandedPadH)
                .padding(.bottom, ChampionsTokens.expandedPadBottom)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isSeasonExpanded)
        .clipped()
    }

    private var seasonCollapsedHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: ChampionsTokens.sectionIconRadius)
                    .fill(ChampionsTokens.trophyBg)
                    .frame(width: ChampionsTokens.sectionIconSize, height: ChampionsTokens.sectionIconSize)
                Image(systemName: "trophy.fill")
                    .font(.system(size: ChampionsTokens.sectionIconInner, weight: .semibold))
                    .foregroundColor(ChampionsTokens.trophyCol)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Season Points")
                    .font(ChampionsTokens.seasonTitle)
                    .foregroundColor(ChampionsTokens.textPrimary)
                    .kerning(-0.15)
                Text("\(data.season.name) · Week \(data.season.weekNumber) of \(data.season.totalWeeks)")
                    .font(ChampionsTokens.seasonSub)
                    .foregroundColor(ChampionsTokens.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ChampionsTokens.textHint)
                .rotationEffect(.degrees(isSeasonExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.3), value: isSeasonExpanded)
        }
        .padding(.horizontal, ChampionsTokens.sectionPadH)
        .padding(.vertical, ChampionsTokens.sectionPadV)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChampionsTokens.borderSheet)
                .frame(height: 1)
        }
    }
}

// MARK: - Season expanded row

private struct ChampionsSeasonMemberRow: View {
    let member: ChampionMember
    let rank: Int
    let index: Int

    @State private var progressAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(ChampionsTokens.seasonRank)
                    .foregroundColor(ChampionsTokens.textHint)
                    .frame(width: ChampionsTokens.rowRankWidth, alignment: .center)

                ChampionsMemberAvatar(member: member, size: ChampionsTokens.seasonAvatarSize)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(ChampionsTokens.seasonName)
                            .foregroundColor(ChampionsTokens.textPrimary)
                        ChampionsHexBadge(tier: member.tier, size: 14)
                        Text(member.tier.rawValue)
                            .font(ChampionsTokens.seasonTier)
                            .foregroundColor(ChampionsTokens.textMuted)
                    }
                    if let nextTier = member.tier.nextTier, let remaining = member.pointsToNextTier, remaining > 0 {
                        Text("\(remaining) pts to \(nextTier.rawValue)")
                            .font(ChampionsTokens.seasonRemain)
                            .foregroundColor(ChampionsTokens.textHint)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: -2) {
                    Text(member.totalPoints, format: .number)
                        .font(ChampionsTokens.seasonPtsNum)
                        .foregroundColor(ChampionsTokens.textPrimary)
                        .kerning(-0.8)
                        .modifier(ChampionsCountInModifier(delay: Double(index) * 0.08 + 0.13))
                    Text("pts")
                        .font(ChampionsTokens.seasonPtsUnit)
                        .foregroundColor(ChampionsTokens.textMuted)
                }
            }
            .padding(.bottom, 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(hex: "F1F5F9"))
                        .frame(height: ChampionsTokens.seasonProgressH)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: member.tier.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: progressAppeared ? geo.size.width * member.tierProgress : 0,
                            height: ChampionsTokens.seasonProgressH
                        )
                        .animation(
                            .easeInOut(duration: 1.2).delay(Double(index) * 0.08),
                            value: progressAppeared
                        )
                }
                .cornerRadius(4)
            }
            .frame(height: ChampionsTokens.seasonProgressH)
            .padding(.leading, ChampionsTokens.seasonProgressPadL)
        }
        .modifier(ChampionsRowStaggerModifier(delay: Double(index) * 0.08))
        .padding(.bottom, ChampionsTokens.seasonRowMarginB)
        .onAppear {
            progressAppeared = true
        }
        .onDisappear {
            progressAppeared = false
        }
    }
}
