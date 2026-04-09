//
//  DashboardOrientationPreviews.swift
//  Miya Health
//
//  Feature-sourced mini previews used by DashboardOrientationView cards.
//  Styling matches DashboardDesign + FamilyVitalityCard / FamilyNotificationsCard / FamilyChallengesView tokens.
//

import SwiftUI

enum DashboardOrientationPreviewKind {
    case familyHub
    case everyoneSetup
    case familyMVP
    case familyNotifications
    case challenges
    case careSupport
    case ready
}

struct DashboardOrientationFeaturePreview: View {
    let kind: DashboardOrientationPreviewKind
    let pulseScale: CGFloat
    /// Tapping **Go to dashboard** on the ready card completes the tour (no duplicate bottom CTA).
    var onReadyEnterTapped: (() -> Void)? = nil

    var body: some View {
        ZStack {
            previewOuterChrome

            previewBody
                .padding(DashboardDesign.smallSpacing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: kind == .ready ? 220 : 190)
        .scaleEffect(pulseScale)
    }

    /// Matches `FamilyNotificationsCard` outer container (white, 24pt continuous, dual shadow).
    private var previewOuterChrome: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(DashboardDesign.cardBackgroundColor)
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch kind {
        case .familyHub:
            familyVitalityPreview
        case .everyoneSetup:
            familySetupPreview
        case .familyMVP:
            familyMVPPreview
        case .familyNotifications:
            familyNotificationsPreview
        case .challenges:
            challengesPreview
        case .careSupport:
            careSupportPreview
        case .ready:
            readyPreview
        }
    }

    // MARK: - Card 1: Family hub (FamilyVitalityCard)

    private var familyVitalityPreview: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.microSpacing) {
            HStack(alignment: .top) {
                Text("Family Vitality")
                    .font(DashboardDesign.title2Font)
                    .foregroundColor(DashboardDesign.primaryTextColor)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("79")
                        .font(DashboardDesign.scoreMediumFont)
                        .foregroundColor(Color.miyaPrimary)

                    Text("Good")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }

            VStack(spacing: DashboardDesign.microSpacing) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)

                        Capsule()
                            .fill(DashboardDesign.miyaTealSoft)
                            .frame(width: geo.size.width * 0.79, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("Progress to optimal: 79 / 100")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    Spacer()
                }
            }

            Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.vertical, 2)

            HStack(spacing: 10) {
                miniPillarTile(
                    icon: "moon.stars.fill",
                    name: "Sleep",
                    status: "Good",
                    iconColor: DashboardDesign.sleepColor
                )
                miniPillarTile(
                    icon: "figure.run",
                    name: "Movement",
                    status: "Excellent",
                    iconColor: DashboardDesign.movementColor
                )
                miniPillarTile(
                    icon: "heart.fill",
                    name: "Recovery",
                    status: "Fair",
                    iconColor: DashboardDesign.stressColor
                )
            }
        }
    }

    /// Mirrors `PillarTile` in `DashboardVitalityCards` (corner radius, shadow, typography).
    private func miniPillarTile(icon: String, name: String, status: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DashboardDesign.primaryTextColor)

            Text(status)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                .fill(DashboardDesign.cardBackgroundColor)
        )
        .shadow(
            color: DashboardDesign.cardShadow.color,
            radius: DashboardDesign.cardShadow.radius,
            x: DashboardDesign.cardShadow.x,
            y: DashboardDesign.cardShadow.y
        )
    }

    // MARK: - Card 2: Setup

    private var familySetupPreview: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text("Family setup")
                .font(DashboardDesign.title2Font)
                .foregroundColor(DashboardDesign.primaryTextColor)

            setupProgressRow(name: "You", done: true)
            setupProgressRow(name: "Partner", done: true)
            setupProgressRow(name: "Dad", done: false)
        }
    }

    private func setupProgressRow(name: String, done: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? Color.green : Color.orange)
                .font(.system(size: 16, weight: .semibold))
            Text(name)
                .font(DashboardDesign.calloutFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
            Spacer()
            Text(done ? "Complete" : "Pending")
                .font(DashboardDesign.captionSemiboldFont)
                .foregroundColor(done ? Color.green : Color.orange)
        }
    }

    // MARK: - Card 3: Family MVP / at a glance

    private var familyMVPPreview: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            HStack(alignment: .top) {
                Text("At a glance")
                    .font(DashboardDesign.title2Font)
                    .foregroundColor(DashboardDesign.primaryTextColor)
                Spacer()
                Text("Today")
                    .font(DashboardDesign.secondarySemiboldFont)
                    .foregroundColor(DashboardDesign.secondaryTextColor)
            }

            HStack(spacing: 10) {
                miniPillarTile(
                    icon: "moon.stars.fill",
                    name: "Sleep",
                    status: "78",
                    iconColor: DashboardDesign.sleepColor
                )
                miniPillarTile(
                    icon: "figure.run",
                    name: "Movement",
                    status: "81",
                    iconColor: DashboardDesign.movementColor
                )
                miniPillarTile(
                    icon: "heart.fill",
                    name: "Recovery",
                    status: "74",
                    iconColor: DashboardDesign.stressColor
                )
            }
        }
    }

    // MARK: - Card 4: Family notifications (`FamilyNotificationsCard` / embedded rows)

    private var familyNotificationsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Family notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("See all")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.miyaPrimary)
            }

            miniEmbeddedNotificationCard(
                initials: "DM",
                pillarIcon: "moon.stars.fill",
                severityColor: Color.orange,
                summary: "Sleep pattern shifted",
                windowText: "7d"
            )

            miniEmbeddedNotificationCard(
                initials: "SK",
                pillarIcon: "heart.fill",
                severityColor: Color.red,
                summary: "Recovery needs attention",
                windowText: "3d"
            )
        }
    }

    /// Mirrors `embeddedNotificationCard` in `DashboardVitalityCards` (fonts, radii, shadows, gradient stroke).
    private func miniEmbeddedNotificationCard(
        initials: String,
        pillarIcon: String,
        severityColor: Color,
        summary: String,
        windowText: String?
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(DashboardDesign.tertiaryBackgroundColor)
                        .frame(width: 32, height: 32)
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                }

                Image(systemName: pillarIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(severityColor)
            }

            HStack(spacing: 8) {
                Text(summary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    if let windowText {
                        Text(windowText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(DashboardDesign.tertiaryBackgroundColor)
                            )
                    }

                    Text("See why")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DashboardDesign.cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            severityColor.opacity(0.2),
                            severityColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Card 5: Challenges (`FamilyChallengesView.challengeRow` + `statusPill`)

    private var challengesPreview: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text("Family challenges")
                .font(DashboardDesign.title2Font)
                .foregroundColor(DashboardDesign.primaryTextColor)

            orientationChallengeRow(memberLabel: "Sam", pillar: "movement", status: "active")
            orientationChallengeRow(memberLabel: "Dad", pillar: "sleep", status: "pending_invite")
        }
    }

    private func orientationChallengeRow(memberLabel: String, pillar: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(memberLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                orientationPillarIcon(pillar)
                Spacer()
                orientationStatusPill(status)
            }
            Text("Day 3 of 7 · 2 days hit")
                .font(.system(size: 13))
                .foregroundColor(DashboardDesign.secondaryTextColor)
        }
        .padding(.vertical, 4)
    }

    private func orientationPillarIcon(_ pillar: String) -> some View {
        let icon: String = {
            switch pillar.lowercased() {
            case "sleep": return "moon.stars.fill"
            case "movement": return "figure.run"
            case "stress": return "heart.fill"
            default: return "flag.checkered"
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundColor(.miyaPrimary)
    }

    private func orientationStatusPill(_ status: String) -> some View {
        let label: String = {
            switch status {
            case "pending_invite": return "Pending"
            case "snoozed": return "Maybe later"
            case "active": return "Active"
            case "completed_success": return "Completed"
            case "completed_failed": return "Didn't quite get there"
            default: return status
            }
        }()
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(status == "active" ? .miyaPrimary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((status == "active" ? Color.miyaPrimary : Color.gray).opacity(0.15))
            )
    }

    // MARK: - Card 6: Care / support

    private var careSupportPreview: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text("Support action")
                .font(DashboardDesign.title2Font)
                .foregroundColor(DashboardDesign.primaryTextColor)

            Text("Miya suggestion")
                .font(DashboardDesign.secondarySemiboldFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)

            Text("“Hey, I noticed your sleep slipped this week. Want to do a wind-down challenge together?”")
                .font(DashboardDesign.calloutFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DashboardDesign.tinySpacing) {
                primaryCapsuleButton("Use template")
                secondaryCapsuleButton("Edit")
            }
        }
    }

    private func primaryCapsuleButton(_ title: String) -> some View {
        Text(title)
            .font(DashboardDesign.captionSemiboldFont)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.miyaPrimary))
    }

    private func secondaryCapsuleButton(_ title: String) -> some View {
        Text(title)
            .font(DashboardDesign.captionSemiboldFont)
            .foregroundColor(Color.miyaPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(DashboardDesign.tertiaryBackgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(Color.miyaPrimary.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Card 7: Ready

    private var readyPreview: some View {
        VStack(spacing: DashboardDesign.tinySpacing) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.miyaPrimary)

            Text("You’re all set")
                .font(DashboardDesign.titleFont)
                .foregroundColor(DashboardDesign.primaryTextColor)

            Text("Start by checking your family, or wait for Miya to alert you when something needs attention.")
                .font(DashboardDesign.secondaryFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let onReadyEnterTapped {
                Button(action: onReadyEnterTapped) {
                    Text("Go to dashboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                                .fill(Color.miyaPrimary)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("Go to dashboard and close tour")
            } else {
                // Preview / SwiftUI canvas without a handler
                Text("Go to dashboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                            .fill(Color.miyaPrimary)
                    )
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
