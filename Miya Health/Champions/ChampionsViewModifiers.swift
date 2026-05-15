import SwiftUI

// MARK: - Shimmer (card idle)

struct ChampionsShimmerModifier: ViewModifier {
    @State private var offset: CGFloat = -1.0

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color(hex: "00B4B4").opacity(0.07), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: geo.size.width * offset)
                .onAppear {
                    withAnimation(
                        .linear(duration: 4.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        offset = 1.5
                    }
                }
            }
            .clipped()
        )
    }
}

// MARK: - Live dot pulse

struct ChampionsLivePulseModifier: ViewModifier {
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .opacity(animating ? 0.3 : 1.0)
            .scaleEffect(animating ? 0.65 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: true)
                ) {
                    animating = true
                }
            }
    }
}

// MARK: - Press scale

struct ChampionsPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Row stagger

struct ChampionsRowStaggerModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(
                    .spring(response: 0.32, dampingFraction: 0.7)
                    .delay(delay)
                ) {
                    appeared = true
                }
            }
    }
}

// MARK: - Badge pop

struct ChampionsBadgePopModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1.0 : 0.3)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.6)
                    .delay(delay)
                ) {
                    appeared = true
                }
            }
    }
}

// MARK: - Pill ring pulse

struct ChampionsPillPulseModifier: ViewModifier {
    let color: Color
    let duration: Double
    @State private var animating = false

    func body(content: Content) -> some View {
        content.background(
            Capsule()
                .stroke(color.opacity(animating ? 0 : 0.4), lineWidth: 1)
                .scaleEffect(animating ? 1.4 : 1.0)
                .opacity(animating ? 0 : 1)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        animating = true
                    }
                }
        )
    }
}

// MARK: - Count-in (season points)

struct ChampionsCountInModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(delay)) {
                    appeared = true
                }
            }
    }
}
