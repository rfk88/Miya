import SwiftUI

// MARK: - FAMILY MEMBERS STRIP

struct FamilyMembersStrip: View {
    let members: [FamilyMemberScore]
    let familyId: String?
    var currentUserAvatarURL: String? = nil

    private func label(for score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80: return "Good"
        case 40..<60: return "Okay"
        default: return "Needs attention"
            }
        }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardDesign.internalSpacing) {
                ForEach(members) { member in
                    MemberProfileLink(
                        member: member,
                        vitalityLabel: label(for: member.currentScore),
                        familyId: familyId,
                        currentUserAvatarURL: currentUserAvatarURL
                    )
                }
            }
            .padding(.horizontal, DashboardDesign.tinySpacing)
        }
    }
    
    private struct MemberProfileLink: View {
        let member: FamilyMemberScore
        let vitalityLabel: String
        let familyId: String?
        var currentUserAvatarURL: String? = nil

        private var progress: CGFloat {
            CGFloat(member.ringProgress)
        }
        
        var body: some View {
            NavigationLink {
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
                        vitalityLabel: vitalityLabel,
                        avatarURL: member.isMe ? currentUserAvatarURL : nil
                    )
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack {
                        // Background circle (premium styling)
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 68, height: 68)
                            .shadow(
                                color: DashboardDesign.cardShadowLight.color,
                                radius: DashboardDesign.cardShadowLight.radius,
                                x: DashboardDesign.cardShadowLight.x,
                                y: DashboardDesign.cardShadowLight.y
                            )
                        
                        // Inner avatar (refined sizing)
                        Circle()
                            .fill(DashboardDesign.groupedBackground)
                            .frame(width: 52, height: 52)

                        if member.isMe {
                            ProfileAvatarView(
                                imageURL: currentUserAvatarURL,
                                initials: member.initials,
                                diameter: 52,
                                backgroundColor: DashboardDesign.groupedBackground,
                                foregroundColor: DashboardDesign.primaryTextColor,
                                font: .system(size: 19, weight: .semibold, design: .default)
                            )
                            .frame(width: 52, height: 52)
                        } else {
                            Text(member.initials)
                                .font(.system(size: 19, weight: .semibold, design: .default))
                                .foregroundColor(DashboardDesign.primaryTextColor)
                        }
                        
                        // Pending badge
                        if member.isPending {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "clock.badge")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.orange)
                                        .padding(4)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    vitalityBar
                    
                    // Name under avatar (refined typography)
                    Text(member.isMe ? "Me" : member.name)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(member.isPending ? .miyaTextSecondary : .miyaTextPrimary)
                }
            }
            .buttonStyle(.plain)
        }
        
        // MARK: - Horizontal Vitality Bar
        
        private var vitalityBar: some View {
            let totalWidth: CGFloat = 68
            let height: CGFloat = 6
            let clamped = max(0, min(progress, 1))
            let rawFillWidth = totalWidth * clamped
            let fillWidth = (clamped == 0) ? 0 : max(rawFillWidth, height)
            
            let baseColor: Color = member.isStale ? Color.gray.opacity(0.8) : DashboardDesign.miyaTealSoft
            let barOpacity: Double = member.isPending ? 0.4 : 1.0
            
            return ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(DashboardDesign.tertiaryBackgroundColor)
                
                if fillWidth > 0 {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(baseColor)
                        .frame(width: fillWidth)
                        .opacity(barOpacity)
                        .animation(.easeInOut(duration: 0.2), value: fillWidth)
                }
            }
            .frame(width: totalWidth, height: height, alignment: .leading)
        }
    }
}

// MARK: - Guided Setup Status (Admin)

struct GuidedSetupStatusCard: View {
    let members: [FamilyMemberRecord]
    let familyName: String
    let onDismiss: (String) -> Void
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.miyaSecondary)
                Text("Guided setup")
                    .font(.headline)
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
            }
            
            if members.isEmpty {
                Text("No guided setup members.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(members, id: \.id) { member in
                        GuidedSetupMemberRow(
                            member: member,
                            familyName: familyName,
                            onDismiss: onDismiss,
                            onAction: onAction
                        )
                    }
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

struct GuidedSetupMemberRow: View {
    let member: FamilyMemberRecord
    let familyName: String
    let onDismiss: (String) -> Void
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
    
    private var status: GuidedSetupStatus {
        // Canonical source of truth: family_members.guided_setup_status
        // For guided members, default nil/unknown to pending_acceptance for display only.
        normalizeGuidedSetupStatus(member.guidedSetupStatus)
    }
    
    private var label: String {
        switch status {
        case .pendingAcceptance: return "Invite not accepted"
        case .acceptedAwaitingData: return "Waiting for you"
        case .dataCompletePendingReview: return "Waiting for member review"
        case .reviewedComplete: return "Complete"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.miyaPrimary.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(member.firstName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.miyaPrimary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.firstName)
                    .font(.subheadline.bold())
                    .foregroundColor(.miyaTextPrimary)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Family: \(familyName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            actionCTA
        }
        .padding(DashboardDesign.internalSpacing)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.smallCornerRadius)
                .fill(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
        )
    }
    
    @ViewBuilder
    private var actionCTA: some View {
        switch status {
        case .pendingAcceptance:
            Button("Resend invite") { onAction(member, .resendInvite) }
                .font(.caption.bold())
                .foregroundColor(.miyaPrimary)
        case .acceptedAwaitingData:
            NavigationLink {
                GuidedHealthDataEntryFlow(
                    memberId: member.id.uuidString,
                    memberName: member.firstName,
                    inviteCode: member.inviteCode ?? ""
                ) { }
            } label: {
                Text("Start guided setup")
                    .font(.caption.bold())
                    .foregroundColor(.miyaPrimary)
            }
        case .dataCompletePendingReview:
            Button("Remind member") { onAction(member, .remindMember) }
                .font(.caption.bold())
                .foregroundColor(.miyaPrimary)
        case .reviewedComplete:
            HStack(spacing: 12) {
                NavigationLink {
                    // Placeholder: ProfileView currently expects basic display inputs.
                    // This keeps the CTA functional while member-specific profile wiring is completed later.
                    ProfileView(
                        memberName: member.firstName,
                        vitalityScore: 0,
                        vitalityTrendDelta: 0,
                        vitalityLabel: "—"
                    )
                } label: {
                    Text("View profile")
                        .font(.caption.bold())
                        .foregroundColor(.miyaPrimary)
                }
                
                Button {
                    onDismiss(member.id.uuidString)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

