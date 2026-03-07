import SwiftUI
import SwiftUIX

// MARK: - All Notifications View
// Shows complete list of family notifications grouped by member, sorted by severity

struct AllNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var localNotifications: [FamilyNotificationItem] = []
    
    let notifications: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    let onSnooze: (FamilyNotificationItem, Int?) -> Void
    
    private typealias MemberGroup = (memberName: String, memberInitials: String, notifications: [FamilyNotificationItem])

    private var groupedNotifications: [MemberGroup] {
        let grouped: [String: [FamilyNotificationItem]] = Dictionary(grouping: localNotifications) { item in
            item.memberName
        }

        var result: [(memberName: String, memberInitials: String, notifications: [FamilyNotificationItem])] = []
        result.reserveCapacity(grouped.count)

        for (memberName, items) in grouped {
            let initials = items.first?.memberInitials ?? ""
            result.append((memberName: memberName, memberInitials: initials, notifications: items))
        }

        result.sort { $0.memberName < $1.memberName }
        return result
    }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle("Family Notifications")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .onAppear { localNotifications = notifications }
    .onChange(of: notifications.map(\.id)) { _, _ in
        localNotifications = notifications
    }
    }

    // MARK: - Main Content (split for compiler)

    @ViewBuilder
    private var content: some View {
        if localNotifications.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
        } else {
            notificationsList
        }
    }

    private var notificationsList: some View {
        List {
            ForEach(groupedNotifications, id: \.memberName) { group in
                memberSection(group)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private func memberSection(_ group: MemberGroup) -> some View {
        Section {
            ForEach(sortedBySeverity(group.notifications)) { notification in
                notificationRow(notification: notification)
                    .modifier(NotificationRowStyle())
            }
        } header: {
            memberHeader(group: group)
                .textCase(nil)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 80)
            
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.3))
            
            Text("No notifications")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DashboardDesign.primaryTextColor)
            
            Text("Your family members are all doing great!")
                .font(.system(size: 16))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Member Header
    @ViewBuilder
    private func memberHeader(group: MemberGroup) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 40, height: 40)

                Text(group.memberInitials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.memberName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DashboardDesign.primaryTextColor)

                Text("\(group.notifications.count) notification\(group.notifications.count == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
            }

            Spacer()
        }
    }

    private struct NotificationRowStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Notification Row (Swipe)
    @ViewBuilder
    private func notificationRow(notification: FamilyNotificationItem) -> some View {
        notificationCard(notification: notification)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    let id = notification.id
                    withAnimation(.easeInOut(duration: 0.15)) {
                        localNotifications.removeAll { $0.id == id }
                    }
                    onSnooze(notification, defaultSnoozeDays(for: notification))
                } label: {
                    Label("Snooze notification", systemImage: "bell.slash.fill")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    onTap(notification)
                } label: {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tint(.blue)
            }
    }
    
    // MARK: - Notification Card
    @ViewBuilder
    private func notificationCard(notification: FamilyNotificationItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                severityColor(notification).opacity(0.25),
                                severityColor(notification).opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                
                Image(systemName: pillarIcon(notification.pillar))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                severityColor(notification),
                                severityColor(notification).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                severityBadge(notification)
                    .offset(x: 18, y: -18)
            }
            
            Text(notification.displayLine)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .lineLimit(2)
                .truncationMode(.tail)
            
            Spacer(minLength: 8)
            
            VStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.4))
            }
        }
        .padding(16)
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
                            severityColor(notification).opacity(0.2),
                            severityColor(notification).opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    // MARK: - Severity Badge
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
    
    // MARK: - Helper Functions
    private func sortedBySeverity(_ notifications: [FamilyNotificationItem]) -> [FamilyNotificationItem] {
        notifications.sorted { n1, n2 in
            let s1 = getSeverity(n1)
            let s2 = getSeverity(n2)
            
            let priority1 = s1 == .attention ? 3 : (s1 == .watch ? 2 : 1)
            let priority2 = s2 == .attention ? 3 : (s2 == .watch ? 2 : 1)
            
            return priority1 > priority2
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
    
    private func severityColor(_ notification: FamilyNotificationItem) -> Color {
        let severity = getSeverity(notification)
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

    private func pillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.run"
        case .stress: return "heart.fill"
        }
    }
    
    private func defaultSnoozeDays(for notification: FamilyNotificationItem) -> Int {
        // “Snooze until next trigger” based on current trigger window
        // Uses existing model value: notification.triggerWindowDays (3/7/14/21)
        guard let current = notification.triggerWindowDays else {
            return 3 // fallback if we don’t know the trigger window
        }

        let next: Int? = {
            switch current {
            case 3: return 7
            case 7: return 14
            case 14: return 21
            default: return nil
            }
        }()

        // If there’s a next trigger, snooze for the delta.
        // If not (e.g. already at 21), fall back to 7 so the action still behaves predictably.
        if let next = next, next > current {
            return next - current
        } else {
            return 7
        }
    }
}

// MARK: - Preview
#Preview {
    AllNotificationsView(
        notifications: [],
        onTap: { _ in },
        onSnooze: { _, _ in }
    )
}
