import SwiftUI

// MARK: - Family Notifications Card
// Extracted from DashboardNotifications.swift for better compilation performance

struct FamilyNotificationsCard: View {
    let items: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    let onSeeAll: () -> Void
    let onSnooze: (FamilyNotificationItem, Int?) -> Void
    
    @State private var itemToSnooze: FamilyNotificationItem?
    
    // MARK: - Grouped view model (one line per member + window)
    
    private struct GroupedNotification: Identifiable {
        let id: String
        let memberInitials: String
        let memberName: String
        var pillars: [VitalityPillar]
        let overallSeverity: TrendSeverity
        let windowDays: Int?
        let durationToken: String?
        /// Representative underlying item used for tap/snooze/detail.
        let representativeItem: FamilyNotificationItem
    }
    
    private var groupedItems: [GroupedNotification] {
        // Sort raw items by severity first, then fold into groups so the
        // highest severity item becomes the representative for each group.
        let sorted = sortedBySeverity(FamilyNotificationItem.dedupedByMemberPillarWindow(items))
        
        var groups: [String: GroupedNotification] = [:]
        var order: [String] = []
        
        for item in sorted {
            let memberKey = (item.memberUserId ?? item.memberName).lowercased()
            let pillarKey = item.pillar.rawValue
            let windowKey = item.triggerWindowDays ?? 0
            let key = "\(memberKey)-\(pillarKey)-\(windowKey)"
            let severity = getSeverity(item)
            
            if var existing = groups[key] {
                if !existing.pillars.contains(item.pillar) {
                    existing.pillars.append(item.pillar)
                }
                if severityPriority(for: severity) > severityPriority(for: existing.overallSeverity) {
                    existing = GroupedNotification(
                        id: existing.id,
                        memberInitials: existing.memberInitials,
                        memberName: existing.memberName,
                        pillars: existing.pillars,
                        overallSeverity: severity,
                        windowDays: existing.windowDays ?? item.triggerWindowDays,
                        durationToken: item.patternDurationToken ?? existing.durationToken,
                        representativeItem: item
                    )
                }
                groups[key] = existing
            } else {
                let group = GroupedNotification(
                    id: key,
                    memberInitials: item.memberInitials,
                    memberName: item.memberName,
                    pillars: [item.pillar],
                    overallSeverity: severity,
                    windowDays: item.triggerWindowDays,
                    durationToken: item.patternDurationToken,
                    representativeItem: item
                )
                groups[key] = group
                order.append(key)
            }
        }
        
        return order.compactMap { groups[$0] }
    }
    
    private var displayedGroups: [GroupedNotification] {
        Array(groupedItems.prefix(3))
    }
    
    private var hasMore: Bool {
        groupedItems.count > 3
    }
    
    private func pillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.run"
        case .stress: return "heart.fill"
        }
    }
    
    private func getSeverity(_ notification: FamilyNotificationItem) -> TrendSeverity {
        switch notification.kind {
        case .trend(let insight):
            return insight.severity
        case .fallback:
            return .attention
        }
    }
    
    private func severityPriority(for severity: TrendSeverity) -> Int {
        switch severity {
        case .attention: return 3
        case .watch: return 2
        case .celebrate: return 1
        @unknown default: return 2
        }
    }
    
    private func severityColor(for severity: TrendSeverity) -> Color {
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
    
    private func severityColor(_ notification: FamilyNotificationItem) -> Color {
        severityColor(for: getSeverity(notification))
    }
    
    private func sortedBySeverity(_ notifications: [FamilyNotificationItem]) -> [FamilyNotificationItem] {
        notifications.sorted { n1, n2 in
            let s1 = getSeverity(n1)
            let s2 = getSeverity(n2)
            
            let priority1 = severityPriority(for: s1)
            let priority2 = severityPriority(for: s2)
            
            return priority1 > priority2
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Family notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if hasMore {
                    Button {
                        onSeeAll()
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all (\(groupedItems.count))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    .foregroundColor(.miyaPrimary)
                    }
                }
            }
            
            VStack(spacing: 10) {
                ForEach(displayedGroups) { group in
                    notificationRow(group)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    @ViewBuilder
    private func notificationRow(_ group: GroupedNotification) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onTap(group.representativeItem)
            } label: {
                notificationCard(group)
            }
            .buttonStyle(.plain)

            Button {
                itemToSnooze = group.representativeItem
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
                    onSnooze(item, defaultSnoozeDays(for: item))
                }
                itemToSnooze = nil
            }
        }
    }

    private func notificationCard(_ group: GroupedNotification) -> some View {
        HStack(spacing: 12) {
            // LEFT: member initials + pillar icons
            HStack(spacing: 8) {
                // LEFT: member initials + pillar icons
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(DashboardDesign.tertiaryBackgroundColor)
                            .frame(width: 32, height: 32)
                        Text(group.memberInitials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DashboardDesign.primaryTextColor)
                    }
                    
                    HStack(spacing: 4) {
                        ForEach(group.pillars, id: \.self) { pillar in
                            Image(systemName: pillarIcon(pillar))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(severityColor(for: group.overallSeverity))
                        }
                    }
                }
                
                // MIDDLE + RIGHT: summary with days/CTA just left of snooze
                HStack(spacing: 8) {
                    Text(summaryLabel(for: group))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        if let windowText = windowLabel(for: group) {
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
                            severityColor(for: group.overallSeverity).opacity(0.2),
                            severityColor(for: group.overallSeverity).opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    private func defaultSnoozeDays(for notification: FamilyNotificationItem) -> Int {
        // “Snooze until next trigger” based on current trigger window
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

        if let next = next, next > current {
            return next - current
        } else {
            return 7
        }
    }
    
    @ViewBuilder
    private func severityBadge(_ notification: FamilyNotificationItem) -> some View {
        let severity = getSeverity(notification)
        
        if severity == .attention || severity == .celebrate {
            ZStack {
                Circle()
                    .fill(severityColor(notification))
                    .frame(width: 20, height: 20)
                
                Image(systemName: severity == .attention ? "exclamationmark" : "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Grouped row helpers
    
    private func windowLabel(for group: GroupedNotification) -> String? {
        return group.durationToken
    }
    
    private func summaryLabel(for group: GroupedNotification) -> String {
        let names = group.pillars.map { pillar -> String in
            switch pillar {
            case .sleep: return "Sleep"
            case .movement: return "Activity"
            case .stress: return "Recovery"
            }
        }
        
        let joined: String
        if names.isEmpty {
            joined = "Check in"
        } else if names.count == 1 {
            joined = names[0]
        } else if names.count == 2 {
            joined = "\(names[0]) & \(names[1])"
        } else {
            joined = "Multiple pillars"
        }
        
        // Keep copy tight and action-oriented
        return "\(joined) low"
    }
}

// MARK: - Premium Button Style for Notification Cards
struct NotificationCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Conditional modifier helper
private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview("FamilyNotificationsCard") {
    FamilyNotificationsCard(
        items: [],
        onTap: { _ in },
        onSeeAll: {},
        onSnooze: { _, _ in }
    )
    .padding()
    .background(Color.gray.opacity(0.08))
}
 
