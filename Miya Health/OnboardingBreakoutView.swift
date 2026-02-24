//
//  OnboardingBreakoutView.swift
//  Miya Health
//
//  Educational breakout screens for self-onboarding flow.
//  Card-based UI with hero moments - following Apple Fitness + Stripe patterns.
//  Final polish: vertical centering, scientific credibility, excitement.
//

import SwiftUI

// MARK: - Shared Components

/// Reusable card wrapper for breakout screens
struct OnboardingCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 3)
    }

}


// MARK: - Previews

#if DEBUG

@available(iOS 17.0, *)
#Preview("Breakout 1") {
    NavigationStack {
        Breakout1View()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

@available(iOS 17.0, *)
#Preview("Breakout 2") {
    NavigationStack {
        Breakout2View()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

@available(iOS 17.0, *)
#Preview("Breakout 3") {
    NavigationStack {
        Breakout3View()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

struct OnboardingBreakoutView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                Breakout1View()
                    .environmentObject(OnboardingManager())
                    .environmentObject(DataManager())
            }
            .previewDisplayName("Breakout 1")

            NavigationView {
                Breakout2View()
                    .environmentObject(OnboardingManager())
                    .environmentObject(DataManager())
            }
            .previewDisplayName("Breakout 2")

            NavigationView {
                Breakout3View()
                    .environmentObject(OnboardingManager())
                    .environmentObject(DataManager())
            }
            .previewDisplayName("Breakout 3")
        }
    }
}

#endif

/// Consistent top section for all breakouts
struct BreakoutTopSection: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.miyaTextPrimary)
            
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Breakout 1: What Is Miya's Vitality Score?

struct Breakout1View: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    @State private var navigateToNext: Bool = false
    @State private var animatedProgress: Double = 0.0
    @State private var displayedScore: Int = 0
    @State private var showLabels: Bool = false
    @State private var showCaption: Bool = false
    @State private var showScienceCard: Bool = false
    @State private var showButton: Bool = false
    
    private let targetScore: Int = 75
    private let targetProgress: Double = 0.75
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // VERTICAL CENTERING: Push content down
                    Spacer()
                        .frame(minHeight: 60)
                    
                    // Top section (fixed)
                    BreakoutTopSection(
                        title: "What Is Miya's Vitality Score?",
                        subtitle: "A simple signal built from validated health science."
                    )
                    
                    // HERO CARD: Horizontal vitality line (NO DOT)
                    OnboardingCard(padding: 24) {
                        VStack(spacing: 24) {
                            // Score display above line
                            Text("\(displayedScore)")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            // Horizontal vitality line
                            VStack(spacing: 16) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        // Background line (full width)
                                        Capsule()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 8)
                                        
                                        // Active line (animated width with gradient) - NO DOT
                                        Capsule()
                                            .fill(LinearGradient(
                                                colors: [
                                                    .miyaTeal,
                                                    Color(red: 0.15, green: 0.55, blue: 1.0),
                                                    Color(red: 0.5, green: 0.3, blue: 1.0)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ))
                                            .frame(width: geo.size.width * animatedProgress, height: 8)
                                    }
                                }
                                .frame(height: 8)
                                
                                // Labels (baseline, improving, thriving)
                                if showLabels {
                                    HStack {
                                        Text("Baseline")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.miyaTextSecondary.opacity(0.6))
                                        
                                        Spacer()
                                        
                                        Text("Improving")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.miyaTextSecondary.opacity(0.6))
                                        
                                        Spacer()
                                        
                                        Text("Thriving")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.miyaTextSecondary.opacity(0.6))
                                    }
                                    .transition(.opacity)
                                }
                                
                                // CREDIBILITY CAPTION
                                if showCaption {
                                    Text("Built from long-term patterns, not single readings")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.miyaTextSecondary.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity)
                                }
                            }
                        }
                    }
                    
                    // SUPPORTING CARD: How it's calculated
                    if showScienceCard {
                        OnboardingCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("How it's calculated")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("The Vitality Score combines lifestyle data, heart health indicators, and family risk factors using established cardiovascular and population-health models. It focuses on patterns over time — not single readings.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer()
                        .frame(minHeight: 40)
                    
                    // CTA Button (pinned)
                    if showButton {
                        Button {
                            navigateToNext = true
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.miyaBackground)
            
            // Hidden NavigationLink
            NavigationLink(
                destination: HeartHealthView()
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager),
                isActive: $navigateToNext
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // 0.3s: Start line animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = targetProgress
            }
        }
        
        // 0.8s: Score counts up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            animateScoreCountUp()
        }
        
        // 1.5s: Labels fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                showLabels = true
            }
        }
        
        // 1.8s: Caption fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                showCaption = true
            }
        }
        
        // 2.0s: Science card fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showScienceCard = true
            }
        }
        
        // 2.5s: Button appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.35)) {
                showButton = true
            }
        }
    }
    
    private func animateScoreCountUp() {
        let steps = 20
        let interval = 0.05
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * interval)) {
                displayedScore = Int(Double(targetScore) * (Double(i) / Double(steps)))
            }
        }
    }
}

// MARK: - Breakout 2: Why Miya Exists

struct Breakout2View: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    @State private var navigateToNext: Bool = false
    @State private var backgroundDarkness: Double = 0.0
    @State private var iconOpacity: Double = 1.0
    @State private var showStatementCard: Bool = false
    @State private var showMissionCard: Bool = false
    @State private var showButton: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // VERTICAL CENTERING: Push content down
                    Spacer()
                        .frame(minHeight: 44)
                    
                    // Top section (fixed)
                    BreakoutTopSection(
                        title: "Why Miya Exists",
                        subtitle: "Because health changes quietly, long before it becomes urgent."
                    )
                    
                    // HERO CARD: 4 PEOPLE with colored fills + icons
                    OnboardingCard(padding: 20) {
                        ZStack {
                            // Subtle background shift
                            Color.white
                                .overlay(
                                    Color.black.opacity(backgroundDarkness * 0.03)
                                )
                            
                            VStack(spacing: 20) {
                                // 4 Family silhouettes with colors
                                HStack(spacing: 16) {
                                    // Person 1: Blue
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue.opacity(0.6))
                                    
                                    // Person 2: Green
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.green.opacity(0.6))
                                    
                                    // Person 3: Purple
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.purple.opacity(0.6))
                                    
                                    // Person 4: Teal/Yellow
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.teal.opacity(0.6))
                                }
                                
                                // Health domain icons below people
                                HStack(spacing: 16) {
                                    // Heart (blue)
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue.opacity(0.8))
                                        .opacity(iconOpacity)
                                        .frame(width: 40)
                                    
                                    // Bolt/Energy (green)
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green.opacity(0.8))
                                        .opacity(iconOpacity)
                                        .frame(width: 40)
                                    
                                    // Moon/Sleep (purple)
                                    Image(systemName: "moon.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.purple.opacity(0.8))
                                        .opacity(iconOpacity)
                                        .frame(width: 40)
                                    
                                    // Brain/Mindfulness (teal)
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 14))
                                        .foregroundColor(.teal.opacity(0.8))
                                        .opacity(iconOpacity)
                                        .frame(width: 40)
                                }
                            }
                            .padding(.vertical, 18)
                        }
                        .frame(height: 140)
                        .cornerRadius(16)
                    }
                    
                    // COMBINED CARD: Statement + WHO Quote
                    if showStatementCard {
                        OnboardingCard {
                            VStack(alignment: .leading, spacing: 20) {
                                // Statement section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Most health problems don't start suddenly.")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("They build quietly over time.")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                // Divider (visual separator)
                                Divider()
                                    .padding(.vertical, 4)

                                // WHO Quote section
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\"Chronic diseases develop over long periods of time and are influenced by accumulated behaviours and exposures.\"")
                                        .font(.system(size: 15, weight: .regular))
                                        .italic()
                                        .foregroundColor(.miyaTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("— World Health Organization")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.miyaTextSecondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // TEXT CARD 2: Mission (NO DISCLAIMER)
                    if showMissionCard {
                        OnboardingCard {
                            Text("Miya exists to help families notice change earlier, create accountability, and act before small issues become bigger ones.")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer()
                        .frame(minHeight: 16)
                    
                    // CTA Button (pinned)
                    if showButton {
                        Button {
                            navigateToNext = true
                        } label: {
                            Text("See my results")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.miyaBackground)
            
            // Hidden NavigationLink
            NavigationLink(
                destination: Breakout3View()
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager),
                isActive: $navigateToNext
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startDriftAnimation()
        }
    }
    
    private func startDriftAnimation() {
        // 0-2s: Background darkens within card
        withAnimation(.easeInOut(duration: 2.0)) {
            backgroundDarkness = 1.0
        }
        
        // 0.8s: Statement + WHO quote card fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showStatementCard = true
            }
        }
        
        // 2-4s: Icons fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 2.0)) {
                iconOpacity = 0.6
            }
        }
        
        // 2.5s: Mission card fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showMissionCard = true
            }
        }
        
        // 4.5s: Button appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeInOut(duration: 0.35)) {
                showButton = true
            }
        }
    }
}

// MARK: - Breakout 3: How Miya Works (EXCITING!)

struct Breakout3View: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    
    @State private var navigateToNext: Bool = false
    @State private var currentStage: Int = 0 // 0 = none, 1-3 = stages
    @State private var waveProgress: Double = 0.0 // For wave animation
    @State private var showExplanationCard: Bool = false
    @State private var showContrastCard: Bool = false
    @State private var showButton: Bool = false
    
    private var isGuidedInviteeAwaitingAdmin: Bool {
        onboardingManager.isInvitedUser && onboardingManager.guidedSetupStatus == .acceptedAwaitingData
    }
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // VERTICAL CENTERING: Push content down
                    Spacer()
                        .frame(minHeight: 60)
                    
                    // Top section (fixed)
                    BreakoutTopSection(
                        title: "How Miya Works",
                        subtitle: "Calm, not reactive."
                    )
                    
                    // HERO CARD: 3-stage flow with WAVE ANIMATION
                    OnboardingCard(padding: 20) {
                        VStack(spacing: 16) {
                            HStack(spacing: 0) {
                                // Stage 1: Observe
                                FlowStageWave(
                                    icon: "magnifyingglass",
                                    title: "Observe",
                                    subtitle: "patterns",
                                    isActive: currentStage == 1,
                                    waveIntensity: currentStage == 1 ? waveProgress : 0
                                )
                                
                                // Connecting wave line
                                WaveConnector(isActive: currentStage >= 2, progress: waveProgress)
                                
                                // Stage 2: Notice
                                FlowStageWave(
                                    icon: "bell.fill",
                                    title: "Notice",
                                    subtitle: "drift",
                                    isActive: currentStage == 2,
                                    waveIntensity: currentStage == 2 ? waveProgress : 0
                                )
                                
                                // Connecting wave line
                                WaveConnector(isActive: currentStage >= 3, progress: waveProgress)
                                
                                // Stage 3: Support
                                FlowStageWave(
                                    icon: "hands.sparkles.fill",
                                    title: "Support",
                                    subtitle: "action",
                                    isActive: currentStage == 3,
                                    waveIntensity: currentStage == 3 ? waveProgress : 0
                                )
                            }
                        }
                        .frame(height: 140)
                    }
                    
                    // EXPLANATION CARD: What the system does
                    if showExplanationCard {
                        OnboardingCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("A system that quietly learns, then intervenes only when it matters.")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.miyaTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Text("Miya watches for meaningful change over time. When something drifts, it helps the right person act — calmly.")
                                    .font(.system(size: 15))
                                    .foregroundColor(.miyaTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // CONTRAST CARD: Designed to support, not overwhelm (two-column)
                    if showContrastCard {
                        OnboardingCard(padding: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Designed to support — not overwhelm")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack(alignment: .top, spacing: 20) {
                                    // Left column: What we DON'T do (muted)
                                    VStack(alignment: .leading, spacing: 10) {
                                        ContrastItem(text: "Panic alerts", isPositive: false)
                                        ContrastItem(text: "Daily nagging", isPositive: false)
                                        ContrastItem(text: "One-off readings", isPositive: false)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    // Right column: What we DO (accent)
                                    VStack(alignment: .leading, spacing: 10) {
                                        ContrastItem(text: "Calm signals", isPositive: true)
                                        ContrastItem(text: "Thoughtful nudges", isPositive: true)
                                        ContrastItem(text: "Long-term patterns", isPositive: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer()
                        .frame(minHeight: 40)
                    
                    // CTA Button (pinned)
                    if showButton {
                        Button {
                            navigateToNext = true
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.miyaBackground)
            
            // Hidden NavigationLink
            NavigationLink(
                destination: breakout3Destination,
                isActive: $navigateToNext
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startFlowAnimation()
        }
    }
    
    @ViewBuilder
    private var breakout3Destination: some View {
        if isGuidedInviteeAwaitingAdmin {
            OnboardingCompleteView(membersCount: 0)
                .environmentObject(onboardingManager)
                .environmentObject(dataManager)
        } else if onboardingManager.isInvitedUser {
            AlertsChampionView()
                .environmentObject(onboardingManager)
                .environmentObject(dataManager)
        } else {
            FamilyMembersInviteView()
                .environmentObject(onboardingManager)
                .environmentObject(dataManager)
        }
    }
    
    private func startFlowAnimation() {
        // Stage 1: Observe (0.3-1.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStage = 1
            }
            // Wave pulse
            withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                waveProgress = 1.0
            }
        }
        
        // Stage 2: Notice (1.8-3.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            waveProgress = 0.0
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStage = 2
            }
            withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                waveProgress = 1.0
            }
        }
        
        // Stage 3: Support (3.3-4.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            waveProgress = 0.0
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStage = 3
            }
            withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                waveProgress = 1.0
            }
        }
        
        // Loop back to Stage 1 (5.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            waveProgress = 0.0
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStage = 1
            }
            // Continue looping
            loopAnimation()
        }
        
        // Show explanation card (2.0s - appears while animation runs)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showExplanationCard = true
            }
        }
        
        // Show contrast card (2.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showContrastCard = true
            }
        }
        
        // Show button (5.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            withAnimation(.easeInOut(duration: 0.35)) {
                showButton = true
            }
        }
    }
    
    private func loopAnimation() {
        // Subtle continuous loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStage = currentStage == 3 ? 1 : currentStage + 1
            }
            loopAnimation()
        }
    }
}

// MARK: - Flow Stage Component with Wave

struct FlowStageWave: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let waveIntensity: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon with glow and scale when active
            ZStack {
                // Glow effect (wave pulse)
                if isActive {
                    Circle()
                        .fill(Color.miyaPrimary.opacity(0.2 * waveIntensity))
                        .frame(width: 50, height: 50)
                        .scaleEffect(1.0 + (0.4 * waveIntensity))
                }
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .miyaPrimary : .miyaTextSecondary.opacity(0.5))
                    .scaleEffect(isActive ? (1.1 + (0.1 * waveIntensity)) : 1.0)
            }
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .miyaTextPrimary : .miyaTextSecondary.opacity(0.7))
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.miyaTextSecondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Wave Connector Component

struct WaveConnector: View {
    let isActive: Bool
    let progress: Double
    
    var body: some View {
        Rectangle()
            .fill(isActive ? Color.miyaPrimary.opacity(0.3 + (0.4 * progress)) : Color.gray.opacity(0.15))
            .frame(width: 2)
            .padding(.vertical, 30)
    }
}

// MARK: - Contrast Item Component

struct ContrastItem: View {
    let text: String
    let isPositive: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(isPositive ? "✓" : "✗")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isPositive ? .miyaPrimary : .miyaTextSecondary.opacity(0.5))
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(isPositive ? .miyaTextPrimary : .miyaTextSecondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
