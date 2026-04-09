//
//  FamilyIntroView.swift
//  Miya Health
//
//  First-launch value proposition screen. Shown once before account creation.
//  Uses a clip-mask split animation to visually illustrate a family health event,
//  then presents the Miya mission copy before handing off to AuthEntryScreen.
//

import SwiftUI

// MARK: - Top-level entry point

struct FamilyIntroView: View {
    /// Called when the user taps "Get Started". Parent writes the seen-flag and swaps routing.
    let onFinish: () -> Void

    // Figure appearance
    @State private var figureOpacity: [Double] = [0, 0, 0, 0]
    @State private var figureOffset: [Double] = [20, 20, 20, 20]

    // Breaking figure (index 1)
    @State private var breakColor: Color = .miyaTextSecondary.opacity(0.5)
    @State private var isBroken: Bool = false
    @State private var othersOpacity: Double = 1.0

    // Copy blocks
    @State private var showLine1: Bool = false
    @State private var showLine2: Bool = false
    @State private var showLine3: Bool = false

    // CTA
    @State private var showButton: Bool = false

    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Family figures hero
                    ZStack {
                        HStack(spacing: 28) {
                            // Figure 0
                            FamilyFigure(
                                color: .miyaTeal.opacity(0.7),
                                opacity: figureOpacity[0],
                                offsetY: figureOffset[0],
                                dimmed: othersOpacity < 1
                            )

                            // Figure 1 — the one that breaks
                            SplitPersonIcon(
                                normalColor: breakColor,
                                isBroken: isBroken,
                                opacity: figureOpacity[1],
                                offsetY: figureOffset[1]
                            )

                            // Figure 2
                            FamilyFigure(
                                color: Color(red: 0.4, green: 0.55, blue: 1.0).opacity(0.7),
                                opacity: figureOpacity[2],
                                offsetY: figureOffset[2],
                                dimmed: othersOpacity < 1
                            )

                            // Figure 3
                            FamilyFigure(
                                color: Color(red: 0.55, green: 0.35, blue: 0.9).opacity(0.7),
                                opacity: figureOpacity[3],
                                offsetY: figureOffset[3],
                                dimmed: othersOpacity < 1
                            )
                        }
                        .frame(height: 120)
                    }
                    .padding(.bottom, 40)

                    // Copy block
                    VStack(alignment: .leading, spacing: 20) {
                        if showLine1 {
                            Text("Know when something's not right.")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        if showLine2 {
                            Text("Miya exists to help families maintain their health and prevent this from happening in the first place.")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        if showLine3 {
                            Text("Miya connects family members together and uses the strong family bonds you already have to hold each other accountable.")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                    Spacer().frame(height: 40)

                    // CTA
                    if showButton {
                        Button {
                            onFinish()
                        } label: {
                            Text("Get Started")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .kerning(-0.2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.miyaPrimary)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .onAppear { runAnimation() }
    }

    // MARK: - Animation timeline

    private func runAnimation() {
        // Figures appear one by one
        for i in 0..<4 {
            let delay = 0.2 + Double(i) * 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.45)) {
                    figureOpacity[i] = 1.0
                    figureOffset[i] = 0
                }
            }
        }

        // Figure 1 shifts to warning red (1.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.8)) {
                breakColor = Color(red: 0.85, green: 0.2, blue: 0.2).opacity(0.85)
            }
        }

        // Figure 1 splits apart (2.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                isBroken = true
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                othersOpacity = 0.45
            }
        }

        // Line 1 (3.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showLine1 = true
            }
        }

        // Line 2 (4.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showLine2 = true
            }
        }

        // Line 3 (5.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showLine3 = true
            }
        }

        // Button (6.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
            withAnimation(.easeInOut(duration: 0.45)) {
                showButton = true
            }
        }
    }
}

// MARK: - SplitPersonIcon

/// Renders a person.fill icon as two independently animated halves.
/// When `isBroken` is false the halves are perfectly overlaid (looks normal).
/// When `isBroken` is true the halves drift apart with slight rotation.
struct SplitPersonIcon: View {
    let normalColor: Color
    let isBroken: Bool
    let opacity: Double
    let offsetY: Double

    private let iconSize: CGFloat = 48

    var body: some View {
        ZStack {
            // Top half
            Image(systemName: "person.fill")
                .font(.system(size: iconSize))
                .foregroundColor(normalColor)
                .clipShape(TopHalfShape())
                .offset(
                    x: isBroken ? -4 : 0,
                    y: isBroken ? -14 : 0
                )
                .rotationEffect(.degrees(isBroken ? -12 : 0), anchor: .bottom)

            // Bottom half
            Image(systemName: "person.fill")
                .font(.system(size: iconSize))
                .foregroundColor(normalColor)
                .clipShape(BottomHalfShape())
                .offset(
                    x: isBroken ? 4 : 0,
                    y: isBroken ? 14 : 0
                )
                .rotationEffect(.degrees(isBroken ? 10 : 0), anchor: .top)
        }
        .opacity(opacity)
        .offset(y: offsetY)
    }
}

// MARK: - Clip shapes

struct TopHalfShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
    }
}

struct BottomHalfShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
    }
}

// MARK: - FamilyFigure

/// One of the non-breaking family members.
struct FamilyFigure: View {
    let color: Color
    let opacity: Double
    let offsetY: Double
    let dimmed: Bool

    var body: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 48))
            .foregroundColor(color)
            .opacity(opacity * (dimmed ? 0.45 : 1.0))
            .offset(y: offsetY)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Family Intro") {
    FamilyIntroView(onFinish: {})
}
#endif
