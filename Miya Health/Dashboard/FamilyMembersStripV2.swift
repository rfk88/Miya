import SwiftUI

// MARK: - Family members strip (redesigned)

/// ~46pt avatar strip used by the redesigned dashboard.
///
/// Each member's circle is coloured by their weekly vitality tier:
///   - score >= 75 → pastel teal
///   - 55..<75    → pastel amber
///   - < 55       → pastel terracotta
///   - no data    → surface grey
///
/// Three additive overlays sit on the circle and never replace the tier
/// colour:
///   - bottom-right amber alert dot when the member has any active server
///     pattern alert
///   - top-right amber clock when the member is invited but not yet
///     onboarded
///   - top-right grey clock with a popover when the member's score is
///     stale (mutually exclusive with the pending clock)
///
/// Tap target is unchanged from the legacy strip: pushes
/// `FamilyMemberProfileView` when familyId + userId are available, otherwise
/// the placeholder ProfileView.
struct FamilyMembersStripV2: View {
    let members: [FamilyMemberScore]
    let familyId: String?
    /// Lower-cased member user ids currently flagged as having ≥1 active
    /// server pattern alert. Drives the bottom-right amber dot.
    let alertMemberIds: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(members) { member in
                    MemberAvatarV2(
                        member: member,
                        familyId: familyId,
                        hasActiveAlert: alertMemberIds.contains((member.userId ?? "").lowercased())
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Individual avatar

private struct MemberAvatarV2: View {
    let member: FamilyMemberScore
    let familyId: String?
    let hasActiveAlert: Bool

    @EnvironmentObject private var dataManager: DataManager
    @State private var showStalePopover = false

    private var tier: ScoreTier {
        guard member.hasScore else { return .noData }
        if member.isStale { return .noData }
        if member.currentScore >= 75 { return .good }
        if member.currentScore >= 55 { return .watch }
        return .low
    }

    var body: some View {
        NavigationLink {
            destinationView
        } label: {
            VStack(spacing: 8) {
                avatarCircle
                Text(member.isMe ? "Me" : member.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.miyaDashboardTextSecond)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Destination

    @ViewBuilder
    private var destinationView: some View {
        if let fid = familyId, let uid = member.userId {
            FamilyMemberProfileView(
                memberUserId: uid,
                memberName: member.name,
                familyId: fid,
                isCurrentUser: member.isMe
            )
        } else {
            ProfileView(
                memberName: member.name,
                vitalityScore: member.currentScore,
                vitalityTrendDelta: 0,
                vitalityLabel: vitalityLabelForScore(member.currentScore),
                avatarURL: nil
            )
        }
    }

    private func vitalityLabelForScore(_ score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80:  return "Good"
        case 40..<60:  return "Okay"
        default:       return "Needs attention"
        }
    }

    // MARK: Avatar circle

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(tier.background)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .stroke(Color.miyaCardWhite.opacity(0.95), lineWidth: 3)
                )
                .overlay(
                    Circle()
                        .stroke(tier.foreground.opacity(0.22), lineWidth: 1)
                        .padding(3)
                )
                .shadow(color: tier.foreground.opacity(0.12), radius: 8, x: 0, y: 4)

            Text(member.initials)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tier.foreground)

            // Top-right: pending OR stale (mutually exclusive).
            if member.isPending {
                pendingClock
            } else if member.isStale && !member.isPending {
                staleClockButton
            }

            // Bottom-right: amber alert dot.
            if hasActiveAlert {
                alertDot
            }
        }
        .frame(width: 64, height: 64, alignment: .center)
    }

    private var pendingClock: some View {
        Circle()
            .fill(Color.miyaCardWhite)
            .overlay(
                Image(systemName: "clock.badge")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.miyaAmber)
            )
            .frame(width: 18, height: 18)
            .overlay(
                Circle().stroke(Color.miyaCardWhite, lineWidth: 1.5)
            )
            .offset(x: 21, y: -21)
            .accessibilityLabel("Invitation pending")
    }

    private var staleClockButton: some View {
        Button {
            showStalePopover = true
        } label: {
            Circle()
                .fill(Color.miyaCardWhite)
                .overlay(
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.miyaTextTertiary)
                )
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().stroke(Color.miyaCardWhite, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .offset(x: 21, y: -21)
        .popover(isPresented: $showStalePopover, attachmentAnchor: .point(.topLeading)) {
            stalePopoverContent
        }
        .accessibilityLabel("Score out of date")
    }

    private var alertDot: some View {
        Circle()
            .fill(Color.miyaAmber)
            .frame(width: 13, height: 13)
            .overlay(
                Circle().stroke(Color.miyaCardWhite, lineWidth: 1.5)
            )
            .offset(x: 21, y: 21)
            .accessibilityLabel("Active alert")
    }

    // MARK: Stale popover (mirrors legacy strip copy)

    private var stalePopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Score out of date", systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text(staleAgeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text("Scores older than 3 days are shown greyed and excluded from family insights. Open the app regularly or keep Apple Health running to stay in sync.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    private var staleAgeText: String {
        guard let updatedAt = member.vitalityScoreUpdatedAt else {
            return "Last sync date unknown."
        }
        let days = Calendar.current.dateComponents([.day], from: updatedAt, to: Date()).day ?? 0
        if days <= 0 { return "Score was updated today." }
        if days == 1 { return "Score was last updated yesterday." }
        return "Score was last updated \(days) days ago."
    }
}
