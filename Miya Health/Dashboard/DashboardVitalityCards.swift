import SwiftUI

// MARK: - FAMILY VITALITY CARD

struct FamilyVitalityCard: View {
    let score: Int
    let label: String
    let factors: [VitalityFactor]
    let includedMembersText: String?
    let progressScore: Int?
    let notifications: [FamilyNotificationItem]
    let onNotificationTap: ((FamilyNotificationItem) -> Void)?
    let onNotificationSeeAll: (() -> Void)?
    let onNotificationSnooze: ((FamilyNotificationItem, Int?) -> Void)?
    let onFactorTapped: (VitalityFactor) -> Void
    let onFamilyChallenges: (() -> Void)?
    
    @State private var itemToSnooze: FamilyNotificationItem? = nil
    
    init(
        score: Int,
        label: String,
        factors: [VitalityFactor],
        includedMembersText: String?,
        progressScore: Int?,
        notifications: [FamilyNotificationItem] = [],
        onNotificationTap: ((FamilyNotificationItem) -> Void)? = nil,
        onNotificationSeeAll: (() -> Void)? = nil,
        onNotificationSnooze: ((FamilyNotificationItem, Int?) -> Void)? = nil,
        onFactorTapped: @escaping (VitalityFactor) -> Void,
        onFamilyChallenges: (() -> Void)? = nil
    ) {
        self.score = score
        self.label = label
        self.factors = factors
        self.includedMembersText = includedMembersText
        self.progressScore = progressScore
        self.notifications = notifications
        self.onNotificationTap = onNotificationTap
        self.onNotificationSeeAll = onNotificationSeeAll
        self.onNotificationSnooze = onNotificationSnooze
        self.onFactorTapped = onFactorTapped
        self.onFamilyChallenges = onFamilyChallenges
    }

    private var progressFraction: Double {
        // Do NOT change logic: use progressScore if present, otherwise fall back to score/100.
        let p = Double(progressScore ?? score)
        return max(0.0, min(p / 100.0, 1.0))
    }

    private var progressLabelText: String {
        // Do NOT hardcode: reuse the values we already have.
        let current = progressScore ?? score
        return "Progress to optimal: \(current) / 100"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with score on right (like screenshot)
            HStack(alignment: .top) {
                Text("Family Vitality")
                    .font(DashboardDesign.title2Font)
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    
                    Spacer()
                    
                // Score on right (like screenshot)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(DashboardDesign.scoreLargeFont)
                        .foregroundColor(Color.miyaPrimary)  // Use brand color to stand out
                    
                    Text(label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }

            // Progress bar + label
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)

                        Capsule()
                            .fill(DashboardDesign.miyaTealSoft)
                            .frame(width: geo.size.width * progressFraction, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(progressLabelText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    
                    if let includedMembersText {
                        Text("• \(includedMembersText)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(DashboardDesign.tertiaryTextColor)
                    }
                }
            }

            // Divider before tiles
                    Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.top, 4)
                    
            // Tiles row (3 compact tiles) built from the SAME `factors` data
            // NOTE: We intentionally do NOT render "What's affecting vitality?" UI.
            HStack(spacing: 10) {
                ForEach(tilesToShow, id: \.id) { factor in
                    PillarTile(
                        factor: factor,
                        tint: tileTint(for: factor),
                        iconColor: tileIconColor(for: factor)
                    )
                    .onTapGesture {
                        // Keep interaction: tapping a tile selects the factor like before.
                        onFactorTapped(factor)
                    }
                }
            }
            
            if !notifications.isEmpty {
                embeddedNotificationsSection
            }
            
            if onFamilyChallenges != nil {
                Button(action: { onFamilyChallenges?() }) {
                    HStack {
                        Text("Family Challenges")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.miyaPrimary)
                    }
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.vertical, DashboardDesign.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius)
                .fill(Color.white)
        )
        .shadow(
            color: DashboardDesign.cardShadowStrong.color,
            radius: DashboardDesign.cardShadowStrong.radius,
            x: DashboardDesign.cardShadowStrong.x,
            y: DashboardDesign.cardShadowStrong.y
        )
    }

    private var tilesToShow: [VitalityFactor] {
        // Keep the same conceptual pillars: Sleep, Activity, Recovery (in that order if present).
        // Do NOT invent; filter from existing factors.
        let order = ["sleep", "activity", "recovery", "stress"]
        var map: [String: VitalityFactor] = [:]
        for f in factors { map[f.name.lowercased()] = f }
        let ordered = order.compactMap { map[$0] }
        // If any missing, fall back to first 3 factors without changing data.
        return ordered.isEmpty ? Array(factors.prefix(3)) : ordered
    }

    private func tileTint(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor.opacity(0.18)
        case "activity": return DashboardDesign.movementColor.opacity(0.18)
        case "stress", "recovery": return DashboardDesign.stressColor.opacity(0.18)
        default: return DashboardDesign.buttonTint.opacity(0.12)
        }
    }

    private func tileIconColor(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor
        case "activity": return DashboardDesign.movementColor
        case "stress", "recovery": return DashboardDesign.stressColor
        default: return DashboardDesign.buttonTint
        }
    }

    // MARK: - Embedded Family Notifications (inside Family Vitality card)
    
    private var dedupedNotifications: [FamilyNotificationItem] {
        FamilyNotificationItem.dedupedByMemberPillarWindow(notifications)
    }

    private var sortedNotifications: [FamilyNotificationItem] {
        dedupedNotifications.sorted { n1, n2 in
            let s1 = notificationSeverity(n1)
            let s2 = notificationSeverity(n2)
            
            let priority1 = s1 == .attention ? 3 : (s1 == .watch ? 2 : 1)
            let priority2 = s2 == .attention ? 3 : (s2 == .watch ? 2 : 1)
            
            return priority1 > priority2
        }
    }
    
    private func notificationSeverity(_ notification: FamilyNotificationItem) -> TrendSeverity {
        switch notification.kind {
        case .trend(let insight):
            return insight.severity
        case .fallback:
            return .attention
        }
    }
    
    private func notificationSeverityColor(_ notification: FamilyNotificationItem) -> Color {
        let severity = notificationSeverity(notification)
        switch severity {
        case .celebrate:
            return Color.green
        case .watch:
            return Color.orange
        case .attention:
            return Color.red
        @unknown default:
            return Color.orange
        }
    }

    private func notificationPillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.run"
        case .stress: return "heart.fill"
        }
    }
    
    @ViewBuilder
    private var embeddedNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Family notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if dedupedNotifications.count > 3, let onNotificationSeeAll {
                    Button {
                        onNotificationSeeAll()
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all (\(dedupedNotifications.count))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.miyaPrimary)
                    }
                }
            }
            
            VStack(spacing: 10) {
                ForEach(sortedNotifications.prefix(3)) { item in
                    embeddedNotificationRow(item)
                }
            }
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func embeddedNotificationRow(_ item: FamilyNotificationItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onNotificationTap?(item)
            } label: {
                embeddedNotificationCard(item)
            }
            .buttonStyle(.plain)
            
            if onNotificationSnooze != nil {
                Button {
                    itemToSnooze = item
                } label: {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .alert(
            "Are you sure you want to snooze this?",
            isPresented: Binding(
                get: { itemToSnooze != nil },
                set: { if !$0 { itemToSnooze = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                itemToSnooze = nil
            }
            Button("Snooze") {
                if let item = itemToSnooze {
                    onNotificationSnooze?(item, defaultSnoozeDays(for: item))
                }
                itemToSnooze = nil
            }
        }
    }
    
    private func embeddedNotificationCard(_ item: FamilyNotificationItem) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                // LEFT: member initials + pillar icon
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(DashboardDesign.tertiaryBackgroundColor)
                            .frame(width: 32, height: 32)
                        Text(item.memberInitials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DashboardDesign.primaryTextColor)
                    }
                    
                    Image(systemName: notificationPillarIcon(item.pillar))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(notificationSeverityColor(item))
                }
                
                // MIDDLE + RIGHT: compact summary with days/CTA just left of snooze
                HStack(spacing: 8) {
                    Text(embeddedSummaryLabel(for: item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        if let windowText = embeddedWindowLabel(for: item) {
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
        }
        .padding(12)
        .padding(.trailing, 44)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            notificationSeverityColor(item).opacity(0.2),
                            notificationSeverityColor(item).opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    private func defaultSnoozeDays(for notification: FamilyNotificationItem) -> Int {
        guard let current = notification.triggerWindowDays else {
            return 3
        }
        
        let next: Int? = {
            switch current {
            case 3: return 7
            case 7: return 14
            case 14: return 21
            default: return nil
            }
        }()
        
        if let next, next > current {
            return next - current
        } else {
            return 7
        }
    }
    
    @ViewBuilder
    private func embeddedSeverityBadge(_ notification: FamilyNotificationItem) -> some View {
        let severity = notificationSeverity(notification)
        
        if severity == .attention || severity == .celebrate {
            ZStack {
                Circle()
                    .fill(notificationSeverityColor(notification))
                    .frame(width: 20, height: 20)
                
                Image(systemName: severity == .attention ? "exclamationmark" : "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Embedded notification helpers
    
    private func embeddedWindowLabel(for item: FamilyNotificationItem) -> String? {
        return item.patternDurationToken
    }
    
    private func embeddedSummaryLabel(for item: FamilyNotificationItem) -> String {
        let pillarName: String
        switch item.pillar {
        case .sleep:
            pillarName = "Sleep"
        case .movement:
            pillarName = "Activity"
        case .stress:
            pillarName = "Recovery"
        }
        
        let severity = notificationSeverity(item)
        let status: String
        switch severity {
        case .celebrate:
            status = "up"
        case .watch:
            status = "drifting"
        case .attention:
            status = "low"
        @unknown default:
            status = "drifting"
        }

        return "\(pillarName) \(status)"
    }
    
    private struct PillarTile: View {
        let factor: VitalityFactor
        let tint: Color
        let iconColor: Color

        private enum DataStatus {
            case fresh, allStale, noScore
        }

        private var dataStatus: DataStatus {
            let scores = factor.memberScores
            guard !scores.isEmpty else { return .noScore }
            let allNoScore = scores.allSatisfy { !$0.hasScore }
            if allNoScore { return .noScore }
            let allStale = scores.allSatisfy { $0.isStale || !$0.hasScore }
            if allStale { return .allStale }
            return .fresh
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    // Icon (smaller, compact)
                    Image(systemName: factor.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(dataStatus == .fresh ? iconColor : Color.gray.opacity(0.5))

                    Spacer()

                    // Data gap indicator badge
                    if dataStatus != .fresh {
                        Image(systemName: dataStatus == .noScore ? "questionmark.circle.fill" : "clock.badge.exclamationmark.fill")
                            .font(.system(size: 13))
                            .foregroundColor(dataStatus == .noScore ? Color.gray.opacity(0.5) : Color.orange.opacity(0.75))
                    }
                }

                // Pillar name
                Text(factor.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)

                // Status label — or low-data notice
                if dataStatus == .noScore {
                    Text("No data yet")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.6))
                } else if dataStatus == .allStale {
                    Text("Data out of date")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.orange.opacity(0.8))
                } else {
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(
                color: DashboardDesign.cardShadow.color,
                radius: DashboardDesign.cardShadow.radius,
                x: DashboardDesign.cardShadow.x,
                y: DashboardDesign.cardShadow.y
            )
        }

        // MARK: - Status mapping helper

        private static func statusLabel(for percent: Int) -> String {
            let clamped = max(0, min(percent, 100))
            switch clamped {
            case 80...100:
                return "Excellent"
            case 65..<80:
                return "Good"
            case 50..<65:
                return "Stable"
            case 35..<50:
                return "Drifting"
            default:
                return "Urgent"
            }
        }

        private var statusLabel: String {
            Self.statusLabel(for: factor.percent)
        }
    }
}

struct FamilyVitalityPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Family vitality")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
                .padding(.top, 12)
            
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.miyaPrimary.opacity(0.6))
                
                VStack(spacing: 6) {
                    Text("Waiting for your family")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Once your family members complete onboarding and sync their health data, you'll see your family vitality score here.")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - PERSONAL VITALITY CARD

struct PersonalVitalityCard: View {
    let currentUser: FamilyMemberScore
    let factors: [VitalityFactor]
    var avatarURL: String? = nil
    @State private var isExpanded: Bool = false
    
    private func label(for score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80:  return "Good"
        case 40..<60:  return "Okay"
        default:       return "Needs attention"
        }
    }
    
    private func myPillarScore(named factorName: String) -> Int? {
        let match = factors.first(where: { $0.name.lowercased() == factorName.lowercased() })
        return match?.memberScores.first(where: { $0.isMe })?.currentScore
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            HStack(spacing: DashboardDesign.internalSpacing) {
                ProfileAvatarView(
                    imageURL: avatarURL,
                    initials: currentUser.initials,
                    diameter: 44,
                    backgroundColor: DashboardDesign.miyaTealSoft.opacity(0.15),
                    foregroundColor: DashboardDesign.miyaTealSoft.opacity(0.9),
                    font: DashboardDesign.bodyFont
                )
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
                    Text("My Vitality")
                        .font(DashboardDesign.bodySemiboldFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text(label(for: currentUser.currentScore))
                        .font(DashboardDesign.secondaryFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                Spacer()
                
                // Clear, non-gauge comparison: current vs optimal (premium typography)
                VStack(alignment: .trailing, spacing: DashboardDesign.tinySpacing) {
                    Text("\(currentUser.currentScore)/\(max(currentUser.optimalScore, 1))")
                        .font(DashboardDesign.scoreSmallFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text("Current / Optimal")
                        .font(DashboardDesign.tinyFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    if let p = currentUser.progressScore {
                        Text("Progress: \(p)/100")
                            .font(DashboardDesign.tinyFont)
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
            }
            
            if currentUser.optimalScore > 0 {
                ProgressView(value: Double(currentUser.currentScore), total: Double(currentUser.optimalScore))
                    .tint(DashboardDesign.miyaTealSoft)
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide submetrics" : "View submetrics")
                        .font(DashboardDesign.secondarySemiboldFont)
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                let sleep = myPillarScore(named: "Sleep")
                let movement = myPillarScore(named: "Activity")
                let stress = myPillarScore(named: "Recovery")
                
                HStack(spacing: DashboardDesign.internalSpacing) {
                    PillarMini(label: "Sleep", score: sleep)
                    PillarMini(label: "Movement", score: movement)
                    PillarMini(label: "Recovery", score: stress)
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

struct PillarMini: View {
    let label: String
    let score: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text(label)
                .font(DashboardDesign.captionSemiboldFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            
            Text(score.map { "\($0)/100" } ?? "—")
                .font(DashboardDesign.bodySemiboldFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
        }
        .padding(.vertical, DashboardDesign.smallSpacing)
        .padding(.horizontal, DashboardDesign.internalSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardDesign.tertiaryBackgroundColor)
        .cornerRadius(DashboardDesign.smallCornerRadius)
    }
}
