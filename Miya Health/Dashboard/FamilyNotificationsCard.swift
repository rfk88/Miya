import SwiftUI

// MARK: - Family Notifications Card
// Extracted from DashboardNotifications.swift for better compilation performance

struct FamilyNotificationsCard: View {
    let items: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    let onSeeAll: () -> Void
    
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.miyaPrimary)
                    }
                }
            }
            
            VStack(spacing: 10) {
                ForEach(displayedItems) { item in
                    Button {
                        onTap(item)
                    } label: {
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
                                    .frame(width: 52, height: 52)
                                
                                // Icon
                                Image(systemName: pillarIcon(item.pillar))
                                    .font(.system(size: 22, weight: .semibold))
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
                                    .offset(x: 18, y: -18)
                            }
                            
                            // Text content with better spacing and hierarchy
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(DashboardDesign.primaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                                
                                Text(item.body)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(DashboardDesign.secondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                            }
                            
                            Spacer(minLength: 8)
                            
                            // Chevron with subtle styling
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.4))
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
                    .buttonStyle(NotificationCardButtonStyle())
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
