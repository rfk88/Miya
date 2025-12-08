import SwiftUI
import UIKit

// MARK: - VITALITY MODEL

// A single family member’s score for a specific vitality factor
struct FamilyMemberScore: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let score: Int       // 0–100
}

// A single vitality factor in the dashboard (Sleep, Activity, Stress, Mindfulness)
struct VitalityFactor: Identifiable {
    let id = UUID()
    let name: String              // e.g. "Sleep"
    let iconName: String          // SF Symbol name
    let percent: Int              // Family-wide average 0–100
    let description: String       // Explanation text
    let actionPlan: [String]      // List of recommended actions
    let memberScores: [FamilyMemberScore]  // Individual scores for each family member
}
// MARK: - SLEEP CHALLENGE UI MODEL

struct SleepChallengeUIModel: Identifiable {
    struct Participant: Identifiable {
        let id = UUID()
        let name: String
        let nightlyHits: [Bool]   // length = totalDays

        var totalHits: Int {
            nightlyHits.filter { $0 }.count
        }
    }

    let id = UUID()
    let title: String
    let totalDays: Int          // 7 / 14 / 21 / 28
    let currentDay: Int         // 1-based, e.g. 5 means day 5 of 14
    let participants: [Participant]

    var totalWeeks: Int {
        Int(ceil(Double(totalDays) / 7.0))
    }
}

// MARK: - ACTIVE CHALLENGE (for Mission Hub)

enum ActiveChallengeUI {
    case hydration(HydrationChallengeUIModel)
    // later: case sleep(SleepChallengeUIModel)
}
// MARK: - TOP BAR

struct DashboardTopBar: View {
    let familyName: String
    let onShareTapped: () -> Void
    let onMenuTapped: () -> Void
    let onNotificationsTapped: () -> Void

    var body: some View {
        ZStack {
            Color.miyaEmerald
                .ignoresSafeArea(edges: .top)

            HStack {
                // LEFT — Burger menu
                Button {
                    onMenuTapped()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                }

                Spacer()

                // RIGHT — Share + Notifications
                HStack(spacing: 16) {
                    Button {
                        onShareTapped()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                    }

                    Button {
                        onNotificationsTapped()
                    } label: {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .padding(.horizontal, 16)
            .foregroundColor(.white)

            Text("\(familyName) Family")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(height: 52)
    }
}

// MARK: - DASHBOARD VIEW

struct DashboardView: View {
    let familyName: String
    
    @State private var isArloExpanded: Bool = false
    @State private var selectedFactor: VitalityFactor? = nil
    
    // Burger + share state
    @State private var showSidebar: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var shareText: String = ""
    
    // Notifications overlay state
    @State private var showNotifications: Bool = false
    
    // 👇 NEW: challenge sheet state
    @State private var isPresentingChallengeSheet: Bool = false
    
    // Active challenges in Mission Hub
    @State private var activeSleepChallenge: SleepChallengeUIModel? = nil
    @State private var activeStepsChallenge: StepsChallengeUIModel? = nil
    @State private var activeHydrationChallenge: HydrationChallengeUIModel? = nil
    @State private var activeMovementChallenge: MovementChallengeUIModel? = nil
    @State private var activeMeditationChallenge: MeditationChallengeUIModel? = nil
    @State private var activeNutritionChallenge: NutritionChallengeUIModel? = nil
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // TOP BAR
                DashboardTopBar(
                    familyName: familyName,
                    onShareTapped: {
                        // 1) Build the share text
                        prepareShareText()
                        // 2) Show the native share sheet
                        isShareSheetPresented = true
                    },
                    onMenuTapped: {
                        // Open sidebar
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSidebar = true
                        }
                    },
                    onNotificationsTapped: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showNotifications.toggle()
                        }
                    }
                )
                
                // MAIN SCROLL CONTENT
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Family members strip (avatars with vitality rings + nav to ProfileView)
                        FamilyMembersStrip(members: DashboardMockData.familyMembers)
                            .padding(.top, 12)

                        // Chat with Arlo card
                        ChatWithArloCard(isExpanded: $isArloExpanded)

                        // Family vitality card
                        FamilyVitalityCard(
                            score: 78,
                            label: "Good week",
                            factors: DashboardMockData.vitalityFactors
                        ) { tappedFactor in
                            selectedFactor = tappedFactor
                        }

                        // ✅ Single, correct Mission Hub card
                        MissionHubCard(
                            isPresentingChallengeSheet: $isPresentingChallengeSheet,
                            activeSleepChallenge: activeSleepChallenge,
                            activeStepsChallenge: activeStepsChallenge,
                            activeHydrationChallenge: activeHydrationChallenge,
                            activeMovementChallenge: activeMovementChallenge,
                            activeMeditationChallenge: activeMeditationChallenge,
                            activeNutritionChallenge: activeNutritionChallenge
                        )

                        Spacer(minLength: 16)
                    }
                    .padding(EdgeInsets(
                        top: 8,
                        leading: 16,
                        bottom: 24,
                        trailing: 16
                    ))
                }
            }
            
            // NOTIFICATIONS OVERLAY
            if showNotifications {
                // Dim background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showNotifications = false
                        }
                    }
                
                // Notification panel
                NotificationsPanel(onClose: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        showNotifications = false
                    }
                })
                .transition(
                    SwiftUI.AnyTransition
                        .move(edge: SwiftUI.Edge.top)
                        .combined(with: SwiftUI.AnyTransition.opacity)
                )
                .zIndex(2)
            }
            
            // SIDEBAR OVERLAY + MENU
            if showSidebar {
                ZStack {
                    // darkened background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSidebar = false
                            }
                        }
                    
                    // Sidebar pinned to the LEFT
                    SidebarMenu(isVisible: $showSidebar)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .leading))
                }
                .zIndex(1)
            }
        } // 👈 END OF ZSTACK

        // Attach sheets to the whole dashboard view
        .sheet(item: $selectedFactor) { factor in
            VitalityFactorDetailSheet(factor: factor)
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ActivityView(activityItems: [shareText])
        }
        .sheet(isPresented: $isPresentingChallengeSheet) {
            ChallengeTypeSelector(
                onSleepChallengeCreated: { model in
                    activeSleepChallenge = model
                    activeStepsChallenge = nil
                    activeHydrationChallenge = nil
                    activeMovementChallenge = nil
                    activeMeditationChallenge = nil
                    activeNutritionChallenge = nil
                },
                onStepsChallengeCreated: { model in
                    activeStepsChallenge = model
                    activeSleepChallenge = nil
                    activeHydrationChallenge = nil
                    activeMovementChallenge = nil
                    activeMeditationChallenge = nil
                    activeNutritionChallenge = nil
                },
                onHydrationChallengeCreated: { model in
                    activeHydrationChallenge = model
                    activeSleepChallenge = nil
                    activeStepsChallenge = nil
                    activeMovementChallenge = nil
                    activeMeditationChallenge = nil
                    activeNutritionChallenge = nil
                },
                onMovementChallengeCreated: { model in
                    activeMovementChallenge = model
                    activeSleepChallenge = nil
                    activeStepsChallenge = nil
                    activeHydrationChallenge = nil
                    activeMeditationChallenge = nil
                    activeNutritionChallenge = nil
                },
                onMeditationChallengeCreated: { model in
                    activeMeditationChallenge = model
                    activeSleepChallenge = nil
                    activeStepsChallenge = nil
                    activeHydrationChallenge = nil
                    activeMovementChallenge = nil
                    activeNutritionChallenge = nil
                },
                onNutritionChallengeCreated: { model in
                    activeNutritionChallenge = model
                    activeSleepChallenge = nil
                    activeStepsChallenge = nil
                    activeHydrationChallenge = nil
                    activeMovementChallenge = nil
                    activeMeditationChallenge = nil
                }
            )
        }
    } // 👈 END OF `var body: some View`
    // MARK: - Share text builder

    private func prepareShareText() {
        let vitality = DashboardMockData.vitalityFactors

        let sleep = vitality.first(where: { $0.name == "Sleep" })?.percent ?? 0
        let activity = vitality.first(where: { $0.name == "Activity" })?.percent ?? 0
        let stress = vitality.first(where: { $0.name == "Stress" })?.percent ?? 0
        let mindfulness = vitality.first(where: { $0.name == "Mindfulness" })?.percent ?? 0

        shareText = """
        Our Family Vitality Score this week: 78/100 💚

        Sleep: \(sleep)
        Activity: \(activity)
        Stress: \(stress)
        Mindfulness: \(mindfulness)

        One family. One mission.
        Shared from Miya Health.
        """
    }
    }

// MARK: - FAMILY MEMBERS STRIP

struct FamilyMembersStrip: View {
    let members: [FamilyMemberScore]

    private func profileConfig(for name: String) -> (score: Int, delta: Int, label: String) {
            switch name {
            case "Josh": return (78, 2, "Good")
            case "Mum":  return (72, 3, "Good")
            case "Dad":  return (65, -1, "Okay")
            case "Ann":  return (80, 4, "Great")
            default:     return (75, 0, "Good")
            }
        }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(members) { member in
                    let progress = CGFloat(member.score) / 100.0
                    let config = profileConfig(for: member.name)

                    NavigationLink {
                        ProfileView(
                            memberName: member.name,
                            vitalityScore: config.score,
                            vitalityTrendDelta: config.delta,
                            vitalityLabel: config.label
                        )
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                // Background circle
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: Color.black.opacity(0.05),
                                            radius: 6, x: 0, y: 3)

                                // Vitality ring
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(
                                        AngularGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.2, green: 0.8, blue: 0.75),
                                                Color(red: 0.15, green: 0.55, blue: 1.0),
                                                Color(red: 0.5, green: 0.3, blue: 1.0)
                                            ]),
                                            center: .center
                                        ),
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 64, height: 64)

                                // Inner avatar
                                Circle()
                                    .fill(Color.miyaBackground)
                                    .frame(width: 48, height: 48)

                                Text(member.initials)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                            }

                            // Name under avatar
                            Text(member.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.miyaTextPrimary)
                        }
                    }
                    .buttonStyle(.plain)   // 👈 MUST BE HERE
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
    // MARK: - CHAT WITH ARLO CARD
    
    struct ChatWithArloCard: View {
        @Binding var isExpanded: Bool
        
        @State private var isLoadingResponse: Bool = false
        @State private var hasLoadedResponse: Bool = false
        
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.miyaPrimary.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "bolt.heart")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.miyaPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat with Arlo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        Text("Your AI health coach")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(16)
                
                if isExpanded {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if isLoadingResponse {
                            // ⏳ Loading state (2s “thinking”)
                            HStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Arlo is looking at your family’s week…")
                                    .font(.system(size: 13))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            // ✅ Loaded response
                            Text("“Here’s what I’m seeing: hydration and sleep are the biggest levers for your family this week. Want a 3-step plan?”")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button {
                                print("Open full chat with Arlo")
                                // later: navigate to full chat screen
                            } label: {
                                Text("Open chat")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color.miyaPrimary)
                                    .foregroundColor(.white)
                                    .cornerRadius(999)
                            }
                        }
                    }
                    .padding(16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                
                if isExpanded {
                    startLoadingIfNeeded()
                } else {
                    // collapse → reset for next time if you want
                    isLoadingResponse = false
                    // hasLoadedResponse = false // uncomment if you want it to reload every time
                }
            }
        }
        
        // MARK: - Loading simulation
        
        private func startLoadingIfNeeded() {
            // Only simulate once; if you want it EVERY time, remove this guard
            guard !hasLoadedResponse else { return }
            
            isLoadingResponse = true
            hasLoadedResponse = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Only show if it’s still expanded
                if isExpanded {
                    withAnimation(.easeInOut) {
                        isLoadingResponse = false
                        hasLoadedResponse = true
                    }
                }
            }
        }
    }
    
// MARK: - FAMILY VITALITY CARD

struct FamilyVitalityCard: View {
    let score: Int
    let label: String
    let factors: [VitalityFactor]
    let onFactorTapped: (VitalityFactor) -> Void

    @State private var isExpanded: Bool = false   // collapsed by default

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            Text("Family vitality")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
                .padding(.top, 12)

            // Oura-style semicircle gauge (same visual language as profile)
            VStack(spacing: 8) {
                FamilySemiCircleGauge(
                    score: score,
                    label: label
                )

            }
            .frame(maxWidth: .infinity)

            Divider()

            // Expandable header
            HStack {
                Text("What’s affecting vitality?")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // EXPANDED LIST
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(factors) { factor in
                        Button {
                            onFactorTapped(factor)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: factor.iconName)
                                    .font(.system(size: 16))
                                    .frame(width: 24, height: 24)

                                Text(factor.name)
                                    .font(.system(size: 13))

                                Spacer()

                                // SOLID TRAFFIC BAR
                                solidTrafficBar(for: factor.percent)

                                Text("\(factor.percent)%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}
        // MARK: - Family semicircle vitality gauge

        struct FamilySemiCircleGauge: View {
            let score: Int        // e.g. 78
            let label: String     // e.g. "Good week"

            private var progress: Double {
                max(0, min(Double(score) / 100.0, 1.0))
            }

            var body: some View {
                VStack(spacing: -24) {

                    // Oura-style arc + centre heart
                    ZStack {
                        // Background arc (full semicircle)
                        ArcShape(progress: 1.0)
                            .stroke(
                                Color(.systemGray5),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )

                        // Active gradient arc
                        ArcShape(progress: progress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.8, blue: 0.75),
                                        Color(red: 0.15, green: 0.55, blue: 1.0),
                                        Color(red: 0.5, green: 0.3, blue: 1.0)
                                    ]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 15, lineCap: .round)
                            )

                        // Centre heart icon
                        Circle()
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                            .overlay(
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.miyaPrimary)
                            )
                            .offset(y: -18)   // moves it up into the arc
                    }
                    .frame(height: 110)

                    // Text stack under the arc
                    VStack(spacing: 2) {
                        Text("Family vitality")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)

                        Text("\(score)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)

                        Text(label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.top, -4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        // MARK: - Traffic Light Helpers
        
        private func statusBand(for percent: Int) -> Int {
            switch percent {
            case ..<40: return 0
            case 40..<70: return 1
            default: return 2
            }
        }
        
        private func bandColor(for index: Int) -> Color {
            [Color.red, .yellow, .green][index]
        }
        
        private func solidTrafficBar(for percent: Int) -> some View {
            let band = statusBand(for: percent)
            
            return RoundedRectangle(cornerRadius: 3)
                .fill(bandColor(for: band))
                .frame(width: 52, height: 6)
        }
    
    // MARK: - VITALITY FACTOR DETAIL SHEET
    
    struct VitalityFactorDetailSheet: View {
        @Environment(\.dismiss) private var dismiss
        
        let factor: VitalityFactor
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Title row (icon + name)
                        HStack(spacing: 8) {
                            Image(systemName: factor.iconName)
                                .font(.system(size: 20))
                            Text(factor.name)
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundColor(.miyaTextPrimary)
                        
                        // Description
                        Text(factor.description)
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Action plan
                        Text("Action plan")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(factor.actionPlan, id: \.self) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                    Text(step)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 14))
                                .foregroundColor(.miyaTextSecondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Family breakdown (traffic-light bars)
                        if !factor.memberScores.isEmpty {
                            Text("Family \(factor.name.lowercased()) scores")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                                .padding(.top, 8)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(factor.memberScores) { member in
                                    HStack(spacing: 12) {
                                        // Avatar
                                        Circle()
                                            .fill(Color.miyaBackground)
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Text(member.initials)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.miyaTextPrimary)
                                            )
                                        
                                        // Name + coloured bar
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(member.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.miyaTextPrimary)
                                            
                                            ProgressView(value: Double(member.score), total: 100)
                                                .progressViewStyle(.linear)
                                                .tint(trafficColor(for: member.score))   // 🔴🟡🟢
                                        }
                                        
                                        Spacer()
                                        
                                        // Score number
                                        Text("\(member.score)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.miyaTextPrimary)
                                    }
                                }
                            }
                        }
                        
                        Spacer(minLength: 12)
                    }
                    .padding(20)
                }
                .navigationTitle(factor.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        
        // MARK: - Traffic-light colour helper
        
        private func trafficColor(for score: Int) -> Color {
            switch score {
            case ..<40:
                // soft red
                return Color.red.opacity(0.85)
            case 40..<70:
                // soft amber
                return Color.yellow.opacity(0.9)
            default:
                // soft green
                return Color.green.opacity(0.9)
            }
        }
    }
    // MARK: - DASHBOARD MOCK DATA (TEMP)
    
    struct DashboardMockData {
        
        static let familyMembers: [FamilyMemberScore] = [
            FamilyMemberScore(name: "Josh", initials: "JK", score: 82),
            FamilyMemberScore(name: "Mum",  initials: "MM", score: 76),
            FamilyMemberScore(name: "Dad",  initials: "DD", score: 71),
            FamilyMemberScore(name: "Ann",  initials: "AN", score: 85)
        ]
        
        static let vitalityFactors: [VitalityFactor] = [
            // Each percent here = family-wide average for that pillar
            
            VitalityFactor(
                name: "Sleep",
                iconName: "bed.double.fill",
                percent: 72,
                description: "On average your family is getting a decent amount of sleep, with a couple of choppy nights pulling the score down a little.",
                actionPlan: [
                    "Pick 1–2 ‘non negotiable’ bedtimes for the family this week.",
                    "Create a 20–30 minute wind-down routine (dim lights, no phones in bed).",
                    "Celebrate any streak of 3+ good nights together."
                ],
                memberScores: [
                    FamilyMemberScore(name: "Josh", initials: "JK", score: 75),
                    FamilyMemberScore(name: "Mum",  initials: "MM", score: 80),
                    FamilyMemberScore(name: "Dad",  initials: "DD", score: 68),
                    FamilyMemberScore(name: "Ann",  initials: "AN", score: 65)
                ]
            ),
            
            VitalityFactor(
                name: "Activity",
                iconName: "figure.walk",
                percent: 86,
                description: "Movement has been a strong point this week – most family members are hitting their activity goals.",
                actionPlan: [
                    "Lock in one shared movement session as a family this week.",
                    "Use short walks to break up long sitting blocks for everyone.",
                    "Turn one normal task (school run, dog walk) into a simple game."
                ],
                memberScores: [
                    FamilyMemberScore(name: "Josh", initials: "JK", score: 90),
                    FamilyMemberScore(name: "Mum",  initials: "MM", score: 82),
                    FamilyMemberScore(name: "Dad",  initials: "DD", score: 79),
                    FamilyMemberScore(name: "Ann",  initials: "AN", score: 93)
                ]
            ),
            
            VitalityFactor(
                name: "Stress",
                iconName: "exclamationmark.circle",
                percent: 64,
                description: "Stress signals are mixed – some days look calm, others are spiking for one or two family members.",
                actionPlan: [
                    "Add one ‘no phone’ window each day (e.g. dinner time).",
                    "Do a 3-minute breathing break together once per day.",
                    "End the day with one quick ‘win of the day’ share as a family."
                ],
                memberScores: [
                    FamilyMemberScore(name: "Josh", initials: "JK", score: 60),
                    FamilyMemberScore(name: "Mum",  initials: "MM", score: 70),
                    FamilyMemberScore(name: "Dad",  initials: "DD", score: 55),
                    FamilyMemberScore(name: "Ann",  initials: "AN", score: 65)
                ]
            ),
            
            VitalityFactor(
                name: "Mindfulness",
                iconName: "sparkles",
                percent: 58,
                description: "Moments of calm and reflection are happening occasionally, but not yet a consistent habit for the family.",
                actionPlan: [
                    "Choose one existing habit (breakfast, bedtime) to add a 2-minute check-in.",
                    "Try one short guided breathing / body-scan together this week.",
                    "Once a week, have a 5-minute ‘how are we really doing?’ chat."
                ],
                memberScores: [
                    FamilyMemberScore(name: "Josh", initials: "JK", score: 55),
                    FamilyMemberScore(name: "Mum",  initials: "MM", score: 62),
                    FamilyMemberScore(name: "Dad",  initials: "DD", score: 50),
                    FamilyMemberScore(name: "Ann",  initials: "AN", score: 65)
                ]
            )
        ]
    }
    
#Preview {
    NavigationStack {
        DashboardView(familyName: "The Kempton")
    }
}
    
    // MARK: - Sidebar mode
    
    private enum SidebarMode {
        case menu
        case account
        case manageMembers
        case invite
    }
    
    // MARK: - SIDEBAR MENU
    
    struct SidebarMenu: View {
        @Binding var isVisible: Bool
        
        // TEMP hard-coded user
        private let userName: String = "Josh Kempton"
        private let userEmail: String = "josh@example.com"
        private let isSuperAdmin: Bool = true
        
        @State private var mode: SidebarMode = .menu
        
        var body: some View {
            let menuWidth = UIScreen.main.bounds.width * 0.75
            
            ZStack {
                Color.miyaEmerald
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Brand line
                    VStack(alignment: .leading, spacing: 6) {
                        Text("One family, one mission.")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                            .padding(.trailing, 40)
                    }
                    .padding(.top, 40)
                    
                    // Main content
                    modeContent
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .frame(width: menuWidth, alignment: .leading)
        }
        
        // MARK: - Mode content
        
        @ViewBuilder
        private var modeContent: some View {
            switch mode {
            case .menu:
                menuContent
                
            case .account:
                AccountSidebarView(
                    userName: userName,
                    userEmail: userEmail,
                    isSuperAdmin: isSuperAdmin,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .menu
                        }
                    },
                    onSignOut: {
                        print("Sign out tapped")
                    },
                    onManageMembers: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .manageMembers
                        }
                    }
                )
                
            case .manageMembers:
                ManageMembersView(
                    members: [
                        FamilyMemberSummary(name: "Josh", isYou: true,  isAdmin: true),
                        FamilyMemberSummary(name: "Mum",  isYou: false, isAdmin: false),
                        FamilyMemberSummary(name: "Dad",  isYou: false, isAdmin: false),
                        FamilyMemberSummary(name: "Ann",  isYou: false, isAdmin: false)
                    ],
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .account
                        }
                    },
                    onMakeAdmin: { member in
                        print("Make admin → \(member.name)")
                    },
                    onRemove: { member in
                        print("Remove member → \(member.name)")
                    }
                )
                
            case .invite:
                InviteSidebarView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = .menu
                    }
                }
            }
        }
        
        // MARK: - MENU CONTENT
        
        private var menuContent: some View {
            VStack(alignment: .leading, spacing: 24) {
                
                // Account block (tap to open Account page)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(sidebarInitials(from: userName))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(userName)
                                .font(.system(size: 15, weight: .semibold))
                            Text("Account & Settings")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .account
                        }
                    }
                }
                
                // Main menu items
                VStack(alignment: .leading, spacing: 20) {
                    menuItem(icon: "book.closed", title: "Education Hub") {
                        print("Education Hub tapped")
                    }
                    
                    menuItem(icon: "person.badge.plus", title: "Invite family member") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .invite
                        }
                    }
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Sign out at bottom (still accessible from menu view)
                Button {
                    print("Sign out tapped")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Sign out")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Color.red.opacity(0.9))
                }
                .padding(.bottom, 24)
            }
        }
        
        // MARK: - Helpers
        
        private func menuItem(icon: String, title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, alignment: .leading)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        
        // Local initials helper just for SidebarMenu
        private func sidebarInitials(from name: String) -> String {
            let parts = name.split(separator: " ").map(String.init)
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
    }
    // MARK: - ACCOUNT SIDEBAR VIEW
    
    struct AccountSidebarView: View {
        let userName: String
        let userEmail: String
        let isSuperAdmin: Bool
        let onBack: () -> Void
        let onSignOut: () -> Void
        let onManageMembers: () -> Void
        
        // TEMP: mocked devices – later wire real data
        private let connectedDevices: [ConnectedDevice] = [
            ConnectedDevice(name: "Apple Health", lastSyncDescription: "2 hours ago")
        ]
        
        // Profile editing state
        @State private var isEditingProfile: Bool = false
        @State private var draftName: String = ""
        @State private var draftEmail: String = ""
        
        // Family name editing state
        @State private var draftFamilyName: String = "The Kempton Family"
        
        // Device detail state
        @State private var activeDevice: ConnectedDevice? = nil
        
        // Notification preferences state
        @State private var isShowingNotificationPrefs: Bool = false
        @State private var notifWeeklySummary: Bool = true
        @State private var notifChallenges: Bool = true
        @State private var notifFamilyUpdates: Bool = true
        
        // Quiet mode state
        private enum QuietDuration: String {
            case hours24 = "24 hours"
            case days3   = "3 days"
            case week1   = "1 week"
        }
        @State private var isShowingQuietMode: Bool = false
        @State private var selectedQuietDuration: QuietDuration? = nil
        
        // Contact support state
        @State private var isShowingSupport: Bool = false
        
        @State private var isPresentingChallengeSheet: Bool = false
        
        private var userInitials: String {
            initials(from: userName)
        }
        
        var body: some View {
            ZStack {
                // MAIN ACCOUNT CONTENT – scrollable
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Top bar
                        HStack(spacing: 8) {
                            Button(action: onBack) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .font(.system(size: 14))
                                }
                                .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Text("Account")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 4)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            
                            // ABOUT YOU
                            AccountSection("About you") {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Text(userInitials)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(userName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        Text(userEmail)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                }
                                
                                Button {
                                    draftName = userName
                                    draftEmail = userEmail
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditingProfile = true
                                    }
                                } label: {
                                    Text("Edit profile")
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(999)
                                }
                            }
                            
                            // CONNECTED DEVICES
                            AccountSection("Connected devices & data") {
                                if connectedDevices.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("No devices connected yet.")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.85))
                                        
                                        Button {
                                            print("Connect a device tapped")
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text("Connect a device")
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(Color.white)
                                            .foregroundColor(.miyaEmerald)
                                            .cornerRadius(999)
                                        }
                                    }
                                } else {
                                    VStack(spacing: 10) {
                                        ForEach(connectedDevices) { device in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(device.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.white)
                                                    
                                                    Text("Last sync: \(device.lastSyncDescription)")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.white.opacity(0.7))
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    activeDevice = device
                                                }
                                            }
                                        }
                                        
                                        Button {
                                            print("Connect another device tapped")
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "plus.circle")
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text("Connect another device")
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                            
                            // FAMILY SETTINGS (SUPERADMIN ONLY)
                            if isSuperAdmin {
                                AccountSection("Family settings") {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Family name")
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            TextField("Family name", text: $draftFamilyName)
                                                .font(.system(size: 14, weight: .semibold))
                                                .padding(8)
                                                .background(Color.white.opacity(0.10))
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                        }
                                        Spacer()
                                        Image(systemName: "pencil")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .contentShape(Rectangle())
                                    
                                    Divider().background(Color.white.opacity(0.15))
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Members")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("Josh (you), Mum, Dad, Ann")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button {
                                            onManageMembers()
                                        } label: {
                                            Text("Manage members")
                                                .font(.system(size: 13, weight: .semibold))
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 12)
                                                .background(Color.white.opacity(0.18))
                                                .foregroundColor(.white)
                                                .cornerRadius(999)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            
                            // APP SETTINGS + SIGN OUT
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingNotificationPrefs = true
                                }
                            } label: {
                                HStack {
                                    Text("Notification preferences")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingQuietMode = true
                                }
                            } label: {
                                HStack {
                                    Text("Quiet mode")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.vertical, 4)
                            }
                            
                            settingRow(title: "Data & privacy")
                            settingRow(title: "Terms of service")
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingSupport = true
                                }
                            } label: {
                                settingRow(title: "Contact support")
                            }
                            
                            Divider().background(Color.white.opacity(0.15))
                            
                            Button {
                                onSignOut()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Sign out")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(Color.red.opacity(0.95))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // EDIT PROFILE OVERLAY
                if isEditingProfile {
                    Color.clear
                    
                    VStack(spacing: 16) {
                        Text("Edit profile")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Button {
                            print("Change photo tapped")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "photo")
                                Text("Change photo")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.miyaEmerald)
                            .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.miyaTextSecondary)
                            TextField("Name", text: $draftName)
                                .padding(10)
                                .background(Color.miyaBackground)
                                .cornerRadius(10)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.miyaTextSecondary)
                            TextField("Email", text: $draftEmail)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingProfile = false
                                }
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            
                            Button {
                                print("Save profile tapped: \(draftName), \(draftEmail)")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingProfile = false
                                }
                            } label: {
                                Text("Save")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.miyaEmerald)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                    .shadow(radius: 1)
                }
                
                // NOTIFICATION PREFERENCES POPUP
                if isShowingNotificationPrefs {
                    Color.clear
                    
                    VStack(spacing: 16) {
                        Text("Notification preferences")
                            .font(.system(size: 16, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $notifWeeklySummary) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Weekly family health summary")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("One calm weekly digest for your whole family.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Toggle(isOn: $notifChallenges) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Challenges & missions")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Invites and key updates for Miya challenges.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Toggle(isOn: $notifFamilyUpdates) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Other family member updates")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("When someone completes a mission or hits a streak.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.miyaEmerald))
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingNotificationPrefs = false
                            }
                        } label: {
                            Text("Close")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                }
                
                // QUIET MODE POPUP
                if isShowingQuietMode {
                    Color.clear
                    
                    VStack(spacing: 16) {
                        Text("Quiet mode")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("Perfect for holidays, illness or busy weeks. Miya will still observe your data, but won’t nudge or react.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            quietOptionRow(
                                title: "24 hours",
                                subtitle: "Pause Miya until this time tomorrow.",
                                isSelected: selectedQuietDuration == .hours24
                            ) {
                                selectedQuietDuration = .hours24
                            }
                            
                            quietOptionRow(
                                title: "3 days",
                                subtitle: "Pause Miya for a short break or busy period.",
                                isSelected: selectedQuietDuration == .days3
                            ) {
                                selectedQuietDuration = .days3
                            }
                            
                            quietOptionRow(
                                title: "1 week",
                                subtitle: "Perfect for holidays or recovery weeks.",
                                isSelected: selectedQuietDuration == .week1
                            ) {
                                selectedQuietDuration = .week1
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingQuietMode = false
                                }
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            
                            Button {
                                print("Quiet mode on for \(selectedQuietDuration?.rawValue ?? "none selected")")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingQuietMode = false
                                }
                            } label: {
                                Text("Turn on Quiet mode")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.miyaEmerald)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                }
                
                // CONTACT SUPPORT POPUP
                if isShowingSupport {
                    Color.clear
                    
                    VStack(spacing: 16) {
                        Text("Contact support")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("If you need help, you can reach the Miya team anytime.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 12) {
                            Button {
                                let email = "support@miya.health"
                                if let url = URL(string: "mailto:\(email)") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "envelope")
                                    Text("Email Miya Support")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.miyaEmerald)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                UIPasteboard.general.string = "support@miya.health"
                            } label: {
                                Text("Copy email address")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingSupport = false
                            }
                        } label: {
                            Text("Close")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                }
                
                // DEVICE DETAIL POPUP
                if let device = activeDevice {
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            Text(device.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Wearable connection")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                            
                            Divider()
                            
                            Button {
                                print("Disconnect \(device.name) tapped")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeDevice = nil
                                }
                            } label: {
                                Text("Disconnect wearable")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                                    .background(Color.red.opacity(0.9))
                                    .cornerRadius(10)
                            }
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeDevice = nil
                                }
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.miyaPrimary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.9))
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        
        // MARK: - Local helpers (AccountSidebarView)
        
        private func settingRow(title: String) -> some View {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        
        private func quietOptionRow(
            title: String,
            subtitle: String,
            isSelected: Bool,
            onTap: @escaping () -> Void
        ) -> some View {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .miyaEmerald : .gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        
        // 👇 now this is INSIDE AccountSidebarView
        private func initials(from name: String) -> String {
            let parts = name
                .split(separator: " ")
                .map { String($0) }
            
            let first = parts.first?.first.map { String($0) } ?? ""
            let second = parts.dropFirst().first?.first.map { String($0) } ?? ""
            
            return (first + second).uppercased()
        }
    }
    // MARK: - Reusable section "card"
    
    private struct AccountSection<Content: View>: View {
        let title: String
        let content: Content
        
        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }
    
    // MARK: - Simple connected device model
    
    struct ConnectedDevice: Identifiable {
        let id = UUID()
        let name: String
        let lastSyncDescription: String
    }
    
    // MARK: - NATIVE iOS SHARE SHEET
    
    struct MiyaShareSheetView: UIViewControllerRepresentable {
        let activityItems: [Any]
        
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
        }
        
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
            // nothing to update
        }
    }
    // MARK: - Notifications UI
    
    struct NotificationPanel: View {
        var onClose: () -> Void
        
        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("Notifications")
                        .font(.headline)
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close notifications")
                }
                .padding()
                .background(.ultraThinMaterial)
                
                ScrollView {
                    VStack(spacing: 0) {
                        NotificationRow(
                            title: "Mom’s Apple Watch needs charging (10% battery)",
                            subtitle: "30 min ago"
                        )
                        
                        Divider()
                        
                        NotificationRow(
                            title: "New lab results available",
                            subtitle: "Tap to review"
                        )
                        
                        Divider()
                        
                        NotificationRow(
                            title: "Medication reminder",
                            subtitle: "8:00 PM daily"
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .frame(maxWidth: 560, alignment: .top)
        }
    }
    
    struct NotificationRow: View {
        let title: String
        let subtitle: String
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
                    .padding(6)
                    .background(Circle().fill(Color.orange.opacity(0.85)))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                // Handle notification tap
            }
        }
    }
    
    // MARK: - FAMILY MEMBERS
    
    struct FamilyMemberSummary: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let isYou: Bool
        let isAdmin: Bool
    }
    
    struct ManageMembersView: View {
        let members: [FamilyMemberSummary]
        
        let onBack: () -> Void
        let onMakeAdmin: (FamilyMemberSummary) -> Void
        let onRemove: (FamilyMemberSummary) -> Void
        
        @State private var selectedMemberForRemoval: FamilyMemberSummary? = nil
        @State private var selectedMemberForAdmin: FamilyMemberSummary? = nil
        
        var body: some View {
            ZStack {
                Color.miyaEmerald.ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Top bar
                    HStack(spacing: 8) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Text("Family members")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(members) { member in
                                memberRow(member)
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            // Remove member
            .confirmationDialog(
                "Remove this family member?",
                isPresented: Binding(
                    get: { selectedMemberForRemoval != nil },
                    set: { if !$0 { selectedMemberForRemoval = nil } }
                ),
                presenting: selectedMemberForRemoval
            ) { member in
                Button("Remove \(member.name)", role: .destructive) {
                    onRemove(member)
                    selectedMemberForRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    selectedMemberForRemoval = nil
                }
            } message: { member in
                Text("Are you sure you want to remove \(member.name) from this family?")
            }
            
            // Make admin
            .confirmationDialog(
                "Transfer family admin?",
                isPresented: Binding(
                    get: { selectedMemberForAdmin != nil },
                    set: { if !$0 { selectedMemberForAdmin = nil } }
                ),
                presenting: selectedMemberForAdmin
            ) { member in
                Button("Make \(member.name) admin", role: .destructive) {
                    onMakeAdmin(member)
                    selectedMemberForAdmin = nil
                }
                Button("Cancel", role: .cancel) {
                    selectedMemberForAdmin = nil
                }
            } message: { member in
                Text("Miya will make \(member.name) the new family admin.")
            }
        }
        
        // MARK: - Row
        
        private func memberRow(_ member: FamilyMemberSummary) -> some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(memberInitials(from: member.name))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if member.isYou {
                            Text("You")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.20))
                                .cornerRadius(999)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(member.isAdmin ? "Admin" : "Member")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                Menu {
                    if !member.isAdmin {
                        Button("Make admin") {
                            selectedMemberForAdmin = member
                        }
                    }
                    
                    if !member.isYou {
                        Button("Remove member", role: .destructive) {
                            selectedMemberForRemoval = member
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 8)
        }
        
        // Local initials helper just for ManageMembersView
        private func memberInitials(from name: String) -> String {
            let parts = name.split(separator: " ").map(String.init)
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
    }
    // MARK: - INVITE FROM SIDEBAR
    
    struct InviteSidebarView: View {
        // Local onboarding type just for this view
        private enum LocalOnboardingType {
            case selfSetup
            case guided
        }
        
        @State private var selectedType: LocalOnboardingType? = nil
        @State private var generatedCode: String? = nil
        
        let onBack: () -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                
                // Top bar
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                
                // Title + subtitle
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite a family member")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Choose how you want them to set up Miya, and we’ll generate a code you can share.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Type selection buttons
                VStack(spacing: 10) {
                    inviteTypeButton(
                        title: "Self setup",
                        subtitle: "They go through the full onboarding and connect their own wearables.",
                        type: .selfSetup
                    )
                    
                    inviteTypeButton(
                        title: "Guided",
                        subtitle: "You or another admin will guide them through setup step by step.",
                        type: .guided
                    )
                }
                .padding(.top, 8)
                
                // Generated code card
                if let code = generatedCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite code")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        
                        HStack {
                            Text(code)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                            
                            Spacer()
                            
                            Button {
                                copyCode(code)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Copy")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(999)
                            }
                        }
                        
                        Text("Share this code with your family member. They’ll paste it into their Miya app to join your family.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .padding(.top, 12)
                }
                
                Spacer()
            }
            .padding(.top, 40)
        }
        
        // MARK: - Type Button
        
        private func inviteTypeButton(
            title: String,
            subtitle: String,
            type: LocalOnboardingType
        ) -> some View {
            let isSelected = (selectedType == type)
            
            return Button {
                selectType(type)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
        
        // MARK: - Logic
        
        private func selectType(_ type: LocalOnboardingType) {
            selectedType = type
            generatedCode = generateCode(for: type)
        }
        
        private func generateCode(for type: LocalOnboardingType) -> String {
            let prefix: String
            switch type {
            case .selfSetup: prefix = "MIYA"
            case .guided:    prefix = "GUIDE"
            }
            
            let number = Int.random(in: 1000...9999)
            return "\(prefix)-\(number)"
        }
        
        private func copyCode(_ code: String) {
            UIPasteboard.general.string = code
            print("Copied invite code: \(code)")
        }
    }   // 👈 end of InviteSidebarView
    
    
    // MARK: - Shared Helper (for Sidebar, Account, ManageMembers)
    
    fileprivate func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
// MARK: - Mission Hub Card

struct MissionHubCard: View {
    @Binding var isPresentingChallengeSheet: Bool
    let activeSleepChallenge: SleepChallengeUIModel?
    let activeStepsChallenge: StepsChallengeUIModel?
    let activeHydrationChallenge: HydrationChallengeUIModel?
    let activeMovementChallenge: MovementChallengeUIModel?
    let activeMeditationChallenge: MeditationChallengeUIModel?
    let activeNutritionChallenge: NutritionChallengeUIModel?

    var body: some View {
        Group {
            if let steps = activeStepsChallenge {
                // Steps has highest priority
                ActiveStepsChallengeCard(model: steps)

            } else if let movement = activeMovementChallenge {
                // Then movement
                ActiveMovementChallengeCard(model: movement)

            } else if let hydration = activeHydrationChallenge {
                // Then hydration
                ActiveHydrationChallengeCard(model: hydration)

            } else if let meditation = activeMeditationChallenge {
                // Then meditation
                ActiveMeditationChallengeCard(model: meditation)

            } else if let nutrition = activeNutritionChallenge {
                // Then nutrition
                ActiveNutritionChallengeCard(model: nutrition)

            } else if let sleep = activeSleepChallenge {
                // Then sleep
                ActiveSleepChallengeCard(challenge: sleep)

            } else {
                // Empty state
                EmptyMissionHubCard(isPresentingChallengeSheet: $isPresentingChallengeSheet)
            }
        }
    }
}
    // MARK: - Empty state (no active challenge)
    
    private struct EmptyMissionHubCard: View {
        @Binding var isPresentingChallengeSheet: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mission Hub")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Spacer()
                }
                .padding(.top, 12)
                
                VStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.system(size: 24))
                        .foregroundColor(.miyaTextSecondary)
                    
                    Text("No active challenge")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Start a new family challenge to get everyone motivated!")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        isPresentingChallengeSheet = true
                    } label: {
                        Text("Start challenge")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 18)
                            .background(Color.miyaPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
    // MARK: - Active Sleep Challenge Card
    
    private struct ActiveSleepChallengeCard: View {
        let challenge: SleepChallengeUIModel
        
        @State private var selectedWeekIndex: Int = 0
        
        private var weeksCount: Int {
            challenge.totalWeeks
        }
        
        private var currentWeekLabel: String {
            weeksCount > 1 ? "Week \(selectedWeekIndex + 1) of \(weeksCount)" : "This week"
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                // HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mission Hub")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                        
                        Text(challenge.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Best streak so far · \(bestTotalHits())/\(challenge.totalDays) on-target days")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    
                    Spacer()
                    
                    if weeksCount > 1 {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(currentWeekLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.miyaPrimary.opacity(0.08))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(999)
                            
                            Text("\(challenge.currentDay)/\(challenge.totalDays) days")
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                        }
                    } else {
                        Text("\(challenge.currentDay)/\(challenge.totalDays) days")
                            .font(.system(size: 11))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                
                // WEEK SELECTOR (only if > 1 week)
                if weeksCount > 1 {
                    HStack {
                        Button {
                            if selectedWeekIndex > 0 { selectedWeekIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedWeekIndex > 0 ? .miyaPrimary : .gray.opacity(0.4))
                        }
                        .disabled(selectedWeekIndex == 0)
                        
                        Spacer()
                        
                        Text(currentWeekLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Spacer()
                        
                        Button {
                            if selectedWeekIndex < weeksCount - 1 { selectedWeekIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedWeekIndex < weeksCount - 1 ? .miyaPrimary : .gray.opacity(0.4))
                        }
                        .disabled(selectedWeekIndex == weeksCount - 1)
                    }
                    .padding(.vertical, 4)
                }
                
                // WEEKLY DOTS
                VStack(alignment: .leading, spacing: 8) {
                    Text("This week’s hits")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    ForEach(challenge.participants) { participant in
                        WeeklyDotsRow(
                            participant: participant,
                            totalDays: challenge.totalDays,
                            weekIndex: selectedWeekIndex
                        )
                    }
                }
                
                // LEADERBOARD
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall leaderboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    let ranked = challenge.participants
                        .sorted { $0.totalHits > $1.totalHits }
                    
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, participant in
                        LeaderboardRow(
                            position: index + 1,
                            participant: participant,
                            totalDays: challenge.totalDays
                        )
                    }
                }
                
                Button {
                    // later: open detailed challenge screen
                    print("View full challenge tapped")
                } label: {
                    Text("View full challenge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
        
        private func bestTotalHits() -> Int {
            challenge.participants.map { $0.totalHits }.max() ?? 0
        }
    }
    // MARK: - Active Steps Challenge (Mission Hub summary)
    
    private struct ActiveStepsChallengeCard: View {
        let model: StepsChallengeUIModel
        
        private var todaySteps: Int {
            min(model.familyStepsToday, model.familyDailyTarget)
        }
        
        private var todayTarget: Int {
            model.familyDailyTarget
        }
        
        private var progressFraction: Double {
            guard todayTarget > 0 else { return 0 }
            return min(Double(todaySteps) / Double(todayTarget), 1.0)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                // HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mission Hub")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                        
                        Text("Daily Steps Challenge")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Clear your family step pot each day. Everyone contributes to the total.")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(model.dayLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.miyaPrimary.opacity(0.08))
                            .foregroundColor(.miyaPrimary)
                            .cornerRadius(999)
                    }
                }
                
                // FAMILY POT
                VStack(alignment: .leading, spacing: 8) {
                    Text("Family progress today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                            .tint(Color.miyaPrimary)
                        
                        HStack {
                            Text("\(todaySteps.formatted()) / \(todayTarget.formatted()) steps")
                                .font(.system(size: 13, weight: .semibold))
                            
                            Spacer()
                            
                            let remaining = max(todayTarget - todaySteps, 0)
                            Text("\(remaining.formatted()) left to clear")
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                
                // LEADERBOARD (top 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s leaderboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    let sorted = model.participants.sorted {
                        if $0.hitDaysCount == $1.hitDaysCount {
                            return $0.totalSteps > $1.totalSteps
                        } else {
                            return $0.hitDaysCount > $1.hitDaysCount
                        }
                    }
                    
                    ForEach(Array(sorted.prefix(3).enumerated()), id: \.element.id) { index, participant in
                        StepsLeaderboardRow(
                            position: index + 1,
                            participant: participant,
                            currentDayIndex: max(0, model.currentDay - 1)
                        )
                    }
                }
                
                Button {
                    print("View full steps challenge tapped")
                } label: {
                    Text("View full challenge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
    // MARK: - Active Hydration Challenge (Mission Hub summary)
    
    private struct ActiveHydrationChallengeCard: View {
        let model: HydrationChallengeUIModel
        
        @State private var selectedWeekIndex: Int = 0
        
        private var weeksCount: Int {
            model.totalWeeks
        }
        
        private var currentWeekLabel: String {
            weeksCount > 1 ? "Week \(selectedWeekIndex + 1) of \(weeksCount)" : "This week"
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                // HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mission Hub")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                        
                        Text(model.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Best streak so far · \(model.bestDaysOnTarget)/\(model.totalDays) hydrated days")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    
                    Spacer()
                    
                    if weeksCount > 1 {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.dayLabel)
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                            
                            Text(currentWeekLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.miyaPrimary.opacity(0.08))
                                .foregroundColor(.miyaPrimary)
                                .cornerRadius(999)
                        }
                    } else {
                        Text(model.dayLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
                
                // WEEK SELECTOR (if > 1 week)
                if weeksCount > 1 {
                    HStack {
                        Button {
                            if selectedWeekIndex > 0 { selectedWeekIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedWeekIndex > 0 ? .miyaPrimary : .gray.opacity(0.4))
                        }
                        .disabled(selectedWeekIndex == 0)
                        
                        Spacer()
                        
                        Text(currentWeekLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Spacer()
                        
                        Button {
                            if selectedWeekIndex < weeksCount - 1 { selectedWeekIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedWeekIndex < weeksCount - 1 ? .miyaPrimary : .gray.opacity(0.4))
                        }
                        .disabled(selectedWeekIndex == weeksCount - 1)
                    }
                    .padding(.vertical, 4)
                }
                
                // WEEKLY DOTS
                VStack(alignment: .leading, spacing: 8) {
                    Text("This week’s hydrated days")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    ForEach(model.participants) { participant in
                        HydrationWeeklyDotsRow(
                            participant: participant,
                            totalDays: model.totalDays,
                            weekIndex: selectedWeekIndex
                        )
                    }
                }
                
                // LEADERBOARD
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall leaderboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    let ranked = model.participants.sorted { $0.daysOnTarget > $1.daysOnTarget }
                    
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, participant in
                        HydrationLeaderboardRow(
                            position: index + 1,
                            participant: participant,
                            totalDays: model.totalDays
                        )
                    }
                }
                
                Button {
                    print("View full hydration challenge tapped")
                } label: {
                    Text("View full challenge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
    private struct HydrationWeeklyDotsRow: View {
        let participant: HydrationChallengeUIModel.Participant
        let totalDays: Int
        let weekIndex: Int
        
        private var weekStartIndex: Int {
            weekIndex * 7
        }
        
        private var weekLength: Int {
            max(0, min(7, totalDays - weekStartIndex))
        }
        
        /// Simple front-end allocation: earlier weeks get the earlier “hit” dots
        private var hitsThisWeek: Int {
            let remainingAfterPreviousWeeks = max(participant.daysOnTarget - weekStartIndex, 0)
            return min(weekLength, remainingAfterPreviousWeeks)
        }
        
        var body: some View {
            HStack(spacing: 8) {
                Text(participant.name)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 60, alignment: .leading)
                
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { offset in
                        let isValidDay = offset < weekLength
                        let isHit = isValidDay && offset < hitsThisWeek
                        
                        Circle()
                            .frame(width: 7, height: 7)
                            .foregroundColor(
                                !isValidDay
                                ? Color(.systemGray5)
                                : (isHit ? Color.miyaPrimary : Color(.systemGray4))
                            )
                    }
                }
                
                Spacer()
                
                Text("\(hitsThisWeek)/\(weekLength)")
                    .font(.system(size: 11))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
    
    private struct HydrationLeaderboardRow: View {
        let position: Int
        let participant: HydrationChallengeUIModel.Participant
        let totalDays: Int
        
        private var streak: Int {
            min(participant.daysOnTarget, 7)
        }
        
        private var streakBadge: String {
            switch streak {
            case 5...: return "🔥 \(streak)-day streak"
            case 3...4: return "⭐ \(streak)-day streak"
            case 1...2: return "\(streak)-day streak"
            default:    return "—"
            }
        }
        
        var body: some View {
            HStack {
                Text("\(position).")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.name)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("\(participant.daysOnTarget)/\(totalDays) hydrated days")
                        .font(.system(size: 11))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                Spacer()
                
                Text(streakBadge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.miyaPrimary)
            }
        }
    }
    // MARK: - Active Movement Challenge (Mission Hub summary)
    
    private struct ActiveMovementChallengeCard: View {
        let model: MovementChallengeUIModel
        
        private var todayMinutes: Int {
            min(model.familyMinutesToday, model.familyDailyTarget)
        }
        
        private var todayTarget: Int {
            model.familyDailyTarget
        }
        
        private var progressFraction: Double {
            guard todayTarget > 0 else { return 0 }
            return min(Double(todayMinutes) / Double(todayTarget), 1.0)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                // HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mission Hub")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaTextSecondary)
                        
                        Text("Movement Challenge")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Clear your family movement pot each day. Walking, gym, sports and active play all count.")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(model.dayLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.miyaPrimary.opacity(0.08))
                            .foregroundColor(.miyaPrimary)
                            .cornerRadius(999)
                    }
                }
                
                // FAMILY POT
                VStack(alignment: .leading, spacing: 8) {
                    Text("Family progress today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                            .tint(Color.miyaPrimary)
                        
                        HStack {
                            Text("\(todayMinutes) / \(todayTarget) mins")
                                .font(.system(size: 13, weight: .semibold))
                            
                            Spacer()
                            
                            let remaining = max(todayTarget - todayMinutes, 0)
                            Text("\(remaining) mins left to clear")
                                .font(.system(size: 11))
                                .foregroundColor(.miyaTextSecondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                
                // LEADERBOARD (top 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s leaderboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextSecondary)
                    
                    let sorted = model.participants.sorted {
                        if $0.hitDaysCount == $1.hitDaysCount {
                            return $0.totalMinutes > $1.totalMinutes
                        } else {
                            return $0.hitDaysCount > $1.hitDaysCount
                        }
                    }
                    
                    ForEach(Array(sorted.prefix(3).enumerated()), id: \.element.id) { index, participant in
                        MovementMissionHubRow(
                            position: index + 1,
                            participant: participant,
                            currentDayIndex: max(0, model.currentDay - 1)
                        )
                    }
                }
                
                Button {
                    print("View full movement challenge tapped")
                } label: {
                    Text("View full challenge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaPrimary)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
    
    // MARK: - Movement leaderboard row (Mission Hub)
    
    private struct MovementMissionHubRow: View {
        let position: Int
        let participant: MovementChallengeUIModel.Participant
        let currentDayIndex: Int
        
        private var todayMinutes: Int {
            guard currentDayIndex < participant.dailyMinutes.count else { return 0 }
            return participant.dailyMinutes[currentDayIndex]
        }
        
        private var hitToday: Bool {
            todayMinutes >= participant.dailyTargetMinutes
        }
        
        private var streakText: String {
            let streak = participant.currentStreak
            switch streak {
            case 3...: return "\(streak)-day streak"
            case 2:    return "2-day streak"
            case 1:    return "1-day streak"
            default:   return "No streak yet"
            }
        }
        
        private var streakIconName: String? {
            let streak = participant.currentStreak
            switch streak {
            case 3...: return "flame.fill"
            case 2:    return "star.fill"
            case 1:    return "circle.fill"
            default:   return nil
            }
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Rank pill
                Text("\(position)")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(position == 1
                                  ? Color.miyaPrimary
                                  : Color(.systemGray5))
                    )
                    .foregroundColor(position == 1 ? .white : .primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.name)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("\(todayMinutes) / \(participant.dailyTargetMinutes) mins today")
                        .font(.system(size: 11))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Today hit badge
                    HStack(spacing: 4) {
                        Image(systemName: hitToday ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(hitToday ? .green : .secondary)
                        
                        Text(hitToday ? "Hit today" : "Missed today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(hitToday ? .green : .secondary)
                    }
                    
                    // Streak pill
                    if let icon = streakIconName {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                            
                            Text(streakText)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.miyaPrimary.opacity(0.08))
                        .foregroundColor(.miyaPrimary)
                        .cornerRadius(999)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
            )
        }
    }
    // MARK: - Weekly dots row
    
    private struct WeeklyDotsRow: View {
        let participant: SleepChallengeUIModel.Participant
        let totalDays: Int
        let weekIndex: Int
        
        private var weekRange: Range<Int> {
            let start = weekIndex * 7
            let end = min(start + 7, totalDays)
            return start..<end
        }
        
        private var hitsThisWeek: Int {
            weekRange.reduce(0) { acc, index in
                guard index < participant.nightlyHits.count else { return acc }
                return acc + (participant.nightlyHits[index] ? 1 : 0)
            }
        }
        
        var body: some View {
            HStack(spacing: 8) {
                Text(participant.name)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 60, alignment: .leading)
                
                // 7-dot strip
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { offset in
                        let index = weekIndex * 7 + offset
                        let isValidDay = index < totalDays
                        let isHit = isValidDay && index < participant.nightlyHits.count && participant.nightlyHits[index]
                        
                        Circle()
                            .frame(width: 7, height: 7)
                            .foregroundColor(
                                !isValidDay
                                ? Color(.systemGray5)
                                : (isHit ? Color.miyaPrimary : Color(.systemGray4))
                            )
                    }
                }
                
                Spacer()
                
                Text("\(hitsThisWeek)/\(min(7, totalDays - weekIndex * 7))")
                    .font(.system(size: 11))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
    
    // MARK: - Leaderboard row
    
    private struct LeaderboardRow: View {
        let position: Int
        let participant: SleepChallengeUIModel.Participant
        let totalDays: Int
        
        private var streakBadge: String {
            let streak = computeCurrentStreak()
            switch streak {
            case 3...: return "🔥 \(streak)-day streak"
            case 2:    return "⭐ 2-day streak"
            case 1:    return "1-day streak"
            default:   return "—"
            }
        }
        
        var body: some View {
            HStack {
                Text("\(position).")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.name)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("\(participant.totalHits)/\(totalDays) on-target days")
                        .font(.system(size: 11))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                Spacer()
                
                Text(streakBadge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.miyaPrimary)
            }
        }
        
        private func computeCurrentStreak() -> Int {
            var streak = 0
            for hit in participant.nightlyHits.reversed() {
                if hit {
                    streak += 1
                } else {
                    break
                }
            }
            return streak
        }
    }
    // MARK: - Single challenge row (card style)
    
    private struct ChallengeCardRow<Destination: View>: View {
        let iconName: String
        let iconColor: Color
        let title: String
        let subtitle: String
        let destination: Destination
        
        var body: some View {
            NavigationLink {
                destination
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)
        }
    }
