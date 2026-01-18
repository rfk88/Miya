import SwiftUI
import SwiftUIX

// MARK: - All Notifications View
// Shows complete list of family notifications grouped by member, sorted by severity

struct AllNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let notifications: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    let onSnooze: (FamilyNotificationItem, Int?) -> Void
    
    @State private var showingSnoozeAlert = false
    @State private var selectedNotification: FamilyNotificationItem?
    
    private var groupedNotifications: [(memberName: String, memberInitials: String, notifications: [FamilyNotificationItem])] {
        let grouped = Dictionary(grouping: notifications) { $0.memberName }
        
        return grouped.map { (memberName: $0.key, memberInitials: $0.value.first?.memberInitials ?? "", notifications: $0.value) }
            .sorted { $0.memberName < $1.memberName }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if notifications.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedNotifications, id: \.memberName) { group in
                            memberSection(group: group)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground))
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
        .confirmationDialog(
            "Snooze Notification",
            isPresented: $showingSnoozeAlert,
            titleVisibility: .visible,
            presenting: selectedNotification
        ) { notification in
            Button("1 day") { onSnooze(notification, 1) }
            Button("3 days") { onSnooze(notification, 3) }
            Button("7 days") { onSnooze(notification, 7) }
            Button("Dismiss permanently") { onSnooze(notification, nil) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("How long would you like to snooze this notification?")
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
    
    // MARK: - Member Section
    @ViewBuilder
    private func memberSection(group: (memberName: String, memberInitials: String, notifications: [FamilyNotificationItem])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Member header
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
            .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                ForEach(sortedBySeverity(group.notifications)) { notification in
                    notificationCard(notification: notification)
                }
            }
        }
    }
    
    // MARK: - Notification Card
    @ViewBuilder
    private func notificationCard(notification: FamilyNotificationItem) -> some View {
        Button {
            onTap(notification)
        } label: {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    
                    Text(notification.body)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                
                Spacer(minLength: 8)
                
                VStack(spacing: 8) {
                    Button {
                        selectedNotification = notification
                        showingSnoozeAlert = true
                    } label: {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color(UIColor.systemGray6))
                            )
                    }
                    .buttonStyle(.plain)
                    
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
        .buttonStyle(NotificationCardButtonStyle())
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
        }
    }
    
    private func pillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.run"
        case .stress: return "heart.fill"
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
