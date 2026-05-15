import SwiftUI

// MARK: - Hexagon

struct ChampionsHexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * (.pi / 3) - .pi / 6
            let x = cx + r * cos(angle)
            let y = cy + r * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

struct ChampionsHexBadge: View {
    let tier: MemberTier
    let size: CGFloat

    var width: CGFloat { size * 0.866 }

    var body: some View {
        LinearGradient(
            colors: tier.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: width, height: size)
        .clipShape(ChampionsHexagonShape())
    }
}

// MARK: - Status pill

struct ChampionsStatusPill: View {
    let status: MemberStatus

    var body: some View {
        switch status {
        case .leading:
            Text("Leading")
                .font(ChampionsTokens.pillText)
                .foregroundColor(ChampionsTokens.teal)
                .padding(.vertical, 3)
                .padding(.horizontal, 9)
                .background(ChampionsTokens.tealSubtle)
                .clipShape(Capsule())
                .modifier(ChampionsPillPulseModifier(color: ChampionsTokens.teal, duration: 2.5))
        case .close:
            Text("Close Race")
                .font(ChampionsTokens.pillText)
                .foregroundColor(ChampionsTokens.amberText)
                .padding(.vertical, 3)
                .padding(.horizontal, 9)
                .background(ChampionsTokens.amberSubtle)
                .clipShape(Capsule())
                .modifier(ChampionsPillPulseModifier(color: ChampionsTokens.amber, duration: 2.0))
        case .trailing:
            EmptyView()
        }
    }
}

// MARK: - Member avatar (URL / initials + white ring)

struct ChampionsMemberAvatar: View {
    let member: ChampionMember
    let size: CGFloat

    var body: some View {
        ZStack {
            #if DEBUG
            if ScreenshotDemoData.isScreenshotModeEnabled {
                Image(ScreenshotDemoData.demoAvatarAssetName(for: member.name))
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                avatarCore
            }
            #else
            avatarCore
            #endif
        }
        .overlay(Circle().strokeBorder(Color.white, lineWidth: ChampionsTokens.avatarBorderWidth))
    }

    @ViewBuilder
    private var avatarCore: some View {
        ProfileAvatarView(
            imageURL: member.avatarURL,
            initials: member.initialsDisplay,
            diameter: size,
            backgroundColor: member.accentColor.opacity(0.25),
            foregroundColor: ChampionsTokens.textPrimary,
            font: .system(size: size * 0.38, weight: .bold),
            showsBorder: false
        )
    }
}

// MARK: - Row chrome helpers

func championsRowBackground(for status: MemberStatus) -> Color {
    switch status {
    case .leading: return ChampionsTokens.tealRow
    case .close: return ChampionsTokens.amberRow
    case .trailing: return .clear
    }
}

func championsLeftBorderColor(for status: MemberStatus) -> Color {
    switch status {
    case .leading: return ChampionsTokens.teal
    case .close: return ChampionsTokens.amber
    case .trailing: return .clear
    }
}
