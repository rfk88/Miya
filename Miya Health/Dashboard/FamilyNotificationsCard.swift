import SwiftUI

// MARK: - Family Notifications Card
// Extracted from DashboardNotifications.swift for better compilation performance

struct FamilyNotificationsCard: View {
    let items: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    let onSeeAll: () -> Void
    let onSnooze: (FamilyNotificationItem, Int?) -> Void
    
    @State private var itemToSnooze: FamilyNotificationItem?
    
    private var displayedItems: [FamilyNotificationItem] {
        sortedBySeverity(items).prefix(3).map { $0 }
    }
    
    private var hasMore: Bool {
        items.count > 3
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
    
    private func sortedBySeverity(_ notifications: [FamilyNotificationItem]) -> [FamilyNotificationItem] {
        notifications.sorted { n1, n2 in
            let s1 = getSeverity(n1)
            let s2 = getSeverity(n2)
            
            let priority1 = s1 == .attention ? 3 : (s1 == .watch ? 2 : 1)
            let priority2 = s2 == .attention ? 3 : (s2 == .watch ? 2 : 1)
            
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
                            Text("See all (\(items.count))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    .foregroundColor(.miyaPrimary)
                    }
                }
            }
            
            VStack(spacing: 10) {
                ForEach(displayedItems) { item in
                    notificationRow(item)
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
    private func notificationRow(_ item: FamilyNotificationItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onTap(item)
            } label: {
                notificationCard(item)
            }
            .buttonStyle(.plain)

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

    private func notificationCard(_ item: FamilyNotificationItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                severityColor(item).opacity(0.25),
                                severityColor(item).opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                // Icon
                Image(systemName: pillarIcon(item.pillar))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                severityColor(item),
                                severityColor(item).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                severityBadge(item)
                    .offset(x: 14, y: -14)
            }

            Text(item.displayLine)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DashboardDesign.secondaryTextColor)
                .lineLimit(2)
                .truncationMode(.tail)

            Spacer(minLength: 8)
        }
        .padding(12)
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
                            severityColor(item).opacity(0.2),
                            severityColor(item).opacity(0.1)
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
 
