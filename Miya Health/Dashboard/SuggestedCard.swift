import SwiftUI

// MARK: - Suggested card (redesign)

/// White card with the new "INSIGHTS" header and three lanes:
///   1. Wins              (teal dot)
///   2. Check in          (terracotta dot)
///   3. Family ops        (amber dot, max 1)
///
/// Total row count is capped at 4. When all lanes are empty, the card
/// renders the existing notifications empty-state copy instead of being
/// hidden, so the dashboard always shows an explanation for an empty
/// "Suggested" surface.
///
/// Routing is delegated to the parent through closures so this view never
/// reaches into DataManager directly.
struct SuggestedCard: View {
    let feed: SuggestedFeed
    let familyId: String?

    /// Push the member's existing profile view.
    let onOpenMemberDetail: (_ userId: String?, _ memberName: String) -> Void
    /// Open the existing Miya chat sheet.
    let onOpenMiyaChat: (_ userId: String?, _ memberName: String) -> Void
    /// Open the existing missing-wearable detail sheet for the given member.
    let onOpenWearableSetup: (_ userId: String?) -> Void

    private var orderedRows: [SuggestedRow] {
        feed.lane1 + feed.lane2 + feed.lane3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            contentBody
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.miyaCardWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.miyaDashboardTextPrimary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 10)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.miyaHeroAccentTeal)

            Text("INSIGHTS")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundColor(.miyaHeroAccentTeal)

            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Content body

    @ViewBuilder
    private var contentBody: some View {
        if feed.isEmpty {
            emptyStateRow
        } else {
            VStack(spacing: 0) {
                ForEach(Array(orderedRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                            .background(Color.miyaTextPrimary.opacity(0.05))
                    }
                    rowView(row)
                }
            }
        }
    }

    private var emptyStateRow: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color.miyaHeroAccentTeal.opacity(0.10), .clear],
                startPoint: .bottomTrailing,
                endPoint: .topLeading
            )

            Text("No alerts yet. As your family syncs more health data, insights will show up here.")
                .font(.system(size: 15))
                .foregroundColor(.miyaDashboardTextSecond)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: Row

    @ViewBuilder
    private func rowView(_ row: SuggestedRow) -> some View {
        switch row.action {
        case .openMemberDetail(let uid, let name):
            // Push the existing FamilyMemberProfileView when familyId + uid are present.
            if let fid = familyId, let id = uid {
                NavigationLink {
                    FamilyMemberProfileView(
                        memberUserId: id,
                        memberName: name,
                        familyId: fid,
                        isCurrentUser: false
                    )
                } label: {
                    rowLabel(row)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    onOpenMemberDetail(uid, name)
                } label: {
                    rowLabel(row)
                }
                .buttonStyle(.plain)
            }

        case .openMiyaChat(let uid, let name):
            Button {
                onOpenMiyaChat(uid, name)
            } label: {
                rowLabel(row)
            }
            .buttonStyle(.plain)

        case .openWearableSetup(let uid, _):
            Button {
                onOpenWearableSetup(uid)
            } label: {
                rowLabel(row)
            }
            .buttonStyle(.plain)

        case .openGuidedReview(let recordId, _):
            NavigationLink {
                GuidedSetupReviewView(memberId: recordId)
            } label: {
                rowLabel(row)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ row: SuggestedRow) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor(for: row.lane))
                .frame(width: 6, height: 6)

            Text(row.text)
                .font(.system(size: 15))
                .foregroundColor(.miyaDashboardTextPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 15))
                .foregroundColor(Color.miyaDashboardTextSecond.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func dotColor(for lane: SuggestedRow.Lane) -> Color {
        switch lane {
        case .wins:      return Color.miyaHeroAccentTeal
        case .checkIn:   return Color.miyaAlertCoral
        case .familyOps: return Color.miyaRecoveryAccent
        }
    }
}
