import SwiftUI

// MARK: - New dashboard top bar (white)

/// Replaces the legacy teal `DashboardTopBar` for the redesigned dashboard.
///
/// Layout: hamburger left, family name centred, bell right with an amber
/// numeric count pill when there are unread bell notifications. The share
/// button has been removed from the dashboard nav bar (sidebar still exposes
/// share).
struct MiyaDashboardTopBar: View {
    let familyName: String
    let notificationCount: Int
    let onMenuTapped: () -> Void
    let onNotificationsTapped: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.miyaCardWhite
                .ignoresSafeArea(edges: [.top])

            HStack(spacing: 0) {
                Button {
                    onMenuTapped()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Menu")

                Spacer()

                Text(familyName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.miyaTextPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onNotificationsTapped()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())

                        if notificationCount > 0 {
                            Text(notificationCount > 99 ? "99+" : "\(notificationCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color.miyaAmber)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.miyaCardWhite, lineWidth: 1.5)
                                )
                                .offset(x: 4, y: 4)
                        }
                    }
                }
                .accessibilityLabel(notificationCount > 0 ? "\(notificationCount) notifications" : "Notifications")
            }
            .padding(.horizontal, 8)

            Rectangle()
                .fill(Color.miyaTextPrimary.opacity(0.08))
                .frame(height: 0.5)
        }
        .frame(height: 56)
    }
}

// MARK: - Floating Chat with Miya button

/// 60pt circular floating action button anchored bottom-trailing of the
/// dashboard. Replaces the in-scroll `ChatWithArloCard` entry point.
struct MiyaChatFAB: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.miyaHeroAccentTeal, .miyaHeroTealStart],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Image(systemName: "message.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.miyaHeroAccentTeal.opacity(0.35), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with Miya")
    }
}

#if DEBUG
#Preview("MiyaDashboardTopBar — no badge") {
    VStack {
        MiyaDashboardTopBar(
            familyName: "The Smiths",
            notificationCount: 0,
            onMenuTapped: {},
            onNotificationsTapped: {}
        )
        Spacer()
    }
    .background(Color.miyaBackground)
}

#Preview("MiyaDashboardTopBar — with count") {
    VStack {
        MiyaDashboardTopBar(
            familyName: "The Smiths",
            notificationCount: 3,
            onMenuTapped: {},
            onNotificationsTapped: {}
        )
        Spacer()
    }
    .background(Color.miyaBackground)
}

#Preview("MiyaChatFAB") {
    ZStack(alignment: .bottomTrailing) {
        Color.miyaBackground
        MiyaChatFAB(onTap: {})
            .padding(20)
    }
}
#endif
