import SwiftUI
import UIKit
import Foundation
import Supabase

// AUDIT REPORT (guided onboarding status-driven admin dashboard)
// - Compile audit: Cannot run `xcodebuild` in this environment (no Xcode). Verified compile-safety via lints/type checks in Cursor.
// - State integrity: Admin "Guided setup" UI reads only from `FamilyMemberRecord.guidedSetupStatus` (canonical DB field)
//   and maps status -> label/CTA with no inferred booleans.
// - DB correctness: Card is fed by `DataManager.fetchFamilyMembers(familyId:)` (fresh query) and filters `onboardingType == "Guided Setup"`.
// - CTA correctness:
//    pending_acceptance -> Resend invite (share sheet; reuses existing invite code; no DB mutation)
//    accepted_awaiting_data -> Start guided setup (routes to GuidedHealthDataEntryFlow)
//    data_complete_pending_review -> Remind member (share sheet; reuses existing invite code; no DB mutation)
//    reviewed_complete -> View profile (routes to ProfileView placeholder)
// - Edge cases: null guided_setup_status is treated as pending_acceptance.
// - Known limitations: Profile routing is a placeholder (ProfileView is not yet driven by real member data in this dashboard).

// MARK: - VITALITY MODEL

// A single family member's score for a specific vitality factor
struct FamilyMemberScore: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let userId: String?         // auth.users.id (uuid string) when available
    let hasScore: Bool          // true only if a valid vitality_score_current exists (>= 0) AND profile row exists
    let isScoreFresh: Bool      // true only if vitality_score_updated_at is within last 3 days (UTC-ish)
    let isStale: Bool           // hasScore == true && isScoreFresh == false (displayable but excluded from family calcs/insights)
    let currentScore: Int       // 0–100 for UI; meaningful only if hasScore (freshness affects inclusion, not display)
    let optimalScore: Int       // UI; meaningful only if hasScore (0 if missing/invalid)
    /// Derived, capped 0–100 progress-to-optimal score (computed in DB via age×risk matrix).
    /// If nil, callers may fall back to current/optimal ratio for display only.
    let progressScore: Int?
    let inviteStatus: String?
    let onboardingType: String?
    let guidedSetupStatus: String?
    let isMe: Bool

    var ringProgress: Double {
        if let progressScore {
            return max(0.0, min(Double(progressScore) / 100.0, 1.0))
        }
        // Display-only fallback: if a member doesn't have a progress score yet, render relative to
        // current/optimal (or 100 if target missing) so the UI doesn't appear "empty".
        let denom = optimalScore > 0 ? optimalScore : 100
        let ratio = Double(currentScore) / Double(denom)
        return max(0.0, min(ratio, 1.0))
    }
    
    var isPending: Bool {
        // BUG 2 FIX: Guided members are pending until reviewed_complete
        if onboardingType == "Guided Setup" {
            #if DEBUG
            print("🔍 isPending check: name=\(name) status='\(guidedSetupStatus ?? "nil")' result=\(guidedSetupStatus != "reviewed_complete")")
            #endif
            return guidedSetupStatus != "reviewed_complete"
        }
        // Self Setup / normal: use invite status
        return (inviteStatus ?? "").lowercased() == "pending"
    }
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
// MARK: - DASHBOARD DESIGN SYSTEM

/// Premium design system for Dashboard components
/// Inspired by Apple Health's polish and iOS HIG patterns
private enum DashboardDesign {
    // MARK: - Spacing (matching onboarding flow)
    static let cardPadding: CGFloat = 16  // Like onboarding cards
    static let cardSpacing: CGFloat = 20  // Between cards
    static let sectionSpacing: CGFloat = 24  // Between sections (like onboarding)
    static let internalSpacing: CGFloat = 16  // Inside cards
    static let smallSpacing: CGFloat = 12  // Between related elements
    static let tinySpacing: CGFloat = 8  // Tight spacing
    static let microSpacing: CGFloat = 4  // Very tight
    
    // MARK: - Corner radius (matching onboarding - 16 for cards)
    static let cardCornerRadius: CGFloat = 16  // Like onboarding cards
    static let smallCornerRadius: CGFloat = 12
    static let tinyCornerRadius: CGFloat = 10
    
    // MARK: - Shadows (stronger for depth and gloss effect)
    static let cardShadow = Shadow(
        color: Color.black.opacity(0.08),
        radius: 12,
        x: 0,
        y: 4
    )
    
    static let cardShadowLight = Shadow(
        color: Color.black.opacity(0.05),
        radius: 8,
        x: 0,
        y: 2
    )
    
    static let cardShadowStrong = Shadow(
        color: Color.black.opacity(0.12),
        radius: 16,
        x: 0,
        y: 6
    )
    
    // MARK: - Typography (smaller, cleaner - matching onboarding)
    static let largeTitleFont = Font.system(size: 20, weight: .bold, design: .default)  // Main titles
    static let titleFont = Font.system(size: 18, weight: .semibold, design: .default)  // Section titles
    static let title2Font = Font.system(size: 16, weight: .semibold, design: .default)  // Card titles
    static let sectionHeaderFont = Font.system(size: 15, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .default)  // Primary content
    static let bodySemiboldFont = Font.system(size: 15, weight: .semibold, design: .default)
    static let calloutFont = Font.system(size: 14, weight: .regular, design: .default)  // Card descriptions
    static let subheadlineFont = Font.system(size: 14, weight: .medium, design: .default)
    static let footnoteFont = Font.system(size: 13, weight: .regular, design: .default)
    static let secondaryFont = Font.system(size: 13, weight: .regular, design: .default)
    static let secondarySemiboldFont = Font.system(size: 13, weight: .semibold, design: .default)
    static let captionFont = Font.system(size: 12, weight: .regular, design: .default)
    static let captionSemiboldFont = Font.system(size: 12, weight: .semibold, design: .default)
    static let tinyFont = Font.system(size: 10, weight: .medium, design: .default)
    
    // Score fonts (for vitality numbers - compact sizing)
    static let scoreLargeFont = Font.system(size: 36, weight: .bold, design: .rounded)
    static let scoreMediumFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let scoreSmallFont = Font.system(size: 18, weight: .bold, design: .rounded)
    
    // MARK: - Colors (Real colors like onboarding - vibrant and clear)
    // Primary brand colors
    static let miyaTealSoft = Color.miyaPrimary  // Use actual brand color
    static let miyaEmeraldSoft = Color.miyaEmerald  // Use actual brand color
    
    // Pillar-specific colors (real, vibrant colors like onboarding)
    static let sleepColor = Color.purple  // Real purple like onboarding
    static let movementColor = Color.green  // Real green
    static let stressColor = Color.orange  // Real orange
    static let vitalityColor = Color.blue  // Real blue
    
    // Button tint (for Chat with Arlo)
    static let buttonTint = Color.blue  // Real blue
    
    // Background colors (warmer, softer)
    static var mainBackground: Color {
        Color(red: 0.98, green: 0.98, blue: 0.99)  // Very light warm gray
    }
    
    static var cardBackgroundColor: Color {
        Color.white.opacity(0.7)  // Base for glass effect
    }
    
    static var groupedBackground: Color {
        Color(red: 0.97, green: 0.97, blue: 0.98)  // Subtle grouping
    }
    
    static var secondaryBackgroundColor: Color {
        Color(.secondarySystemBackground)
    }
    
    static var tertiaryBackgroundColor: Color {
        Color(.tertiarySystemBackground)
    }
    
    // Text colors (matching onboarding - use actual Miya colors)
    static var primaryTextColor: Color {
        Color.miyaTextPrimary  // Use actual brand text color
    }
    
    static var secondaryTextColor: Color {
        Color.miyaTextSecondary  // Use actual brand secondary text
    }
    
    static var tertiaryTextColor: Color {
        Color.miyaTextSecondary.opacity(0.7)  // Lighter version
    }
    
    // MARK: - Glass Effect Helper (with stronger shadows and gloss)
    static func glassCardBackground(tint: Color = .white) -> some View {
        ZStack {
            // Base white background
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(Color.white)
            
            // Glass material overlay for gloss
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(.ultraThinMaterial)
            
            // Gloss gradient for depth
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
        )
        .shadow(
            color: cardShadow.color,
            radius: cardShadow.radius,
            x: cardShadow.x,
            y: cardShadow.y
        )
    }
    
    // MARK: - Glass Card modifier (for consistent application)
    struct GlassCardModifier: ViewModifier {
        let tint: Color
        
        init(tint: Color = .white) {
            self.tint = tint
        }
        
        func body(content: Content) -> some View {
            content
                .padding(cardPadding)
                .background(glassCardBackground(tint: tint))
        }
    }
    
    // MARK: - Card styling helper (legacy, for non-glass cards)
    static func cardStyle() -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(cardBackgroundColor)
            .shadow(
                color: cardShadow.color,
                radius: cardShadow.radius,
                x: cardShadow.x,
                y: cardShadow.y
            )
    }
    
    // MARK: - Card modifier (legacy, for non-glass cards)
    struct CardModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(cardBackgroundColor)
                )
                .shadow(
                    color: cardShadow.color,
                    radius: cardShadow.radius,
                    x: cardShadow.x,
                    y: cardShadow.y
                )
        }
    }
    
    // MARK: - Icon container styling (softer colors)
    static func iconContainer(size: CGFloat = 40, color: Color = miyaTealSoft) -> some View {
        Circle()
            .fill(color.opacity(0.15))  // Softer opacity
            .frame(width: size, height: size)
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Extension for Card Styling
extension View {
    func dashboardCardStyle() -> some View {
        self.modifier(DashboardDesign.CardModifier())
    }
    
    func glassCardStyle(tint: Color = .white) -> some View {
        self.modifier(DashboardDesign.GlassCardModifier(tint: tint))
    }
}

// MARK: - HELPER SHAPES AND VIEWS

public struct ArcShape: Shape {
    /// 0.0 to 1.0 where 1.0 is a full TOP semicircle (left → right)
    var progress: Double
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Use a true semicircle centered horizontally.
        // The radius is constrained so the stroke won't get clipped.
        let lineWidth: CGFloat = 15 // should match/approx the gauge stroke width
        let radius = (min(rect.width, rect.height * 2) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY)

        let clamped = max(0.0, min(progress, 1.0))
        let startAngle = Angle.degrees(180)
        let endAngle = Angle.degrees(180 - (180 * clamped))
        
        // IMPORTANT: SwiftUI's coordinate system has Y pointing down.
        // To render the TOP semicircle (∩) from left → right, we must draw counterclockwise.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        
        return path
    }
}


// MARK: - TOP BAR

struct DashboardTopBar: View {
    let familyName: String
    let onShareTapped: () -> Void
    let onMenuTapped: () -> Void
    let onNotificationsTapped: () -> Void

    var body: some View {
        ZStack {
            // Premium header with softer emerald color
            DashboardDesign.miyaEmeraldSoft
                .ignoresSafeArea(edges: [.top])

            // Subtle blur effect for depth (refined opacity)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: [.top])
                .opacity(0.1)

            HStack(spacing: 0) {
                // LEFT — Burger menu (premium tap target)
                Button {
                    onMenuTapped()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                Spacer()

                // CENTER — Family name (refined typography, better spacing)
                Text("\(familyName) Family")
                    .font(DashboardDesign.sectionHeaderFont)
                    .foregroundColor(.white)

                Spacer()

                // RIGHT — Share + Notifications (improved spacing and tap targets)
                HStack(spacing: DashboardDesign.smallSpacing) {
                    Button {
                        onShareTapped()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    Button {
                        onNotificationsTapped()
                    } label: {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .padding(.horizontal, DashboardDesign.smallSpacing)
        }
        .frame(height: 56)
    }
}

// MARK: - DASHBOARD VIEW

struct DashboardView: View {
    let familyName: String
    
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    
    @State private var selectedFactor: VitalityFactor? = nil
    @State private var familyMembers: [FamilyMemberScore] = []
    @State private var resolvedFamilyName: String = ""
    @State private var vitalityFactors: [VitalityFactor] = []
    
    /// Canonical family member records (includes `guided_setup_status`).
    /// Used for admin status mapping UI; no inference from UI flags.
    @State private var familyMemberRecords: [FamilyMemberRecord] = []
    
    /// Refresh ID to force family members strip to update
    @State private var familyMembersRefreshID = UUID()
    
    /// IDs of dismissed guided members (don't show in card)
    @State private var dismissedGuidedMemberIds: Set<String> = []
    
    /// Current authenticated user ID (loaded async, used for role checks)
    @State private var currentUserIdString: String? = nil
    
    // Burger + share state
    @State private var showSidebar: Bool = false
    @State private var isShareSheetPresented: Bool = false
    @State private var shareText: String = ""
    
    // Notifications overlay state
    @State private var showNotifications: Bool = false

    // Family vitality (in-memory only; no UI yet)
    @State private var familyVitalityScore: Int? = nil
    @State private var familyVitalityProgressScore: Int? = nil
    @State private var isLoadingFamilyVitality: Bool = false
    @State private var familyVitalityErrorMessage: String? = nil
    @State private var familySnapshot: FamilyVitalitySnapshot? = nil
    @State private var familyVitalityMembersWithData: Int? = nil
    @State private var familyVitalityMembersTotal: Int? = nil
    @State private var trendInsights: [TrendInsight] = []
    @State private var trendCoverage: TrendCoverageStatus? = nil
    @State private var isComputingTrendInsights: Bool = false
    @State private var serverPatternAlerts: [FamilyNotificationItem] = []
    @State private var selectedFamilyNotification: FamilyNotificationItem? = nil
    
    // Family badges (Daily computed; Weekly persisted)
    @State private var dailyBadgeWinners: [BadgeEngine.Winner] = []
    @State private var weeklyBadgeWinners: [BadgeEngine.Winner] = []
    @State private var weeklyBadgeWeekStart: String? = nil
    @State private var weeklyBadgeWeekEnd: String? = nil

    // Superadmin-only: present Invite Member flow from sidebar reliably (single source of truth at Dashboard root)
    @State private var isInviteMemberSheetPresented: Bool = false

    // Loading states (avoid flashing placeholders while data is still loading)
    @State private var isLoadingFamilyMembers: Bool = false
    @State private var isShowingDebugUpload: Bool = false
    @State private var isShowingDebugAddRecord: Bool = false
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()  // Use actual onboarding background
            
            VStack(spacing: 0) {
                // TOP BAR
                DashboardTopBar(
                    familyName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
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
                    VStack(alignment: .leading, spacing: DashboardDesign.sectionSpacing) {
#if DEBUG
                        // Debug buttons (visually subordinate, smaller, less prominent)
                        HStack(spacing: DashboardDesign.smallSpacing) {
                            Button {
                                isShowingDebugUpload = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "tray.and.arrow.up")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Upload data")
                                        .font(DashboardDesign.tinyFont)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
                                .foregroundColor(DashboardDesign.secondaryTextColor)
                                .cornerRadius(DashboardDesign.tinyCornerRadius)
                            }
                            
                            Button {
                                isShowingDebugAddRecord = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Add record")
                                        .font(DashboardDesign.tinyFont)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
                                .foregroundColor(DashboardDesign.secondaryTextColor)
                                .cornerRadius(DashboardDesign.tinyCornerRadius)
                            }
                        }
                        .padding(.bottom, DashboardDesign.tinySpacing)
#endif

                        // Family members strip (avatars with vitality rings + nav to ProfileView)
                        Group {
                            if isLoadingFamilyMembers {
                                DashboardInlineLoaderCard(title: "Family members")
                            } else {
                        FamilyMembersStrip(members: familyMembers, familyId: dataManager.currentFamilyId)
                            .id(familyMembersRefreshID)
                            }
                        }
                        .padding(.top, 8)
                        
                        // Guided setup status (admin-facing): map guided_setup_status → label + CTA.
                        // BUG 6 FIX: Only show for admin/superadmin roles
                        if let uid = currentUserIdString,
                           let myMembership = familyMemberRecords.first(where: { $0.userId?.uuidString == uid }),
                           (myMembership.role == "admin" || myMembership.role == "superadmin") {
                            let guidedMembers = familyMemberRecords.filter {
                                    $0.onboardingType == "Guided Setup" && 
                                    !dismissedGuidedMemberIds.contains($0.id.uuidString)
                            }
                            if !guidedMembers.isEmpty {
                                GuidedSetupStatusCard(
                                    members: guidedMembers,
                                familyName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
                                onDismiss: { memberId in
                                    dismissedGuidedMemberIds.insert(memberId)
                                    if let uid = currentUserIdString {
                                        persistDismissedGuidedMembers(for: uid)
                                    }
                                }
                            ) { member, action in
                                handleGuidedStatusAction(member: member, action: action)
                                }
                            }
                        }

                        // Notifications / Patterns (family insights)
                        // Only show after trend computation completes to avoid flashing stale insights
                        if let snapshot = familySnapshot, familyVitalityScore != nil, !isComputingTrendInsights {
                            let trendNotifications = FamilyNotificationItem.build(
                                snapshot: snapshot,
                                trendInsights: trendInsights,
                                trendCoverage: trendCoverage,
                                factors: vitalityFactors,
                                members: familyMembers
                            ).filter { item in
                                // Filter out "celebrate" trends if we have server alerts
                                if case .trend(let insight) = item.kind {
                                    return insight.severity != .celebrate
                                }
                                return true
                            }
                            
                            // Prefer server alerts, fallback to trend insights
                            let notifications = serverPatternAlerts.isEmpty ? trendNotifications : serverPatternAlerts
                            
                            if !notifications.isEmpty {
                                FamilyNotificationsCard(items: notifications.prefix(3).map { $0 }) { item in
                                    selectedFamilyNotification = item
                                }
                            }
                        }

                        // Chat with Arlo card (primary button style)
                        ChatWithArloCard()

                        // Family vitality score (family-level gauge)
                        if isLoadingFamilyVitality {
                            FamilyVitalityLoadingCard()
                        } else if let score = familyVitalityScore {
                        FamilyVitalityCard(
                                score: score,
                                label: vitalityLabel(for: score),
                                factors: vitalityFactors,
                                includedMembersText: {
                                    if let withData = familyVitalityMembersWithData, let total = familyVitalityMembersTotal {
                                        return "Included members: \(withData)/\(total)"
                                    }
                                    return nil
                                }(),
                                progressScore: familyVitalityProgressScore
                        ) { tappedFactor in
                            selectedFactor = tappedFactor
                            }
                        } else {
                            FamilyVitalityPlaceholderCard()
                        }

                        // Champions (Daily + Weekly)
                        // Always render (with an empty state) so the section doesn't "disappear" during testing.
                        FamilyBadgesCard(
                            daily: dailyBadgeWinners,
                            weekly: weeklyBadgeWinners,
                            weekStart: weeklyBadgeWeekStart,
                            weekEnd: weeklyBadgeWeekEnd
                        )

                        // PERSONAL VITALITY (current user) — simple current/optimal with optional submetrics
                        if let me = familyMembers.first(where: { $0.isMe }) {
                            PersonalVitalityCard(currentUser: me, factors: vitalityFactors)
                        }


                        Spacer(minLength: DashboardDesign.sectionSpacing)
                    }
                    .padding(EdgeInsets(
                        top: DashboardDesign.internalSpacing,
                        leading: DashboardDesign.cardPadding,
                        bottom: DashboardDesign.sectionSpacing,
                        trailing: DashboardDesign.cardPadding
                    ))
                }
                .refreshable {
                    // Avoid overlapping refresh calls that can trigger cancellation
                    if isLoadingFamilyMembers || isLoadingFamilyVitality {
                        print("ℹ️ Dashboard: refresh skipped (already loading)")
                        return
                    }
                    await loadFamilyMembers()
                    await loadFamilyVitality()
                    familyMembersRefreshID = UUID()
                    await computeAndStoreFamilySnapshot()
                    await computeTrendInsights()
                    await loadServerPatternAlerts()
                    await computeFamilyBadgesIfNeeded()
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
                NotificationPanel(onClose: {
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
                    SidebarMenu(
                        isVisible: $showSidebar,
                        isInviteMemberSheetPresented: $isInviteMemberSheetPresented,
                        familyMemberRecords: familyMemberRecords,
                        currentUserId: currentUserIdString,
                        familyDisplayName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
                        onReloadMembers: {
                            Task { await loadFamilyMembers() }
                        },
                        onUpdateResolvedFamilyName: { newName in
                            resolvedFamilyName = newName
                        }
                    )
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
        .sheet(isPresented: $isInviteMemberSheetPresented) {
            NavigationStack {
                FamilyMembersInviteView(isPresentedFromDashboard: true)
                    .environmentObject(onboardingManager)
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ActivityView(activityItems: [shareText])
        }
        .sheet(item: $selectedFamilyNotification) { item in
            FamilyNotificationDetailSheet(
                item: item,
                onStartRecommendedChallenge: {
                    // Challenge feature removed
                }
            )
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugUpload) {
            NavigationStack {
                DebugUploadPickerView(members: familyMembers)
                .environmentObject(onboardingManager)
                .environmentObject(dataManager)
            }
        }
        .onChange(of: isShowingDebugUpload) { isPresented in
            // After a debug upload finishes and the sheet is dismissed, refresh dashboard data
            // so new daily vitality rows + notifications appear immediately.
            guard !isPresented else { return }
            Task {
                #if DEBUG
                print("DEBUG_UPLOAD: sheet dismissed → refreshing family + trends")
                #endif
                await loadFamilyMembers()
                await loadFamilyVitality()
                familyMembersRefreshID = UUID()
                await computeAndStoreFamilySnapshot()
                await computeTrendInsights()
                await loadServerPatternAlerts()
                await computeFamilyBadgesIfNeeded()
            }
        }
        .sheet(isPresented: $isShowingDebugAddRecord) {
            NavigationStack {
                DebugAddRecordView(members: familyMembers)
                    .environmentObject(dataManager)
            }
        }
        #endif
        .onChange(of: isShowingDebugAddRecord) { isPresented in
            guard !isPresented else { return }
            Task {
                #if DEBUG
                print("DEBUG_ADD_RECORD: sheet dismissed → refreshing family + trends")
                #endif
                await loadFamilyMembers()
                await loadFamilyVitality()
                familyMembersRefreshID = UUID()
                await computeAndStoreFamilySnapshot()
                await computeTrendInsights()
                await loadServerPatternAlerts()
                await computeFamilyBadgesIfNeeded()
            }
        }
        .task {
            print("DashboardView .task started")
            loadFamilyName()
            currentUserIdString = await dataManager.currentUserIdString
            if let uid = currentUserIdString {
                loadDismissedGuidedMembers(for: uid)
            }
            await dataManager.clearFamilyCachesIfAuthChanged()
            await loadFamilyMembers()
            await loadFamilyVitality()
            await computeAndStoreFamilySnapshot()
            await computeTrendInsights()
            await loadServerPatternAlerts()
            await computeFamilyBadgesIfNeeded()
            print("DashboardView .task finished, familyVitalityScore=\(String(describing: familyVitalityScore))")
        }
    } // 👈 END OF `var body: some View`
    // MARK: - Share text builder

    private func prepareShareText() {
        let sleep = vitalityFactors.first(where: { $0.name == "Sleep" })?.percent
        let activity = vitalityFactors.first(where: { $0.name == "Activity" })?.percent
        let stress = vitalityFactors.first(where: { $0.name == "Stress" })?.percent

        let familyScoreText: String = {
            if let score = familyVitalityScore { return "\(score)/100" }
            return "N/A"
        }()

        shareText = """
        Our Family Vitality Score this week: \(familyScoreText)

        Sleep: \(sleep.map(String.init) ?? "N/A")
        Activity: \(activity.map(String.init) ?? "N/A")
        Stress: \(stress.map(String.init) ?? "N/A")

        One family. One mission.
        Shared from Miya Health.
        """
    }

    // MARK: - Badges (Daily computed; Weekly persisted)
    
    private func utcDayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    private func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date) ?? date
    }
    
    private func computeFamilyBadgesIfNeeded() async {
        guard let familyId = dataManager.currentFamilyId else { return }
        
        // Build member list (exclude pending and missing user ids)
        let members: [BadgeEngine.Member] = familyMembers.compactMap { m in
            guard !m.isPending, let uid = m.userId else { return nil }
            return BadgeEngine.Member(userId: uid, name: m.name)
        }
        guard !members.isEmpty else { return }
        
        let today = Date()
        let todayKey = utcDayKey(for: today)
        
        // Week window: last 7 days INCLUDING today (not ending yesterday)
        // This ensures data uploaded for "today" is included in weekly badge calculations
        let weekEndDate = today
        let weekStartDate = dateByAddingDays(-6, to: weekEndDate)
        let weekEndKey = utcDayKey(for: weekEndDate)
        let weekStartKey = utcDayKey(for: weekStartDate)
        
        // Previous week: 7 days before this week
        let prevEndDate = dateByAddingDays(-1, to: weekStartDate)
        let prevStartDate = dateByAddingDays(-6, to: prevEndDate)
        let prevEndKey = utcDayKey(for: prevEndDate)
        let prevStartKey = utcDayKey(for: prevStartDate)
        
        weeklyBadgeWeekStart = weekStartKey
        weeklyBadgeWeekEnd = weekEndKey
        
        // Fetch score rows for prevStart..todayKey (covers prev week, this week, and today).
        // Primary path: RPC `get_family_vitality_scores`.
        // Fallback path (debug/robustness): per-user queries if RPC isn't deployed yet.
        // Handle cancellations gracefully - don't clear badges if request was cancelled.
        let scoreRows: [DataManager.FamilyVitalityScoreRow]
        do {
            scoreRows = try await dataManager.fetchFamilyVitalityScores(
                familyId: familyId,
                startDate: prevStartKey,
                endDate: todayKey
            )
        } catch {
            // Check if this is a cancellation - if so, preserve existing badges and return early
            let errorDesc = error.localizedDescription.lowercased()
            if error is CancellationError ||
               (error as? URLError)?.code == .cancelled ||
               errorDesc.contains("cancelled") {
                #if DEBUG
                print("ℹ️ Champions: Badge fetch cancelled; preserving existing badges")
                #endif
                return // Don't clear badges on cancellation
            }
            
            #if DEBUG
            print("❌ Champions: fetchFamilyVitalityScores RPC failed; falling back to per-user reads. error=\(error.localizedDescription)")
            #endif
            do {
                scoreRows = try await dataManager.fetchFamilyVitalityScoresFallbackByUserIds(
                    userIds: members.map(\.userId),
                    startDate: prevStartKey,
                    endDate: todayKey
                )
            } catch {
                // Also check cancellation in fallback
                let fallbackErrorDesc = error.localizedDescription.lowercased()
                if error is CancellationError ||
                   (error as? URLError)?.code == .cancelled ||
                   fallbackErrorDesc.contains("cancelled") {
                    #if DEBUG
                    print("ℹ️ Champions: Badge fallback fetch cancelled; preserving existing badges")
                    #endif
                    return // Don't clear badges on cancellation
                }
                #if DEBUG
                print("❌ Champions: Fallback also failed: \(error.localizedDescription)")
                #endif
                scoreRows = []
            }
        }
        
        let mapped: [BadgeEngine.ScoreRow] = scoreRows.map { r in
            BadgeEngine.ScoreRow(
                userId: r.userId,
                dayKey: r.scoreDate,
                total: r.totalScore,
                sleep: r.sleepPillar,
                movement: r.movementPillar,
                stress: r.stressPillar
            )
        }
        
        // Filter out future dates (data should only include dates up to today)
        let validMapped = mapped.filter { $0.dayKey <= todayKey }
        
        // Daily badges (computed from today vs yesterday - percentage increase)
        let todayRows = validMapped.filter { $0.dayKey == todayKey }
        let yesterdayKey = utcDayKey(for: dateByAddingDays(-1, to: today))
        let yesterdayRows = validMapped.filter { $0.dayKey == yesterdayKey }
        dailyBadgeWinners = BadgeEngine.computeDailyBadges(members: members, todayRows: todayRows, yesterdayRows: yesterdayRows)
        
        // Weekly badges: try read persisted for this week first.
        // If the table doesn't exist yet, skip persistence gracefully and just compute on read.
        let persisted: [DataManager.FamilyBadgeRow]
        do {
            persisted = try await dataManager.fetchFamilyBadges(familyId: familyId, weekStart: weekStartKey)
        } catch {
            // Check if this is a cancellation - if so, preserve existing badges and return early
            let errorDesc = error.localizedDescription.lowercased()
            if error is CancellationError ||
               (error as? URLError)?.code == .cancelled ||
               errorDesc.contains("cancelled") {
                #if DEBUG
                print("ℹ️ Champions: Badge persistence fetch cancelled; preserving existing badges")
                #endif
                return // Don't clear badges on cancellation
            }
            #if DEBUG
            print("❌ Champions: fetchFamilyBadges failed; proceeding with computed weekly winners only. error=\(error.localizedDescription)")
            #endif
            persisted = []
        }
        
        let nameByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId.lowercased(), $0.name) })
        func winnersFromPersisted(_ rows: [DataManager.FamilyBadgeRow]) -> [BadgeEngine.Winner] {
            rows.map { row in
                var meta: [String: Any] = [:]
                if let m = row.metadata {
                    for (k, v) in m {
                        switch v {
                        case .string(let s):
                            meta[k] = s
                        case .integer(let i):
                            meta[k] = i
                        case .double(let d):
                            meta[k] = d
                        case .bool(let b):
                            meta[k] = b
                        default:
                            break
                        }
                    }
                }
                return BadgeEngine.Winner(
                    badgeType: row.badgeType,
                    winnerUserId: row.winnerUserId.lowercased(),
                    winnerName: nameByUserId[row.winnerUserId.lowercased()] ?? "Member",
                    metadata: meta
                )
            }
        }
        
        if persisted.count >= BadgeEngine.WeeklyBadgeType.allCases.count {
            weeklyBadgeWinners = winnersFromPersisted(persisted)
            return
        }
        
        // Compute weekly winners (this week + prev week + last 14 days ending weekEndKey)
        // Use validMapped (filtered to exclude future dates)
        let thisWeekRows = validMapped.filter { $0.dayKey >= weekStartKey && $0.dayKey <= weekEndKey }
        let prevWeekRows = validMapped.filter { $0.dayKey >= prevStartKey && $0.dayKey <= prevEndKey }
        let last14StartKey = utcDayKey(for: dateByAddingDays(-13, to: weekEndDate))
        let last14Rows = validMapped.filter { $0.dayKey >= last14StartKey && $0.dayKey <= weekEndKey }
        
        #if DEBUG
        print("🏆 BadgeEngine: Week window: \(weekStartKey) to \(weekEndKey) (today: \(todayKey))")
        print("🏆 BadgeEngine: Total rows fetched: \(scoreRows.count), Valid (not future): \(validMapped.count)")
        print("🏆 BadgeEngine: This week rows: \(thisWeekRows.count), Prev week rows: \(prevWeekRows.count), Last 14 rows: \(last14Rows.count)")
        if !thisWeekRows.isEmpty {
            let dates = thisWeekRows.map { $0.dayKey }.sorted()
            print("🏆 BadgeEngine: This week dates: \(dates.joined(separator: ", "))")
        }
        #endif
        
        let computedWinners = BadgeEngine.computeWeeklyBadges(
            members: members,
            thisWeekRows: thisWeekRows,
            prevWeekRows: prevWeekRows,
            last14Rows: last14Rows
        )
        
        #if DEBUG
        print("🏆 BadgeEngine: Computed \(computedWinners.count) weekly winners")
        #endif
        
        weeklyBadgeWinners = computedWinners
        
        // Persist if caller is admin/superadmin AND we have something to persist.
        if let uid = currentUserIdString,
           let myMembership = familyMemberRecords.first(where: { $0.userId?.uuidString == uid }),
           (myMembership.role == "admin" || myMembership.role == "superadmin"),
           !computedWinners.isEmpty {
            try? await dataManager.upsertFamilyBadges(
                familyId: familyId,
                weekStart: weekStartKey,
                weekEnd: weekEndKey,
                winners: computedWinners
            )
        }
    }
    
    // MARK: - Data loading
    private func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.dropFirst().first?.prefix(1) ?? ""
        let combined = first + second
        return combined.isEmpty ? "?" : combined.uppercased()
    }
    
    private func loadFamilyName() {
        if let fname = dataManager.familyName, !fname.isEmpty {
            resolvedFamilyName = fname
        } else {
            resolvedFamilyName = familyName
        }
    }
    
    private func membersDisplayString() -> String {
        let memberNames = familyMemberRecords.map { record in
            if record.userId?.uuidString == currentUserIdString {
                return "\(record.firstName) (you)"
            } else {
                return record.firstName
            }
        }
        return memberNames.joined(separator: ", ")
    }
    
    private func vitalityLabel(for score: Int) -> String {
        switch score {
        case 80...100: return "Great week"
        case 60..<80: return "Good week"
        case 40..<60: return "Needs attention"
        default: return "Let's improve"
        }
    }
    
    private func loadFamilyMembers() async {
        await MainActor.run {
            isLoadingFamilyMembers = true
        }
        defer {
            Task { @MainActor in
                isLoadingFamilyMembers = false
            }
        }

        var familyId = dataManager.currentFamilyId
        if familyId == nil {
            do {
                try await dataManager.fetchFamilyData()
                familyId = dataManager.currentFamilyId
            } catch {
                print("⚠️ Dashboard: Failed to fetch family data: \(error.localizedDescription)")
            }
        }
        
        guard let fid = familyId else {
            print("⚠️ Dashboard: No familyId available; showing placeholder members")
            return
        }
        
        do {
            let records = try await dataManager.fetchFamilyMembers(familyId: fid)
            await MainActor.run {
                familyMemberRecords = records
            }

            // Fetch per-member vitality + optimal scores from user_profiles.
            // NOTE: We intentionally do NOT rely on embedded joins from family_members -> user_profiles because
            // PostgREST requires a direct FK relationship for embedding, and family_members.user_id references auth.users.
            struct VitalityProfileRow: Decodable {
                let user_id: String?
                let vitality_score_current: Int?
                let vitality_score_updated_at: String?
                let optimal_vitality_target: Int?
                let vitality_progress_score_current: Int?
                let vitality_sleep_pillar_score: Int?
                let vitality_movement_pillar_score: Int?
                let vitality_stress_pillar_score: Int?
            }
            
            // Fallback struct for when migration hasn't run (column doesn't exist yet)
            struct VitalityProfileRowLegacy: Decodable {
                let user_id: String?
                let vitality_score_current: Int?
                let vitality_score_updated_at: String?
                let optimal_vitality_target: Int?
                let vitality_sleep_pillar_score: Int?
                let vitality_movement_pillar_score: Int?
                let vitality_stress_pillar_score: Int?
            }
            
            let supabase = SupabaseConfig.client
            var profileByUserId: [String: VitalityProfileRow] = [:]
            do {
                let userIds = records.compactMap { $0.userId?.uuidString }
                if userIds.isEmpty {
                    print("⚠️ Dashboard: No member user_ids found; skipping user_profiles vitality fetch.")
                } else {
                    print("🔍 Dashboard: Fetching user_profiles for \(userIds.count) user_ids: \(userIds.prefix(3).joined(separator: ", "))...")
                    
                    // Query each user individually and combine (most reliable approach)
                    // This avoids .or()/.in() syntax issues with Supabase Swift client
                    var allProfiles: [VitalityProfileRow] = []
                    for userId in userIds {
                        do {
                            // Try with new progress_score column first (if migration has run)
                            let userProfiles: [VitalityProfileRow] = try await supabase
                                .from("user_profiles")
                                .select("user_id, vitality_score_current, vitality_score_updated_at, optimal_vitality_target, vitality_progress_score_current, vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score")
                                .eq("user_id", value: userId)
                                .limit(1)
                                .execute()
                                .value
                            allProfiles.append(contentsOf: userProfiles)
                        } catch {
                            // Fallback: if new column doesn't exist (migration not run), try without it
                            let errorStr = error.localizedDescription.lowercased()
                            if errorStr.contains("vitality_progress_score_current") || errorStr.contains("does not exist") {
                                do {
                                    let legacyProfiles: [VitalityProfileRowLegacy] = try await supabase
                                        .from("user_profiles")
                                        .select("user_id, vitality_score_current, vitality_score_updated_at, optimal_vitality_target, vitality_sleep_pillar_score, vitality_movement_pillar_score, vitality_stress_pillar_score")
                                        .eq("user_id", value: userId)
                                        .limit(1)
                                        .execute()
                                        .value
                                    // Map to VitalityProfileRow with nil progress_score
                                    allProfiles.append(contentsOf: legacyProfiles.map { p in
                                        VitalityProfileRow(
                                            user_id: p.user_id,
                                            vitality_score_current: p.vitality_score_current,
                                            vitality_score_updated_at: p.vitality_score_updated_at,
                                            optimal_vitality_target: p.optimal_vitality_target,
                                            vitality_progress_score_current: nil,
                                            vitality_sleep_pillar_score: p.vitality_sleep_pillar_score,
                                            vitality_movement_pillar_score: p.vitality_movement_pillar_score,
                                            vitality_stress_pillar_score: p.vitality_stress_pillar_score
                                        )
                                    })
                                } catch {
                                    print("⚠️ Dashboard: Failed to fetch profile for user_id=\(userId) (fallback): \(error.localizedDescription)")
                                }
                            } else {
                            print("⚠️ Dashboard: Failed to fetch profile for user_id=\(userId): \(error.localizedDescription)")
                            }
                        }
                    }
                    let profiles = allProfiles
                    
                    print("✅ Dashboard: Loaded \(profiles.count) user_profiles rows for family members (expected \(userIds.count))")
                    if profiles.isEmpty {
                        print("⚠️ Dashboard: Query returned 0 rows. Debugging:")
                        print("  - User IDs queried: \(userIds)")
                        print("  - This might indicate: RLS blocking, wrong table name, or user_ids don't match user_profiles.user_id")
                    }
                    for p in profiles {
                        if let uid = p.user_id {
                            let key = uid.lowercased()
                            profileByUserId[key] = p
                            print("  📊 Profile loaded: user_id=\(uid) current=\(p.vitality_score_current ?? -1) optimal=\(p.optimal_vitality_target ?? -1)")
                        } else {
                            print("  ⚠️ Profile row missing user_id: current=\(p.vitality_score_current ?? -1) optimal=\(p.optimal_vitality_target ?? -1)")
                        }
                    }
                }
            } catch {
                // Best-effort: still render members strip even if profiles can't be loaded.
                print("❌ Dashboard: Failed to load user_profiles vitality for family \(fid): \(error)")
                print("❌ Dashboard: Error details: \(error.localizedDescription)")
            }

            // Freshness cutoff (match RPC semantics: now - 3 days)
            let freshCutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            func parseISODate(_ s: String?) -> Date? {
                guard let s else { return nil }
                return isoFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
            }

            let membersTotal = records.count
            let membersWithUserId = records.filter { $0.userId != nil }.count
            let profilesLoaded = profileByUserId.count

            let mapped: [FamilyMemberScore] = records.map { rec in
                let name = rec.firstName
                let uid = rec.userId?.uuidString
                let isMe = (uid != nil && uid == currentUserIdString)
                let profile = uid.flatMap { profileByUserId[$0.lowercased()] }

                // Normalize invalid / missing scores.
                let rawCurrent = profile?.vitality_score_current
                let hasValidCurrent = (rawCurrent != nil && (rawCurrent ?? -1) >= 0)
                let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)

                // Optimal is meaningful only if present and > 0.
                let rawOptimal = profile?.optimal_vitality_target
                let hasValidOptimal = (rawOptimal != nil && (rawOptimal ?? 0) > 0)

                // Only treat as "hasScore" if we have a real userId + a matching profile row + a valid current score.
                let hasScore = (uid != nil && profile != nil && hasValidCurrent)
                let isScoreFresh = (hasScore && isFresh)
                let isStale = (hasScore && !isFresh)

                // UI values:
                // - Fresh: show current + optimal
                // - Stale (hasScore but not fresh): KEEP last-known current + optimal for display (greyed ring),
                //   but still exclude from family insights/calcs via isScoreFresh gating.
                // - Missing/invalid: show 0/0 for neutral empty state.
                let currentScoreForUI = (hasScore ? (rawCurrent ?? 0) : 0)
                let optimalScoreForUI = (hasScore && hasValidOptimal ? (rawOptimal ?? 0) : 0)
                let progressScoreForUI: Int? = {
                    guard hasScore else { return nil }
                    // Allow 0..100; nil if missing.
                    if let p = profile?.vitality_progress_score_current, p >= 0 { return p }
                    return nil
                }()

                let updatedAtRaw = profile?.vitality_score_updated_at ?? "nil"
                let ageHours: Double? = updatedAt.map { Date().timeIntervalSince($0) / 3600.0 }
                let ageDays: Double? = ageHours.map { $0 / 24.0 }
                let ageText: String = {
                    guard let ageHours else { return "nil" }
                    return String(format: "%.1fh (%.2fd)", ageHours, (ageDays ?? 0))
                }()
                print("Dashboard member vitality: name=\(name) user_id=\(uid ?? "nil") hasScore=\(hasScore) fresh=\(isScoreFresh) stale=\(isStale) current=\(currentScoreForUI) optimal=\(optimalScoreForUI) progress=\(progressScoreForUI.map(String.init) ?? "nil") updated_at=\(updatedAtRaw) age=\(ageText)")

                return FamilyMemberScore(
                    name: name,
                    initials: makeInitials(from: name),
                    userId: uid,
                    hasScore: hasScore,
                    isScoreFresh: isScoreFresh,
                    isStale: isStale,
                    currentScore: currentScoreForUI,
                    optimalScore: optimalScoreForUI,
                    progressScore: progressScoreForUI,
                    inviteStatus: rec.inviteStatus,
                    onboardingType: rec.onboardingType,
                    guidedSetupStatus: rec.guidedSetupStatus,
                    isMe: isMe
                )
            }

            let activeFreshWithScores = mapped.filter { !$0.isPending && $0.hasScore && $0.isScoreFresh && $0.optimalScore > 0 }.count
            let staleOrMissing = mapped.filter { $0.isPending || !$0.hasScore || !$0.isScoreFresh || $0.optimalScore <= 0 }.count
            print("DashboardCounts: membersTotal=\(membersTotal) profilesLoaded=\(profilesLoaded) membersWithUserId=\(membersWithUserId) activeFreshWithScores=\(activeFreshWithScores) staleOrMissing=\(staleOrMissing)")
            
            // Ensure the authenticated user appears first and is labeled "Me" in the strip.
            let ordered: [FamilyMemberScore] = {
                let me = mapped.filter { $0.isMe }
                let others = mapped.filter { !$0.isMe }
                return me + others
            }()

            // Build family-level pillar factors from per-user pillar snapshots (no mock/placeholder values).
            func avgPercent(_ values: [Int?]) -> Int? {
                let xs = values.compactMap { $0 }
                guard !xs.isEmpty else { return nil }
                let mean = Double(xs.reduce(0, +)) / Double(xs.count)
                return Int(mean.rounded())
            }

            func memberScoresForPillar(_ getter: (VitalityProfileRow) -> Int?) -> [FamilyMemberScore] {
                return records.map { rec in
                    let name = rec.firstName
                    let uid = rec.userId?.uuidString
                    let isMe = (uid != nil && uid == currentUserIdString)
                    let profile = uid.flatMap { profileByUserId[$0.lowercased()] }
                    let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                    let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)
                    let pillar = profile.flatMap(getter)
                    let hasPillar = (uid != nil && profile != nil && pillar != nil && (pillar ?? -1) >= 0)
                    let isPillarFresh = (hasPillar && isFresh)
                    let isPillarStale = (hasPillar && !isFresh)
                    return FamilyMemberScore(
                        name: name,
                        initials: makeInitials(from: name),
                        userId: uid,
                        hasScore: hasPillar,
                        isScoreFresh: isPillarFresh,
                        isStale: isPillarStale,
                        currentScore: (hasPillar ? (pillar ?? 0) : 0),
                        optimalScore: 0,
                        progressScore: nil,
                        inviteStatus: rec.inviteStatus,
                        onboardingType: rec.onboardingType,
                        guidedSetupStatus: rec.guidedSetupStatus,
                        isMe: isMe
                    )
                }
            }

            // Pillar averages should align with "fresh score" gating so coaching surfaces don't include stale/missing data.
            let sleepAvg = avgPercent(records.compactMap { rec in
                guard let uid = rec.userId?.uuidString else { return nil }
                let profile = profileByUserId[uid.lowercased()]
                let rawCurrent = profile?.vitality_score_current
                let hasValidCurrent = (rawCurrent != nil && (rawCurrent ?? -1) >= 0)
                let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)
                guard hasValidCurrent && isFresh else { return nil }
                return profile?.vitality_sleep_pillar_score
            })
            let movementAvg = avgPercent(records.compactMap { rec in
                guard let uid = rec.userId?.uuidString else { return nil }
                let profile = profileByUserId[uid.lowercased()]
                let rawCurrent = profile?.vitality_score_current
                let hasValidCurrent = (rawCurrent != nil && (rawCurrent ?? -1) >= 0)
                let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)
                guard hasValidCurrent && isFresh else { return nil }
                return profile?.vitality_movement_pillar_score
            })
            let stressAvg = avgPercent(records.compactMap { rec in
                guard let uid = rec.userId?.uuidString else { return nil }
                let profile = profileByUserId[uid.lowercased()]
                let rawCurrent = profile?.vitality_score_current
                let hasValidCurrent = (rawCurrent != nil && (rawCurrent ?? -1) >= 0)
                let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)
                guard hasValidCurrent && isFresh else { return nil }
                return profile?.vitality_stress_pillar_score
            })

            var factors: [VitalityFactor] = []
            if let sleepAvg {
                factors.append(
                    VitalityFactor(
                        name: "Sleep",
                        iconName: "bed.double.fill",
                        percent: sleepAvg,
                        description: "Your family's sleep pillar reflects duration, efficiency, and consistency.",
                        actionPlan: ["Keep a consistent bedtime", "Aim for a wind-down routine"],
                        memberScores: memberScoresForPillar { $0.vitality_sleep_pillar_score }
                    )
                )
            }
            if let movementAvg {
                factors.append(
                    VitalityFactor(
                        name: "Activity",
                        iconName: "figure.walk",
                        percent: movementAvg,
                        description: "Your family's activity pillar reflects daily movement and energy.",
                        actionPlan: ["Take a short walk today", "Add movement breaks"],
                        memberScores: memberScoresForPillar { $0.vitality_movement_pillar_score }
                    )
                )
            }
            if let stressAvg {
                factors.append(
                    VitalityFactor(
                        name: "Stress",
                        iconName: "exclamationmark.circle",
                        percent: stressAvg,
                        description: "Your family's stress pillar reflects recovery signals like HRV and resting heart rate.",
                        actionPlan: ["Try a short breathing exercise", "Prioritize recovery"],
                        memberScores: memberScoresForPillar { $0.vitality_stress_pillar_score }
                    )
                )
            }

            await MainActor.run {
                familyMembers = ordered
                vitalityFactors = factors
                loadFamilyName()
            }
        } catch {
            // SwiftUI refreshes / view transitions can cancel in-flight tasks.
            // Cancellation can come through as CancellationError, URLError with cancelled code, or wrapped in error messages.
            // Do not treat cancellation as a failure; keep last-known good UI state (don't overwrite familyMembers).
            let errorDesc = error.localizedDescription.lowercased()
            if error is CancellationError || 
               (error as? URLError)?.code == .cancelled ||
               errorDesc.contains("cancelled") || 
               errorDesc.contains("cancel") {
                print("ℹ️ Dashboard: loadFamilyMembers cancelled (type: \(type(of: error)))")
                return
            }
            
            // Real error (not cancellation): show fallback UI but only if we have partial data
            print("⚠️ Dashboard: Failed to load family members: \(error.localizedDescription)")
            await MainActor.run {
                // Only create fallback members if we have familyMemberRecords but failed to get profiles.
                // If fetchFamilyMembers itself failed, familyMemberRecords is empty and we should keep existing UI.
                if !familyMemberRecords.isEmpty {
                    // Best-effort: show member strip with names even if vitality fetch fails.
                    familyMembers = familyMemberRecords.map { rec in
                    let name = rec.firstName
                    let uid = rec.userId?.uuidString
                    let isMe = (uid != nil && uid == currentUserIdString)
                    return FamilyMemberScore(
                        name: name,
                        initials: makeInitials(from: name),
                        userId: uid,
                        hasScore: false,
                        isScoreFresh: false,
                        isStale: false,
                        currentScore: 0,
                        optimalScore: 0,
                        progressScore: nil,
                        inviteStatus: rec.inviteStatus,
                        onboardingType: rec.onboardingType,
                        guidedSetupStatus: rec.guidedSetupStatus,
                        isMe: isMe
                    )
                    }
                }
                loadFamilyName()
            }
        }
    }

    private func loadFamilyVitality() async {
        print("loadFamilyVitality() called")
        await MainActor.run {
            isLoadingFamilyVitality = true
            familyVitalityErrorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoadingFamilyVitality = false
            }
        }
        
        do {
            let summary = try await dataManager.fetchFamilyVitalitySummary()
            let familyUUID = dataManager.currentFamilyId.flatMap(UUID.init(uuidString:))
            
            if let score = summary.score {
                print("FamilyVitality: familyId=\(familyUUID?.uuidString ?? "nil") score=\(score)")
            } else {
                print("FamilyVitality: familyId=\(familyUUID?.uuidString ?? "nil") — no members with vitality_score_current, score=nil")
            }
            print("loadFamilyVitality() success, score=\(String(describing: summary.score)) membersWithData=\(summary.membersWithData) membersTotal=\(summary.membersTotal)")
            
            await MainActor.run {
                familyVitalityScore = summary.score
                familyVitalityProgressScore = summary.progressScore
                familyVitalityMembersWithData = summary.membersWithData
                familyVitalityMembersTotal = summary.membersTotal
            }
        } catch {
            // Preserve last-known good state on cancellation
            let errorDesc = error.localizedDescription.lowercased()
            if error is CancellationError ||
               (error as? URLError)?.code == .cancelled ||
               errorDesc.contains("cancelled") ||
               errorDesc.contains("cancel") {
                print("ℹ️ Dashboard: loadFamilyVitality cancelled (type: \(type(of: error)))")
                return
            }
            await MainActor.run {
                familyVitalityScore = nil
                familyVitalityProgressScore = nil
                familyVitalityMembersWithData = nil
                familyVitalityMembersTotal = nil
                familyVitalityErrorMessage = error.localizedDescription
            }
            print("FamilyVitality ERROR: \(error.localizedDescription)")
            print("loadFamilyVitality() caught error: \(error)")
        }
    }

    private func computeAndStoreFamilySnapshot() async {
        await MainActor.run {
            // Build pillar averages from the already-computed vitalityFactors (snapshot data only).
            var pillarAverages: [VitalityPillar: Int] = [:]
            for factor in vitalityFactors {
                switch factor.name.lowercased() {
                case "sleep":
                    pillarAverages[.sleep] = factor.percent
                case "activity":
                    pillarAverages[.movement] = factor.percent
                case "stress":
                    pillarAverages[.stress] = factor.percent
                default:
                    break
                }
            }
            
            // Exclude current user from family insights to avoid seeing yourself as "needs help"
            let others = familyMembers.filter { !$0.isMe }
            let total = familyVitalityMembersTotal ?? others.count
            let snapshot = FamilyVitalitySnapshotEngine.compute(
                members: others,
                familyAverage: familyVitalityScore,
                pillarAverages: pillarAverages,
                membersTotal: total
            )
            familySnapshot = snapshot
            
            let focus = snapshot.focusPillar?.displayName ?? "nil"
            let strength = snapshot.strengthPillar?.displayName ?? "nil"
            print("FamilySnapshot: state=\(snapshot.familyStateLabel.rawValue) alignment=\(snapshot.alignmentLevel.rawValue) focus=\(focus) strength=\(strength) support=\(snapshot.supportMembers.count) celebrate=\(snapshot.celebrateMembers.count) helpCards=\(snapshot.helpCards.count)")
        }
    }
    
    /// Load server pattern alerts from the database into state
    private func loadServerPatternAlerts() async {
        let alerts = await fetchServerPatternAlerts()
        await MainActor.run {
            serverPatternAlerts = alerts
        }
    }
    
    /// Fetch server pattern alerts from the database
    private func fetchServerPatternAlerts() async -> [FamilyNotificationItem] {
        do {
            let supabase = SupabaseConfig.client
            
            // Require familyId to scope alerts
            guard let familyId = dataManager.currentFamilyId else {
                print("❌ Dashboard: No familyId available for get_family_pattern_alerts")
                return []
            }
            
            // Call the get_family_pattern_alerts RPC
            struct AlertRow: Decodable {
                let id: String
                let member_user_id: String
                let metric_type: String
                let pattern_type: String?
                let episode_status: String
                let active_since: String?
                let current_level: Int
                let severity: String?
                let deviation_percent: Double?
                let baseline_value: Double?
                let recent_value: Double?
            }
            
            let rows: [AlertRow] = try await supabase
                .rpc("get_family_pattern_alerts", params: ["family_id": AnyJSON.string(familyId)])
                .execute()
                .value
            
            print("🔔 Dashboard: Found \(rows.count) active server pattern alerts")
            
            var items: [FamilyNotificationItem] = []
            
            for row in rows {
                // Find member name
                guard let member = familyMembers.first(where: { $0.userId?.lowercased() == row.member_user_id.lowercased() }) else {
                    continue
                }
                
                // Map metric to pillar
                let pillar: VitalityPillar
                switch row.metric_type.lowercased() {
                case "steps":
                    pillar = .movement
                case "sleep_minutes":
                    pillar = .sleep
                case "hrv_ms", "resting_hr":
                    pillar = .stress
                default:
                    continue
                }
                
                // Build title and body
                let metricDisplay: String
                switch row.metric_type {
                case "steps": metricDisplay = "Movement"
                case "sleep_minutes": metricDisplay = "Sleep"
                case "hrv_ms": metricDisplay = "HRV"
                case "resting_hr": metricDisplay = "Resting HR"
                default: metricDisplay = row.metric_type
                }
                
                let patternDesc = row.pattern_type?.contains("rise") == true ? "above" : "below"
                let levelDesc = "\(row.current_level)d"
                
                let title = "\(metricDisplay) \(patternDesc) baseline"
                let deviationText = row.deviation_percent.map { String(format: "%.0f%%", abs($0 * 100)) } ?? ""
                let body = deviationText.isEmpty ? 
                    "\(metricDisplay) has been \(patternDesc) \(member.name)'s baseline for \(levelDesc)." :
                    "\(metricDisplay) is \(deviationText) \(patternDesc) \(member.name)'s baseline (last \(levelDesc))."
                
                // Create a TrendInsight to store the server pattern data with debugWhy
                let debugWhy = "serverPattern metric=\(row.metric_type) pattern=\(row.pattern_type ?? "unknown") level=\(row.current_level) severity=\(row.severity ?? "watch") deviation=\(row.deviation_percent ?? 0) alertStateId=\(row.id) activeSince=\(row.active_since ?? "unknown")"
                
                let insight = TrendInsight(
                    memberName: member.name,
                    memberUserId: row.member_user_id,
                    pillar: pillar,
                    severity: row.severity == "critical" ? .attention : (row.severity == "attention" ? .attention : .watch),
                    title: title,
                    body: body,
                    debugWhy: debugWhy,
                    windowDays: 21,
                    requiredDays: 7,
                    missingDays: 0,
                    confidence: 1.0
                )
                
                let item = FamilyNotificationItem(
                    id: row.id,
                    kind: .trend(insight),
                    pillar: pillar,
                    title: title,
                    body: body,
                    memberInitials: member.initials,
                    memberName: member.name
                )
                items.append(item)
            }
            
            print("🔔 Dashboard: Converted \(items.count) server pattern alerts to notification items")
            return items
            
        } catch {
            print("❌ Dashboard: Failed to fetch server pattern alerts: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Fetch vitality history for family members and compute trend insights.
    private func computeTrendInsights() async {
        await MainActor.run {
            isComputingTrendInsights = true
        }
        
        print("🔍 computeTrendInsights() called")
        print("  - Total familyMembers: \(familyMembers.count)")
        
        // Collect userIds from eligible members
        let eligibleUserIds = familyMembers.compactMap { member -> String? in
            guard !member.isPending,
                  member.hasScore,
                  member.isScoreFresh,
                  !member.isMe, // exclude the logged-in user from family trend insights
                  let userId = member.userId else {
                return nil
            }
            return userId
        }
        
        print("  - Eligible userIds: \(eligibleUserIds.count)")
        for (idx, uid) in eligibleUserIds.enumerated() {
            let member = familyMembers.first { $0.userId?.lowercased() == uid.lowercased() }
            print("    [\(idx + 1)] \(uid) (\(member?.name ?? "unknown"))")
        }
        
        guard !eligibleUserIds.isEmpty else {
            await MainActor.run {
                trendInsights = []
                trendCoverage = TrendCoverageStatus(
                    windowDays: 21,
                    daysAvailable: 0,
                    missingDays: 21,
                    requiredDaysForAnyInsight: 7,
                    needMoreDataDays: 7,
                    hasMinimumCoverage: false
                )
                isComputingTrendInsights = false
            }
            print("⚠️ TrendEngine: No eligible members for trend analysis")
            print("  - Check: isPending=\(familyMembers.map { $0.isPending }), hasScore=\(familyMembers.map { $0.hasScore }), isScoreFresh=\(familyMembers.map { $0.isScoreFresh })")
            return
        }
        
        do {
            // Fetch 21 days of history for each member (matches trend window)
            print("  📥 Fetching vitality history from Supabase...")
            let history = try await dataManager.fetchMemberVitalityScoreHistory(
                userIds: eligibleUserIds,
                days: 21
            )
            
            print("  📊 History received: \(history.count) users")
            for (userId, scores) in history {
                print("    - \(userId): \(scores.count) days")
            }
            
            // Compute trends
            print("  🧮 Computing trends...")
            // IMPORTANT: We exclude the logged-in user from "family trends" and from history fetches.
            // So we must also exclude them from the trend engine member list, otherwise the engine
            // may pick "Me" as the coverage representative and suppress insights (0 days).
            let result = FamilyVitalityTrendEngine.computeTrends(
                members: familyMembers.filter { !$0.isMe },
                history: history
            )
            
            await MainActor.run {
                trendInsights = result.insights
                trendCoverage = result.coverage
                isComputingTrendInsights = false
            }
            
            print("✅ TrendEngine: Computed \(result.insights.count) trend insights for \(eligibleUserIds.count) members")
            print("  Coverage: daysAvailable=\(result.coverage.daysAvailable) needMore=\(result.coverage.needMoreDataDays) hasMin=\(result.coverage.hasMinimumCoverage)")
            if result.insights.isEmpty {
                print("  ⚠️ No insights generated - check logs above for reasons")
            } else {
                for insight in result.insights {
                    print("  - \(insight.title): \(insight.severity.rawValue) | \(insight.debugWhy ?? "")")
                }
            }
        } catch {
            print("❌ TrendEngine ERROR: \(error.localizedDescription)")
            print("  Error type: \(type(of: error))")
            await MainActor.run {
                trendInsights = []
                trendCoverage = TrendCoverageStatus(
                    windowDays: 21,
                    daysAvailable: 0,
                    missingDays: 21,
                    requiredDaysForAnyInsight: 7,
                    needMoreDataDays: 7,
                    hasMinimumCoverage: false
                )
                isComputingTrendInsights = false
            }
        }
    }
    
    // MARK: - Guided setup status actions (manual nudges; no background logic)
    
    enum GuidedAdminAction {
        case resendInvite
        case startGuidedSetup
        case remindMember
        case viewProfile
    }
    
    private func handleGuidedStatusAction(member: FamilyMemberRecord, action: GuidedAdminAction) {
        switch action {
        case .resendInvite:
            shareText = inviteShareText(for: member, intent: "Invite not accepted")
            isShareSheetPresented = true
        case .remindMember:
            shareText = inviteShareText(for: member, intent: "Reminder to review")
            isShareSheetPresented = true
        case .startGuidedSetup:
            // Navigation occurs via NavigationLink in the row.
            break
        case .viewProfile:
            // Navigation occurs via NavigationLink in the row when available.
            break
        }
    }
    
    private func inviteShareText(for member: FamilyMemberRecord, intent: String) -> String {
        let code = member.inviteCode ?? ""
        return """
        \(intent)
        
        Join the \(resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName) Family on Miya Health
        Invite for: \(member.firstName)
        Code: \(code)
        """
    }
    
    // MARK: - Persistence for dismissed guided members
    
    private func dismissedKey(for userId: String) -> String {
        "dismissedGuidedMembers:\(userId)"
    }
    
    private func loadDismissedGuidedMembers(for userId: String) {
        let key = dismissedKey(for: userId)
        if let data = UserDefaults.standard.array(forKey: key) as? [String] {
            dismissedGuidedMemberIds = Set(data)
        }
    }
    
    private func persistDismissedGuidedMembers(for userId: String) {
        let key = dismissedKey(for: userId)
        UserDefaults.standard.set(Array(dismissedGuidedMemberIds), forKey: key)
    }
    }

// MARK: - FAMILY MEMBERS STRIP

struct FamilyMembersStrip: View {
    let members: [FamilyMemberScore]
    let familyId: String?

    private func label(for score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80: return "Good"
        case 40..<60: return "Okay"
        default: return "Needs attention"
            }
        }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardDesign.internalSpacing) {
                ForEach(members) { member in
                    MemberProfileLink(
                        member: member,
                        vitalityLabel: label(for: member.currentScore),
                        familyId: familyId
                    )
                }
            }
            .padding(.horizontal, DashboardDesign.tinySpacing)
        }
    }
    
    private struct MemberProfileLink: View {
        let member: FamilyMemberScore
        let vitalityLabel: String
        let familyId: String?
        
        private var progress: CGFloat {
            CGFloat(member.ringProgress)
        }
        
        var body: some View {
            NavigationLink {
                if let fid = familyId, let uid = member.userId {
                    FamilyMemberProfileView(
                        memberUserId: uid,
                        memberName: member.name,
                        familyId: fid
                    )
                } else {
                ProfileView(
                    memberName: member.name,
                    vitalityScore: member.currentScore,
                    vitalityTrendDelta: 0,
                    vitalityLabel: vitalityLabel
                )
                }
            } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                // Background circle (premium styling)
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .frame(width: 68, height: 68)
                                    .shadow(
                                        color: DashboardDesign.cardShadowLight.color,
                                        radius: DashboardDesign.cardShadowLight.radius,
                                        x: DashboardDesign.cardShadowLight.x,
                                        y: DashboardDesign.cardShadowLight.y
                                    )

                                // Vitality ring (dim if pending; greyed if stale)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(
                                        member.isStale
                                            ? AngularGradient(
                                                gradient: Gradient(colors: [
                                                    Color.gray.opacity(0.55),
                                                    Color.gray.opacity(0.55),
                                                    Color.gray.opacity(0.55)
                                                ]),
                                                center: .center
                                            )
                                            : AngularGradient(
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
                                    .frame(width: 68, height: 68)
                                    .opacity(member.isPending ? 0.35 : (member.isStale ? 0.75 : 1.0))

                                // Inner avatar (refined sizing)
                                Circle()
                                    .fill(DashboardDesign.groupedBackground)
                                    .frame(width: 52, height: 52)

                                Text(member.initials)
                                    .font(.system(size: 19, weight: .semibold, design: .default))
                                    .foregroundColor(DashboardDesign.primaryTextColor)

                                // Pending badge
                                if member.isPending {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: "clock.badge")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.orange)
                                                .padding(4)
                                        }
                                        Spacer()
                                    }
                                }
                            }

                            // Name under avatar (refined typography)
                            Text(member.isMe ? "Me" : member.name)
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(member.isPending ? .miyaTextSecondary : .miyaTextPrimary)
                        }
                    }
                    .buttonStyle(.plain)
            }
        }
}

// MARK: - Minimal loaders (keep layout stable; avoid flashing placeholders)

private struct DashboardInlineLoaderCard: View {
    let title: String
    
    var body: some View {
        HStack(spacing: DashboardDesign.internalSpacing) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading \(title)…")
                .font(DashboardDesign.bodyFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            Spacer()
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.vertical, DashboardDesign.internalSpacing)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

private struct FamilyVitalityLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            Text("Family vitality")
                .font(DashboardDesign.sectionHeaderFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
                .padding(.top, DashboardDesign.cardPadding)
            
            Spacer()
            
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading family score…")
                        .font(DashboardDesign.bodySemiboldFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                }
                Spacer()
            }
            
            Spacer()
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.bottom, DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
        .frame(minHeight: 200)
        }
}

// MARK: - Guided Setup Status (Admin)

private struct GuidedSetupStatusCard: View {
    let members: [FamilyMemberRecord]
    let familyName: String
    let onDismiss: (String) -> Void
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.miyaSecondary)
                Text("Guided setup")
                    .font(.headline)
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
            }
            
            if members.isEmpty {
                Text("No guided setup members.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(members, id: \.id) { member in
                        GuidedSetupMemberRow(
                            member: member,
                            familyName: familyName,
                            onDismiss: onDismiss,
                            onAction: onAction
                        )
                    }
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

private struct GuidedSetupMemberRow: View {
    let member: FamilyMemberRecord
    let familyName: String
    let onDismiss: (String) -> Void
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
    
    private var status: GuidedSetupStatus {
        // Canonical source of truth: family_members.guided_setup_status
        // For guided members, default nil/unknown to pending_acceptance for display only.
        normalizeGuidedSetupStatus(member.guidedSetupStatus)
    }
    
    private var label: String {
        switch status {
        case .pendingAcceptance: return "Invite not accepted"
        case .acceptedAwaitingData: return "Waiting for you"
        case .dataCompletePendingReview: return "Waiting for member review"
        case .reviewedComplete: return "Complete"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.miyaPrimary.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(member.firstName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.miyaPrimary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.firstName)
                    .font(.subheadline.bold())
                    .foregroundColor(.miyaTextPrimary)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Family: \(familyName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            actionCTA
        }
        .padding(DashboardDesign.internalSpacing)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.smallCornerRadius)
                .fill(DashboardDesign.tertiaryBackgroundColor.opacity(0.5))
        )
    }
    
    @ViewBuilder
    private var actionCTA: some View {
        switch status {
        case .pendingAcceptance:
            Button("Resend invite") { onAction(member, .resendInvite) }
                .font(.caption.bold())
                .foregroundColor(.miyaPrimary)
        case .acceptedAwaitingData:
            NavigationLink {
                GuidedHealthDataEntryFlow(
                    memberId: member.id.uuidString,
                    memberName: member.firstName,
                    inviteCode: member.inviteCode ?? ""
                ) { }
            } label: {
                Text("Start guided setup")
                    .font(.caption.bold())
                    .foregroundColor(.miyaPrimary)
            }
        case .dataCompletePendingReview:
            Button("Remind member") { onAction(member, .remindMember) }
                .font(.caption.bold())
                .foregroundColor(.miyaPrimary)
        case .reviewedComplete:
            HStack(spacing: 12) {
                NavigationLink {
                    // Placeholder: ProfileView currently expects basic display inputs.
                    // This keeps the CTA functional while member-specific profile wiring is completed later.
                    ProfileView(
                        memberName: member.firstName,
                        vitalityScore: 0,
                        vitalityTrendDelta: 0,
                        vitalityLabel: "—"
                    )
                } label: {
                    Text("View profile")
                        .font(.caption.bold())
                        .foregroundColor(.miyaPrimary)
                }
                
                Button {
                    onDismiss(member.id.uuidString)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - CHAT WITH ARLO CARD
    
// MARK: - CHAT WITH ARLO (PRIMARY CTA)
    
    struct ChatWithArloCard: View {
        // IMPORTANT: keep your existing navigation/tap behavior.
        // If your previous ChatWithArloCard had environment objects / routing state,
        // keep them here and keep the action/destination exactly the same.

        // Keep same action - just change UI to primary button
        var onTap: () -> Void = {
            print("Open full chat with Arlo")
            // later: navigate to full chat screen
        }
        
        var body: some View {
            // ✅ IMPORTANT:
            // Replace ONLY the wrapper below with whatever you already had:
            // - If you used NavigationLink, keep the same destination.
            // - If you used Button, keep the same action.
            //
            // EXAMPLE BUTTON WRAPPER (replace with your existing action):
            Button {
                // KEEP YOUR EXISTING ACTION EXACTLY
                // e.g. open AI chat sheet / navigate to Arlo chat
                onTap()
            } label: {
                chatCTAContent
            }
            .buttonStyle(.plain)
        }

        private var chatCTAContent: some View {
            HStack(spacing: 16) {
                    ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DashboardDesign.buttonTint.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.75), lineWidth: 0.9)
                        )
                        .frame(width: 54, height: 54)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                        Text("Chat with Arlo")
                        .font(DashboardDesign.title2Font)
                        .foregroundColor(DashboardDesign.primaryTextColor)

                        Text("Your AI health coach")
                        .font(DashboardDesign.subheadlineFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.65), lineWidth: 0.8)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            .background(DashboardDesign.glassCardBackground(tint: Color.white))
        }
    }
    
// MARK: - FAMILY VITALITY CARD

struct FamilyVitalityCard: View {
    let score: Int
    let label: String
    let factors: [VitalityFactor]
    let includedMembersText: String?
    let progressScore: Int?
    let onFactorTapped: (VitalityFactor) -> Void

    private var progressFraction: Double {
        // Do NOT change logic: use progressScore if present, otherwise fall back to score/100.
        let p = Double(progressScore ?? score)
        return max(0.0, min(p / 100.0, 1.0))
    }

    private var progressLabelText: String {
        // Do NOT hardcode: reuse the values we already have.
        let current = progressScore ?? score
        return "Progress to optimal: \(current) / 100"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with score on right (like screenshot)
            HStack(alignment: .top) {
                Text("Family Vitality")
                    .font(DashboardDesign.title2Font)
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    
                    Spacer()
                    
                // Score on right (like screenshot)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(DashboardDesign.scoreLargeFont)
                        .foregroundColor(Color.miyaPrimary)  // Use brand color to stand out
                    
                    Text(label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }

            // Progress bar + label
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)

                        Capsule()
                            .fill(DashboardDesign.miyaTealSoft)
                            .frame(width: geo.size.width * progressFraction, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(progressLabelText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    
                    if let includedMembersText {
                        Text("• \(includedMembersText)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(DashboardDesign.tertiaryTextColor)
                    }
                }
            }

            // Divider before tiles
                    Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.top, 4)
                    
            // Tiles row (3 compact tiles) built from the SAME `factors` data
            // NOTE: We intentionally do NOT render "What's affecting vitality?" UI.
                            HStack(spacing: 10) {
                ForEach(tilesToShow, id: \.id) { factor in
                    PillarTile(
                        factor: factor,
                        tint: tileTint(for: factor),
                        iconColor: tileIconColor(for: factor)
                    )
                    .onTapGesture {
                        // Keep interaction: tapping a tile selects the factor like before.
                        onFactorTapped(factor)
                    }
                }
            }
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.vertical, DashboardDesign.cardPadding)
        .background(
            ZStack {
                // Base white
                RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius)
                    .fill(Color.white)
                
                // Gloss effect
                RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
        )
        .shadow(
            color: DashboardDesign.cardShadowStrong.color,
            radius: DashboardDesign.cardShadowStrong.radius,
            x: DashboardDesign.cardShadowStrong.x,
            y: DashboardDesign.cardShadowStrong.y
        )
    }

    private var tilesToShow: [VitalityFactor] {
        // Keep the same conceptual pillars: Sleep, Activity, Stress (in that order if present).
        // Do NOT invent; filter from existing factors.
        let order = ["sleep", "activity", "stress"]
        var map: [String: VitalityFactor] = [:]
        for f in factors { map[f.name.lowercased()] = f }
        let ordered = order.compactMap { map[$0] }
        // If any missing, fall back to first 3 factors without changing data.
        return ordered.isEmpty ? Array(factors.prefix(3)) : ordered
    }

    private func tileTint(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor.opacity(0.18)
        case "activity": return DashboardDesign.movementColor.opacity(0.18)
        case "stress": return DashboardDesign.stressColor.opacity(0.18)
        default: return DashboardDesign.buttonTint.opacity(0.12)
        }
    }

    private func tileIconColor(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor
        case "activity": return DashboardDesign.movementColor
        case "stress": return DashboardDesign.stressColor
        default: return DashboardDesign.buttonTint
        }
    }

    private struct PillarTile: View {
        let factor: VitalityFactor
        let tint: Color
        let iconColor: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Icon (smaller, compact)
                Image(systemName: factor.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)

                // Name (smaller font)
                Text(factor.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)

                // Value + Unit on same line (like screenshot: "50 hrs")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(factor.percent)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text(unitShortText(for: factor.name))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }

                // Full unit text below (no truncation)
                Text(unitText(for: factor.name))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    // Base white
                    RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                        .fill(Color.white)
                    
                    // Gloss effect
                    RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
            )
            .shadow(
                color: DashboardDesign.cardShadow.color,
                radius: DashboardDesign.cardShadow.radius,
                x: DashboardDesign.cardShadow.x,
                y: DashboardDesign.cardShadow.y
            )
        }

        private func unitShortText(for name: String) -> String {
            switch name.lowercased() {
            case "sleep": return "hrs"
            case "activity": return "mins"
            case "stress": return "pts"
            default: return ""
            }
        }
        
        private func unitText(for name: String) -> String {
            switch name.lowercased() {
            case "sleep": return "hrs last week"
            case "activity": return "mins last week"
            case "stress": return "pts last week"
            default: return "score"
            }
        }
    }
}

// MARK: - FAMILY BADGES CARD (Daily + Weekly)

private struct FamilyBadgesCard: View {
    let daily: [BadgeEngine.Winner]
    let weekly: [BadgeEngine.Winner]
    let weekStart: String?
    let weekEnd: String?
    
    @State private var isWeeklyExpanded: Bool = false
    
    private func title(for badgeType: String) -> String {
        switch badgeType {
        // Daily
        case "daily_most_sleep": return "Most Sleep"
        case "daily_most_movement": return "Most Movement"
        case "daily_most_stressfree": return "Best Recovery"
        // Weekly
        case "weekly_vitality_mvp": return "Vitality MVP"
        case "weekly_sleep_mvp": return "Sleep Champion"
        case "weekly_movement_mvp": return "Move Champion"
        case "weekly_stressfree_mvp": return "Stress-free MVP"
        case "weekly_family_anchor": return "Family anchor"
        case "weekly_consistency_mvp": return "Consistency MVP"
        case "weekly_balanced_week": return "Balanced week"
        case "weekly_biggest_comeback_day": return "Biggest comeback"
        case "weekly_sleep_streak_leader": return "Sleep streak"
        case "weekly_movement_streak_leader": return "Movement streak"
        case "weekly_stress_streak_leader": return "Stress streak"
        case "weekly_data_champion": return "Data champion"
        default: return badgeType.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    private func iconName(for badgeType: String) -> String {
        switch badgeType {
        case "daily_most_sleep", "weekly_sleep_mvp", "weekly_sleep_streak_leader":
            return "moon.fill"
        case "daily_most_movement", "weekly_movement_mvp", "weekly_movement_streak_leader":
            return "figure.walk"
        case "daily_most_stressfree", "weekly_stressfree_mvp", "weekly_stress_streak_leader":
            return "heart.fill"
        case "weekly_consistency_mvp":
            return "metronome"
        case "weekly_family_anchor":
            return "shield.fill"
        case "weekly_balanced_week":
            return "circle.grid.cross.fill"
        case "weekly_biggest_comeback_day":
            return "arrow.up.right"
        case "weekly_data_champion":
            return "chart.bar.fill"
        case "weekly_vitality_mvp":
            return "crown.fill"
        default:
            return "rosette"
        }
    }
    
    private func weeklySorted(_ winners: [BadgeEngine.Winner]) -> [BadgeEngine.Winner] {
        // Stable order with Vitality MVP featured first
        let order = BadgeEngine.WeeklyBadgeType.allCases.map(\.rawValue)
        return winners.sorted { a, b in
            let ia = order.firstIndex(of: a.badgeType) ?? 999
            let ib = order.firstIndex(of: b.badgeType) ?? 999
            return ia < ib
        }
    }
    
    private func formatDelta(from meta: [String: Any]) -> String? {
        // Prefer percentage increase
        if let percentIncrease = meta["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            if rounded == 0 { return nil }
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
        // Fallback to delta (for backwards compatibility)
        if let d = meta["delta"] as? Double {
            let rounded = Int(d.rounded())
            if rounded == 0 { return nil }
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
        if let i = meta["delta"] as? Int {
            if i == 0 { return nil }
            return i > 0 ? "+\(i)" : "\(i)"
        }
        return nil
    }

    var body: some View {
        let weeklyOrdered = weeklySorted(weekly)
        let featured = weeklyOrdered.first(where: { $0.badgeType == "weekly_vitality_mvp" }) ?? weeklyOrdered.first
        let rest = weeklyOrdered.filter { $0.id != featured?.id }
        
        VStack(alignment: .leading, spacing: 16) {
            // Header (exact match to screenshot)
            HStack(spacing: 6) {
                Text("Champions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                if let weekStart, let weekEnd, !weekly.isEmpty {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    Text("\(weekStart) – \(weekEnd) UTC")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                Spacer()
            }
            
            // Empty state
            if daily.isEmpty && weekly.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No champions yet")
                .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    
                    Text("Add daily vitality scores to start awarding Today + Weekly champions.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            
            // Featured Vitality MVP card (exact match to screenshot)
            if let featured {
                FeaturedVitalityCard(
                    winnerName: featured.winnerName,
                    deltaText: formatDelta(from: featured.metadata),
                    subtitle: formatVitalitySubtitle(from: featured.metadata)
                )
            }
            
            // Today section (exact match to screenshot)
            if !daily.isEmpty {
                Text("Today")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    .padding(.top, 4)
                
                VStack(spacing: 8) {
                    ForEach(daily) { w in
                        ChampionRow(
                            title: title(for: w.badgeType),
                            winnerName: w.winnerName,
                            iconName: iconName(for: w.badgeType),
                            valueText: formatDailyValue(for: w.badgeType, metadata: w.metadata)
                        )
                    }
                }
                .padding(.top, 8)
            }
            
            // This week section (exact match to screenshot)
            if !weekly.isEmpty {
            HStack {
                    Text("This week")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DashboardDesign.primaryTextColor)

                Spacer()

                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
                .padding(.top, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                        isWeeklyExpanded.toggle()
                    }
                }
                
                if isWeeklyExpanded {
                    VStack(spacing: 8) {
                        ForEach(rest.prefix(3)) { w in
                            ChampionRow(
                                title: title(for: w.badgeType),
                                winnerName: w.winnerName,
                                iconName: iconName(for: w.badgeType),
                                valueText: formatWeeklyValue(for: w.badgeType, metadata: w.metadata)
                            )
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 8) {
                        ForEach(rest.prefix(2)) { w in
                            ChampionRow(
                                title: title(for: w.badgeType),
                                winnerName: w.winnerName,
                                iconName: iconName(for: w.badgeType),
                                valueText: formatWeeklyValue(for: w.badgeType, metadata: w.metadata)
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
    
    // Helper functions for formatting values
    private func formatDailyValue(for badgeType: String, metadata: [String: Any]) -> String {
        // Format as percentage increase from previous day
        if let percentIncrease = metadata["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)%"
        }
        // Fallback for old format (shouldn't happen after migration)
        if let value = metadata["value"] as? Int {
            return "+\(value)%"
        }
        return ""
    }
    
    private func formatWeeklyValue(for badgeType: String, metadata: [String: Any]) -> String {
        // Format as percentage increase from previous week
        if let percentIncrease = metadata["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)%"
        }
        // Fallback for old format (delta-based)
        if let delta = metadata["delta"] as? Double, let prevAvg = metadata["prevAvg"] as? Double, prevAvg > 0 {
            let percentIncrease = (delta / prevAvg) * 100.0
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)%"
        }
        // Last resort fallback
        if let delta = metadata["delta"] as? Double {
            let deltaInt = Int(delta.rounded())
            return "\(deltaInt > 0 ? "+" : "")\(deltaInt)"
        }
        return ""
    }
    
    private func formatVitalitySubtitle(from metadata: [String: Any]) -> String {
        // Format as percentage increase
        if let percentIncrease = metadata["percentIncrease"] as? Double {
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)% vitality this week"
        }
        // Fallback for old format
        if let delta = metadata["delta"] as? Double, let prevAvg = metadata["prevAvg"] as? Double, prevAvg > 0 {
            let percentIncrease = (delta / prevAvg) * 100.0
            let rounded = Int(percentIncrease.rounded())
            return "+\(rounded)% vitality this week"
        }
        if let delta = metadata["delta"] as? Double {
            let deltaInt = Int(delta.rounded())
            return "+\(deltaInt) vitality points this week"
        }
        return ""
    }
}

// MARK: - Featured Vitality MVP Card (exact match to screenshot)
private struct FeaturedVitalityCard: View {
    let winnerName: String
    let deltaText: String?
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Trophy icon
            Image(systemName: "crown.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Vitality MVP")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                // Name pill
                Text(winnerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.top, 2)
            }

                                Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // "This week" pill
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                // Delta value with arrow
                if let deltaText, !deltaText.isEmpty {
                    HStack(spacing: 4) {
                        Text(deltaText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DashboardDesign.primaryTextColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
        )
    }
}

// MARK: - Champion Row (exact match to screenshot - Today and This week rows)
private struct ChampionRow: View {
    let title: String
    let winnerName: String
    let iconName: String
    let valueText: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon (colored, matching dashboard)
            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundColor(iconColor(for: iconName))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)
                
                Text(winnerName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
            }
            
            Spacer()
            
            // Value with arrow
            HStack(spacing: 4) {
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 4,
            x: 0,
            y: 1
        )
    }
    
    private func iconColor(for iconName: String) -> Color {
        switch iconName {
        case "moon.fill": return Color.purple
        case "figure.walk": return Color.green
        case "heart.fill": return Color.orange
        case "crown.fill": return Color.blue
        default: return Color.blue
        }
    }
}

// MARK: - DEBUG: Add single-day (or range) vitality_scores rows by computing via VitalityScoringEngine

#if DEBUG
private struct DebugAddRecordView: View {
    let members: [FamilyMemberScore]
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedUserId: String = ""
    @State private var selectedName: String = ""
    
    @State private var day: Date = Date()
    @State private var daysToCreate: Int = 1
    
    // Raw inputs (keep minimal; computed through the real engine)
    @State private var sleepHoursText: String = ""
    @State private var stepsText: String = ""
    @State private var movementMinutesText: String = ""
    @State private var hrvMsText: String = ""
    @State private var restingHrText: String = ""
    
    // Age (derived from profile if possible; allow override)
    @State private var derivedAge: Int? = nil
    @State private var isOverridingAge: Bool = false
    @State private var overrideAge: Int = 30
    
    @State private var isSaving: Bool = false
    @State private var statusText: String? = nil
    
    private func utcDayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    private func parseDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Locale-safe parsing: accept both "." and "," decimals.
        let nf = NumberFormatter()
        nf.locale = Locale.current
        nf.numberStyle = .decimal
        if let n = nf.number(from: trimmed) {
            return n.doubleValue
        }
        // Fallback: swap comma->dot
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func parseInt(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
    
    private var ageUsed: Int? {
        if isOverridingAge { return overrideAge }
        return derivedAge
    }
    
    private func computeSnapshot() -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown)? {
        guard let age = ageUsed else { return nil }
        
        let raw = VitalityRawMetrics(
            age: age,
            sleepDurationHours: parseDouble(sleepHoursText),
            restorativeSleepPercent: nil,
            sleepEfficiencyPercent: nil,
            awakePercent: nil,
            movementMinutes: parseDouble(movementMinutesText),
            steps: parseInt(stepsText),
            activeCalories: nil,
            hrvMs: parseDouble(hrvMsText),
            hrvType: (parseDouble(hrvMsText) != nil) ? "rmssd" : nil,
            restingHeartRate: parseDouble(restingHrText),
            breathingRate: nil
        )
        
        let engine = VitalityScoringEngine()
        return engine.scoreIfPossible(raw: raw)
    }
    
    private func pill(_ snapshot: VitalitySnapshot, _ pillar: VitalityPillar) -> Int? {
        snapshot.pillarScores.first(where: { $0.pillar == pillar })?.score
    }
    
    private func computeDerivedAgeIfPossible(userId: String) async {
        struct DOBRow: Decodable { let date_of_birth: String? }
        do {
            let supabase = SupabaseConfig.client
            let rows: [DOBRow] = try await supabase
                .from("user_profiles")
                .select("date_of_birth")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            guard let s = rows.first?.date_of_birth, !s.isEmpty else {
                await MainActor.run { derivedAge = nil }
                return
            }
            
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            guard let dob = df.date(from: s) else {
                await MainActor.run { derivedAge = nil }
                return
            }
            
            let cal = Calendar(identifier: .gregorian)
            let now = Date()
            let years = cal.dateComponents([.year], from: dob, to: now).year ?? 30
            await MainActor.run {
                derivedAge = max(0, years)
                // keep overrideAge reasonable if user toggles override on
                if overrideAge <= 0 { overrideAge = max(0, years) }
            }
        } catch {
            await MainActor.run { derivedAge = nil }
        }
    }
    
    private func seedDefaultMemberIfNeeded() {
        guard selectedUserId.isEmpty else { return }
        if let me = members.first(where: { $0.isMe }), let uid = me.userId {
            selectedUserId = uid
            selectedName = me.name
        } else if let first = members.first(where: { !$0.isPending && $0.userId != nil }), let uid = first.userId {
            selectedUserId = uid
            selectedName = first.name
        }
    }
    
    var body: some View {
        Form {
            Section {
                Picker("Member", selection: $selectedUserId) {
                    ForEach(members.filter { !$0.isPending && $0.userId != nil }, id: \.userId) { m in
                        Text(m.name).tag(m.userId ?? "")
                    }
                }
                .onChange(of: selectedUserId) { _, newId in
                    if let m = members.first(where: { $0.userId == newId }) {
                        selectedName = m.name
                    }
                    Task { await computeDerivedAgeIfPossible(userId: newId) }
                }
            } header: {
                Text("Target")
            }
            
            Section {
                DatePicker("Start day", selection: $day, displayedComponents: [.date])
                Stepper("Days to create: \(daysToCreate)", value: $daysToCreate, in: 1...14)
                Button("Quick: 7 days") { daysToCreate = 7 }
                    .foregroundColor(.miyaPrimary)
            } header: {
                Text("Dates (UTC day keys)")
            } footer: {
                Text("This writes rows to vitality_scores using UTC day keys (YYYY-MM-DD). Weekly badges use the last 7 completed UTC days (ending yesterday).")
            }
            
            Section {
                Toggle("Override age", isOn: $isOverridingAge)
                if isOverridingAge {
                    Stepper("Age: \(overrideAge)", value: $overrideAge, in: 0...110)
                } else {
                    HStack {
                        Text("Age used")
                Spacer()
                        Text(derivedAge.map(String.init) ?? "Missing in profile")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Age (must match scoring)")
            } footer: {
                Text("We compute scores using the same age-specific schema as production. If date of birth is missing, enable override.")
            }
            
            Section {
                TextField("Sleep duration (hours)", text: $sleepHoursText)
                    .keyboardType(.decimalPad)
                TextField("Steps (count)", text: $stepsText)
                    .keyboardType(.numberPad)
                TextField("Movement minutes (optional)", text: $movementMinutesText)
                    .keyboardType(.decimalPad)
                TextField("HRV ms (optional)", text: $hrvMsText)
                    .keyboardType(.decimalPad)
                TextField("Resting HR (optional)", text: $restingHrText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Raw inputs (we compute pillars from these)")
            } footer: {
                Text("Do not type pillar scores here. Pillars/total are computed via VitalityScoringEngine to match production.")
            }
            
            Section {
                if let scored = computeSnapshot() {
                    let snap = scored.snapshot
                    HStack {
                        Text("Total")
                        Spacer()
                        Text("\(snap.totalScore)/100")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    HStack {
                        Text("Sleep")
                        Spacer()
                        Text("\(pill(snap, .sleep) ?? 0)/100")
                    }
                    HStack {
                        Text("Movement")
                        Spacer()
                        Text("\(pill(snap, .movement) ?? 0)/100")
                    }
                    HStack {
                        Text("Stress")
                        Spacer()
                        Text("\(pill(snap, .stress) ?? 0)/100")
                    }
                } else {
                    Text("Enter enough data for at least 2 pillars (e.g., sleep + steps/movement or sleep + HRV/resting HR).")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Preview (computed)")
            }
            
            Section {
                if let statusText {
                    Text(statusText)
                        .foregroundColor(.secondary)
                }
                
                        Button {
                    guard !selectedUserId.isEmpty else { return }
                    guard let scored = computeSnapshot() else {
                        statusText = "Not enough data to compute a valid vitality snapshot (need 2 pillars)."
                        return
                    }
                    
                    isSaving = true
                    statusText = nil
                    
                    Task {
                        let start = day
                        let cal = Calendar(identifier: .gregorian)
                        
                        var rows: [(dayKey: String, snapshot: VitalitySnapshot)] = []
                        for i in 0..<daysToCreate {
                            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
                            rows.append((dayKey: utcDayKey(for: d), snapshot: scored.snapshot))
                        }
                        
                        #if DEBUG
                        let firstKey = rows.first?.dayKey ?? "nil"
                        let lastKey = rows.last?.dayKey ?? "nil"
                        print("DEBUG_ADD_RECORD_SAVE: userId=\(selectedUserId) days=\(rows.count) range=\(firstKey)→\(lastKey)")
                        #endif
                        
                        do {
                            try await dataManager.saveDailyVitalityPillarScores(
                                rows,
                                source: "manual",
                                forUserId: selectedUserId,
                                clearExisting: false
                            )
                            await MainActor.run {
                                isSaving = false
                                statusText = "Saved \(daysToCreate) day(s) for \(selectedName.isEmpty ? "member" : selectedName)."
                            }
                            // Dismiss after a short beat so the user sees success
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            await MainActor.run { dismiss() }
                        } catch {
                            await MainActor.run {
                                isSaving = false
                                statusText = "Save failed: \(error.localizedDescription)"
                            }
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .tint(.miyaPrimary)
                        } else {
                            Text("Save record(s)")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Add record (debug)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedDefaultMemberIfNeeded()
            if !selectedUserId.isEmpty {
                Task { await computeDerivedAgeIfPossible(userId: selectedUserId) }
            }
        }
    }
}
#endif

struct FamilyVitalityPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Family vitality")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
                .padding(.top, 12)
            
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.miyaPrimary.opacity(0.6))
                
                VStack(spacing: 6) {
                    Text("Waiting for your family")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Once your family members complete onboarding and sync their health data, you'll see your family vitality score here.")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
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
            switch index {
            case 0: return Color.red.opacity(0.9)
            case 1: return Color.yellow.opacity(0.9)
            default: return Color.green.opacity(0.9)
            }
        }
        
        private func trafficProgressBar(for percent: Int) -> some View {
            let clamped = max(0, min(percent, 100))
            let band = statusBand(for: clamped)
            let fill = bandColor(for: band)

            let totalWidth: CGFloat = 64
            let height: CGFloat = 7
            let corner: CGFloat = height / 2

            // Show a small “dot” for tiny non-zero values so 1–5% isn’t invisible.
            let rawFillWidth = totalWidth * (CGFloat(clamped) / 100.0)
            let fillWidth = (clamped == 0) ? 0 : max(rawFillWidth, height)

            return ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color(.systemGray4))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(Color(.systemGray3), lineWidth: 0.5)
                    )

                RoundedRectangle(cornerRadius: corner)
                    .fill(fill)
                    .frame(width: fillWidth)
                    .animation(.easeInOut(duration: 0.2), value: clamped)
            }
            .frame(width: totalWidth, height: height, alignment: .leading)
            .clipped()
            .fixedSize()
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
                                let freshMembers = factor.memberScores.filter { $0.hasScore && $0.isScoreFresh }
                                let staleMembers = factor.memberScores.filter { $0.hasScore && !$0.isScoreFresh }
                                let missingCount = factor.memberScores.filter { !$0.hasScore }.count
                                
                                ForEach(freshMembers) { member in
                                    scoreRow(
                                        member: member,
                                        tint: trafficColor(for: member.currentScore),
                                        trailingLabel: "\(member.currentScore)"
                                    )
                                }
                                
                                if !staleMembers.isEmpty {
                                    Divider().padding(.vertical, 4)
                                    Text("Needs sync")
                                            .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.miyaTextSecondary)
                                    
                                    ForEach(staleMembers) { member in
                                        scoreRow(
                                            member: member,
                                            tint: .gray.opacity(0.55),
                                            trailingLabel: "Needs sync"
                                        )
                                    }
                                }
                                
                                if missingCount > 0 {
                                    Divider().padding(.vertical, 4)
                                    Text("No data yet for \(missingCount) member\(missingCount == 1 ? "" : "s").")
                                        .font(.system(size: 13))
                                        .foregroundColor(.miyaTextSecondary)
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
        
        private func scoreRow(member: FamilyMemberScore, tint: Color, trailingLabel: String) -> some View {
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
                
                // Name + colored bar
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                    
                    ProgressView(value: Double(member.currentScore), total: Double(max(member.optimalScore, 1)))
                        .progressViewStyle(.linear)
                        .tint(tint)
                }
                
                Spacer()
                
                Text(trailingLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
        }
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
    }
    
    // MARK: - SIDEBAR MENU
    
    struct SidebarMenu: View {
        @Binding var isVisible: Bool
        @Binding var isInviteMemberSheetPresented: Bool
        let familyMemberRecords: [FamilyMemberRecord]
        let currentUserId: String?
        let familyDisplayName: String
        let onReloadMembers: () -> Void
        let onUpdateResolvedFamilyName: (String) -> Void
        
        // Needed for sign-out + cache reset. Do not access private auth props from views.
        @EnvironmentObject var authManager: AuthManager
        @EnvironmentObject var dataManager: DataManager
        @EnvironmentObject var onboardingManager: OnboardingManager
        
        @State private var mode: SidebarMode = .menu
        
        private var isSuperAdminUser: Bool {
            guard let uid = currentUserId else { return false }
            return familyMemberRecords.first(where: { $0.userId?.uuidString == uid })?.role.lowercased() == "superadmin"
        }
        
        private var accountName: String {
            let first = onboardingManager.firstName.trimmingCharacters(in: .whitespaces)
            let last = onboardingManager.lastName.trimmingCharacters(in: .whitespaces)
            let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { return full }
            if !onboardingManager.email.isEmpty { return onboardingManager.email }
            return "You"
        }
        
        private var accountEmail: String {
            if !onboardingManager.email.isEmpty { return onboardingManager.email }
            return ""
        }
        
        private var membersDisplayString: String {
            let memberNames = familyMemberRecords.map { record in
                if record.userId?.uuidString == currentUserId {
                    return "\(record.firstName) (you)"
                } else {
                    return record.firstName
                }
            }
            return memberNames.joined(separator: ", ")
        }
        
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
                    userName: accountName,
                    userEmail: accountEmail,
                    familyName: familyDisplayName,
                    familyMembersDisplay: membersDisplayString,
                    isSuperAdmin: isSuperAdminUser,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .menu
                        }
                    },
                    onSignOut: {
                        Task {
                            do {
                                // signOut() posts .userDidLogout notification which triggers full state reset
                                try await authManager.signOut()
                            } catch {
                                print("❌ Dashboard: Sign out failed: \(error.localizedDescription)")
                            }
                        }
                    },
                    onManageMembers: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .manageMembers
                        }
                    },
                    onSaveProfile: { newName in
                        try await dataManager.updateMyMemberName(firstName: newName)
                        onboardingManager.firstName = newName
                    },
                    onSaveFamilyName: { newName in
                        guard let familyId = dataManager.currentFamilyId else {
                            throw NSError(
                                domain: "MiyaDashboard",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Family not loaded"]
                            )
                        }
                        try await dataManager.updateFamilyName(familyId: familyId, name: newName)
                        onUpdateResolvedFamilyName(newName)
                    }
                )
                
            case .manageMembers:
                ManageMembersView(
                    members: familyMemberRecords.map {
                        FamilyMemberSummary(
                            id: $0.id.uuidString,
                            name: $0.firstName,
                            isYou: $0.userId?.uuidString == currentUserId,
                            isSuperAdmin: $0.role.lowercased() == "superadmin"
                        )
                    },
                    isSuperAdmin: isSuperAdminUser,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = .account
                        }
                    },
                    onRemove: { member in
                        guard isSuperAdminUser else { return }
                        Task {
                            do {
                                try await dataManager.softRemoveFamilyMember(memberId: member.id)
                                onReloadMembers()
                            } catch {
                                print("❌ Dashboard: Remove member failed: \(error.localizedDescription)")
                            }
                        }
                    },
                    onInvite: {
                        guard isSuperAdminUser else { return }
                        isInviteMemberSheetPresented = true
                    }
                )
            }
        }
        
        // MARK: - MENU CONTENT
        
        private var menuContent: some View {
                VStack(alignment: .leading, spacing: 24) {
                
                // Account block (tap to open Account page)
                VStack(alignment: .leading, spacing: 4) {
                    let displayName = accountName
                    Text("Account")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(sidebarInitials(from: displayName))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
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
                    
                    // Superadmin-only: reuse onboarding invite flow (same validations + DB writes).
                    if isSuperAdminUser {
                        menuItem(icon: "person.badge.plus", title: "Invite Member") {
                            print("✅ Invite Member tapped")
                            isInviteMemberSheetPresented = true
                        }
                    }
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Sign out at bottom (still accessible from menu view)
                Button {
                    Task {
                        do {
                            try await authManager.signOut()
                        } catch {
                            print("⚠️ Sign out failed: \(error.localizedDescription)")
                        }
                    }
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
        let familyName: String
        let familyMembersDisplay: String
        let isSuperAdmin: Bool
        let onBack: () -> Void
        let onSignOut: () -> Void
        let onManageMembers: () -> Void
        let onSaveProfile: (String) async throws -> Void
        let onSaveFamilyName: ((String) async throws -> Void)?
        
        // TEMP: mocked devices – later wire real data
        private let connectedDevices: [ConnectedDevice] = [
            ConnectedDevice(name: "Apple Health", lastSyncDescription: "2 hours ago")
        ]
        
        // Profile editing state
        @State private var isEditingProfile: Bool = false
        @State private var draftName: String = ""
        @State private var draftEmail: String = ""
        @State private var isSavingProfile: Bool = false
        @State private var profileErrorMessage: String?
        
        @State private var isEditingFamilyName: Bool = false
        @State private var draftFamilyName: String = ""
        @State private var isSavingFamilyName: Bool = false
        @State private var familyNameErrorMessage: String?
        
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
        
        @State private var localUserName: String
        @State private var localFamilyName: String
        
        private var userInitials: String {
            initials(from: localUserName)
        }
        
        init(userName: String,
             userEmail: String,
             familyName: String,
             familyMembersDisplay: String,
             isSuperAdmin: Bool,
             onBack: @escaping () -> Void,
             onSignOut: @escaping () -> Void,
             onManageMembers: @escaping () -> Void,
             onSaveProfile: @escaping (String) async throws -> Void,
             onSaveFamilyName: ((String) async throws -> Void)? = nil) {
            self.userName = userName
            self.userEmail = userEmail
            self.familyName = familyName
            self.familyMembersDisplay = familyMembersDisplay
            self.isSuperAdmin = isSuperAdmin
            self.onBack = onBack
            self.onSignOut = onSignOut
            self.onManageMembers = onManageMembers
            self.onSaveProfile = onSaveProfile
            self.onSaveFamilyName = onSaveFamilyName
            _localUserName = State(initialValue: userName)
            _localFamilyName = State(initialValue: familyName)
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
                                        Text(localUserName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        Text(userEmail)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                }
                                
                                Button {
                                    draftName = localUserName
                                    draftEmail = userEmail
                                    profileErrorMessage = nil
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditingProfile = true
                                    }
                                } label: {
                                    Text(isEditingProfile ? "Editing…" : "Edit profile")
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(999)
                                }
                                
                                if isEditingProfile {
                                    VStack(alignment: .leading, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Name")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.miyaTextSecondary)
                                            TextField("Name", text: $draftName)
                                                .padding(10)
                                                .background(Color.miyaBackground)
                                                .cornerRadius(10)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Email")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.miyaTextSecondary)
                                            TextField("Email", text: $draftEmail)
                                                .padding(10)
                                                .background(Color.miyaBackground)
                                                .cornerRadius(10)
                                                .disabled(true)
                                            Text("Email is managed by your login provider.")
                                                .font(.footnote)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        
                                        if let profileErrorMessage {
                                            Text(profileErrorMessage)
                                                .font(.footnote)
                                                .foregroundColor(.red.opacity(0.9))
                                        }
                                        
                                        HStack {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    isEditingProfile = false
                                                }
                                                profileErrorMessage = nil
                                            } label: {
                                                Text("Cancel")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                            }
                                            
                                            Button {
                                                Task {
                                                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    guard !trimmed.isEmpty else {
                                                        await MainActor.run {
                                                            profileErrorMessage = "Name can’t be empty."
                                                        }
                                                        return
                                                    }
                                                    
                                                    await MainActor.run {
                                                        isSavingProfile = true
                                                        profileErrorMessage = nil
                                                    }
                                                    
                                                    defer {
                                                        Task { @MainActor in
                                                            isSavingProfile = false
                                                        }
                                                    }
                                                    
                                                    do {
                                                        try await onSaveProfile(trimmed)
                                                        await MainActor.run {
                                                            localUserName = trimmed
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                isEditingProfile = false
                                                            }
                                                            profileErrorMessage = nil
                                                        }
                                                    } catch {
                                                        await MainActor.run {
                                                            profileErrorMessage = error.localizedDescription
                                                        }
                                                    }
                                                }
                                            } label: {
                                                HStack {
                                                    if isSavingProfile {
                                                        ProgressView()
                                                            .progressViewStyle(.circular)
                                                    }
                                                    Text(isSavingProfile ? "Saving…" : "Save")
                                                        .font(.system(size: 14, weight: .semibold))
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                            }
                                            .background(Color.miyaEmerald)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                            .disabled(isSavingProfile)
                                        }
                                    }
                                    .padding(.top, 8)
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
                                            Task { print("Connect another device tapped") }
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
                            
                            // FAMILY SETTINGS (edit gated by superadmin)
                                AccountSection("Family settings") {
                                    VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                        Text("Family name")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                            Text(localFamilyName)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                        }
                                        Spacer()
                                        if isSuperAdmin, onSaveFamilyName != nil {
                                            Button {
                                                draftFamilyName = localFamilyName
                                                familyNameErrorMessage = nil
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    isEditingFamilyName = true
                                                }
                                            } label: {
                                                Text(isEditingFamilyName ? "Editing…" : "Edit")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .padding(.vertical, 4)
                                                    .padding(.horizontal, 10)
                                                    .background(Color.white.opacity(0.18))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(10)
                                            }
                                        }
                                    }
                                    
                                    if isEditingFamilyName {
                                        VStack(alignment: .leading, spacing: 8) {
                                            TextField("Family name", text: $draftFamilyName)
                                                .padding(10)
                                                .background(Color.miyaBackground)
                                                .cornerRadius(10)
                                            
                                            if let familyNameErrorMessage {
                                                Text(familyNameErrorMessage)
                                                    .font(.footnote)
                                                    .foregroundColor(.red.opacity(0.9))
                                            }
                                            
                                            HStack {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        isEditingFamilyName = false
                                                    }
                                                    familyNameErrorMessage = nil
                                                } label: {
                                                    Text("Cancel")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 8)
                                                }
                                                
                                                Button {
                                                    Task {
                                                        guard let onSaveFamilyName else {
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                isEditingFamilyName = false
                                                            }
                                                            return
                                                        }
                                                        let trimmed = draftFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
                                                        guard !trimmed.isEmpty else {
                                                            familyNameErrorMessage = "Family name can’t be empty."
                                                            return
                                                        }
                                                        isSavingFamilyName = true
                                                        do {
                                                            try await onSaveFamilyName(trimmed)
                                                            localFamilyName = trimmed
                                                            familyNameErrorMessage = nil
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                isEditingFamilyName = false
                                                            }
                                                        } catch {
                                                            familyNameErrorMessage = error.localizedDescription
                                                        }
                                                        isSavingFamilyName = false
                                                    }
                                                } label: {
                                                    HStack {
                                                        if isSavingFamilyName {
                                                            ProgressView()
                                                                .progressViewStyle(.circular)
                                                        }
                                                        Text("Save")
                                                            .font(.system(size: 13, weight: .semibold))
                                                    }
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                }
                                                .background(Color.miyaEmerald)
                                                .foregroundColor(.white)
                                                .cornerRadius(10)
                                                .disabled(isSavingFamilyName)
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.15))
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Members")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text(familyMembersDisplay)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                    }
                                    
                                if isSuperAdmin {
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
                
            }
        .sheet(item: $activeDevice) { device in
            NavigationStack {
                        VStack(spacing: 16) {
                            Text(device.name)
                        .font(.system(size: 18, weight: .semibold))
                    Text("Last sync: \(device.lastSyncDescription)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                            
                            Button {
                        Task { print("Reconnect \(device.name) tapped") }
                            } label: {
                        Text("Reconnect")
                            .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            }
                    .buttonStyle(.borderedProminent)
                            
                            Button {
                        Task { print("Connect another device tapped") }
                            } label: {
                        Text("Connect another device")
                            .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                        
                        Spacer()
                    }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            activeDevice = nil
                        }
                    }
                }
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
        let id: String
        let name: String
        let isYou: Bool
        let isSuperAdmin: Bool
    }
    
    struct ManageMembersView: View {
        let members: [FamilyMemberSummary]
        let isSuperAdmin: Bool
        
        let onBack: () -> Void
        let onRemove: (FamilyMemberSummary) -> Void
        let onInvite: () -> Void
        
        @State private var selectedMemberForRemoval: FamilyMemberSummary? = nil
        
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
                        
                        if isSuperAdmin {
                            // Invite member action (moved here from sidebar)
                            Button {
                                onInvite()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Invite member")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundColor(.miyaPrimary)
                                .background(Color.white)
                                .cornerRadius(14)
                            }
                            .padding(.top, 16)
                        }
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
                    
                    Text(member.isSuperAdmin ? "Superadmin" : "Member")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if isSuperAdmin && !member.isSuperAdmin && !member.isYou {
                Menu {
                        Button("Remove member", role: .destructive) {
                            selectedMemberForRemoval = member
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
    // MARK: - Shared Helper (for Sidebar, Account, ManageMembers)
    
    fileprivate func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }


// MARK: - PERSONAL VITALITY CARD

private struct PersonalVitalityCard: View {
    let currentUser: FamilyMemberScore
    let factors: [VitalityFactor]
    @State private var isExpanded: Bool = false
    
    private func label(for score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80:  return "Good"
        case 40..<60:  return "Okay"
        default:       return "Needs attention"
        }
    }
    
    private func myPillarScore(named factorName: String) -> Int? {
        let match = factors.first(where: { $0.name.lowercased() == factorName.lowercased() })
        return match?.memberScores.first(where: { $0.isMe })?.currentScore
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            HStack(spacing: DashboardDesign.internalSpacing) {
                ZStack {
                    Circle()
                        .fill(DashboardDesign.miyaTealSoft.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(currentUser.initials)
                        .font(DashboardDesign.bodyFont)
                        .foregroundColor(DashboardDesign.miyaTealSoft.opacity(0.9))
                }
                
                VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
                    Text("My Vitality")
                        .font(DashboardDesign.bodySemiboldFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text(label(for: currentUser.currentScore))
                        .font(DashboardDesign.secondaryFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                Spacer()
                
                // Clear, non-gauge comparison: current vs optimal (premium typography)
                VStack(alignment: .trailing, spacing: DashboardDesign.tinySpacing) {
                    Text("\(currentUser.currentScore)/\(max(currentUser.optimalScore, 1))")
                        .font(DashboardDesign.scoreSmallFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text("Current / Optimal")
                        .font(DashboardDesign.tinyFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    if let p = currentUser.progressScore {
                        Text("Progress: \(p)/100")
                            .font(DashboardDesign.tinyFont)
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
            }
            
            if currentUser.optimalScore > 0 {
                ProgressView(value: Double(currentUser.currentScore), total: Double(currentUser.optimalScore))
                    .tint(DashboardDesign.miyaTealSoft)
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide submetrics" : "View submetrics")
                        .font(DashboardDesign.secondarySemiboldFont)
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                let sleep = myPillarScore(named: "Sleep")
                let movement = myPillarScore(named: "Activity")
                let stress = myPillarScore(named: "Stress")
                
                HStack(spacing: DashboardDesign.internalSpacing) {
                    PillarMini(label: "Sleep", score: sleep)
                    PillarMini(label: "Movement", score: movement)
                    PillarMini(label: "Stress", score: stress)
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

private struct PillarMini: View {
    let label: String
    let score: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text(label)
                .font(DashboardDesign.captionSemiboldFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            
            Text(score.map { "\($0)/100" } ?? "—")
                .font(DashboardDesign.bodySemiboldFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
        }
        .padding(.vertical, DashboardDesign.smallSpacing)
        .padding(.horizontal, DashboardDesign.internalSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardDesign.tertiaryBackgroundColor)
        .cornerRadius(DashboardDesign.smallCornerRadius)
    }
}

// MARK: - FAMILY VITALITY INSIGHTS CARD (Premium Redesign)

// MARK: - Family Notifications (lightweight, drill-in)

private struct FamilyNotificationItem: Identifiable {
    enum Kind {
        case trend(TrendInsight)
        case fallback(memberName: String, memberInitials: String, memberUserId: String?, pillar: VitalityPillar, title: String, body: String)
    }
    
    let id: String
    let kind: Kind
    let pillar: VitalityPillar
    let title: String
    let body: String
    let memberInitials: String
    let memberName: String
    
    /// Extract member user ID from the item (for history fetching)
    var memberUserId: String? {
        switch kind {
        case .trend(let insight):
            return insight.memberUserId
        case .fallback(_, _, let userId, _, _, _):
            return userId
        }
    }
    
    /// Extract debug why text if available
    var debugWhy: String? {
        switch kind {
        case .trend(let insight):
            return insight.debugWhy
        case .fallback:
            return nil
        }
    }
    
    /// Extract window days if available (for defaulting segmented control)
    var triggerWindowDays: Int? {
        switch kind {
        case .trend(let insight):
            return insight.windowDays
        case .fallback:
            return nil
        }
    }
    
    static func build(
        snapshot: FamilyVitalitySnapshot,
        trendInsights: [TrendInsight],
        trendCoverage: TrendCoverageStatus?,
        factors: [VitalityFactor],
        members: [FamilyMemberScore]
    ) -> [FamilyNotificationItem] {
        func memberPillarScore(userId: String?, factorName: String) -> Int? {
            guard let uid = userId?.lowercased() else { return nil }
            let f = factors.first(where: { $0.name.lowercased() == factorName.lowercased() })
            return f?.memberScores.first(where: { $0.userId?.lowercased() == uid })?.currentScore
        }
        
        func memberPillarScore(userId: String?, pillar: VitalityPillar) -> Int? {
            switch pillar {
            case .sleep: return memberPillarScore(userId: userId, factorName: "Sleep")
            case .movement: return memberPillarScore(userId: userId, factorName: "Activity")
            case .stress: return memberPillarScore(userId: userId, factorName: "Stress")
            }
        }
        
        /// If a member's current pillar score is strong, suppress negative trend alerts (they've likely already recovered).
        /// For all pillars (Sleep, Movement, Stress): HIGHER score = BETTER (better sleep, more movement, better stress management).
        /// If current score >= 85, the member is doing well NOW, so we suppress alerts about past problems.
        func isStillRelevantNegativeAlert(memberUserId: String?, pillar: VitalityPillar) -> Bool {
            guard let current = memberPillarScore(userId: memberUserId, pillar: pillar) else {
                #if DEBUG
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=nil → KEEP (no score available)")
                #endif
                return true
            }
            // Only suppress if current pillar score is very strong (>= 85), indicating full recovery.
            // Lower threshold (75) was too aggressive and filtered out valid trend alerts.
            let shouldKeep = current < 85
            #if DEBUG
            if shouldKeep {
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=\(current) → KEEP (score < 85, alert still relevant)")
            } else {
                print("🔔 NotificationFilter: memberUserId=\(memberUserId ?? "nil"), pillar=\(pillar), currentScore=\(current) → FILTER OUT (score >= 85, member has recovered)")
            }
            #endif
            return shouldKeep
        }
        
        // 1) Prefer true trend insights when available
        if trendCoverage?.hasMinimumCoverage == true, !trendInsights.isEmpty {
            #if DEBUG
            print("🔔 Building notifications from \(trendInsights.count) trend insights")
            #endif
            let filtered = trendInsights
                .filter { !$0.memberName.isEmpty }
            #if DEBUG
            print("🔔 After name filter: \(filtered.count) insights")
            #endif
            // Suppress stale negative alerts if the member is now doing well in that pillar.
            let relevanceFiltered = filtered.filter { ins in
                    switch ins.severity {
                    case .attention, .watch:
                        let keep = isStillRelevantNegativeAlert(memberUserId: ins.memberUserId, pillar: ins.pillar)
                        #if DEBUG
                        if !keep {
                            let currentScore = memberPillarScore(userId: ins.memberUserId, pillar: ins.pillar) ?? 0
                            print("🔔 Filtered out: \(ins.title) (current \(ins.pillar.displayName) score=\(currentScore) >= 85, member has recovered from past issue)")
                        }
                        #endif
                        return keep
                    case .celebrate:
                        return true
                    }
                }
            #if DEBUG
            print("🔔 After relevance filter: \(relevanceFiltered.count) insights")
            #endif
            let final = relevanceFiltered.prefix(5).map { ins in
                    let initials = makeInitials(from: ins.memberName)
                    return FamilyNotificationItem(
                        id: ins.id.uuidString,
                        kind: .trend(ins),
                        pillar: ins.pillar,
                        title: ins.title,
                        body: ins.body,
                        memberInitials: initials,
                        memberName: ins.memberName
                    )
                }
            #if DEBUG
            print("🔔 Final notification count: \(final.count)")
            for item in final {
                print("  - \(item.title)")
            }
            #endif
            return final
        }
        
        // 2) Fallback: derive a pillar per member from their pillar scores (Sleep / Activity / Stress)
        // This avoids hardcoding everything to the family's focus pillar.
        let others = members.filter { !$0.isMe && !$0.isPending && $0.hasScore && $0.isScoreFresh }
        guard !others.isEmpty else { return [] }
        
        func lowestPillar(for member: FamilyMemberScore) -> (pillar: VitalityPillar, score: Int)? {
            let sleep = memberPillarScore(userId: member.userId, factorName: "Sleep")
            let movement = memberPillarScore(userId: member.userId, factorName: "Activity")
            let stress = memberPillarScore(userId: member.userId, factorName: "Stress")
            let options: [(VitalityPillar, Int?)] = [(.sleep, sleep), (.movement, movement), (.stress, stress)]
            let present = options.compactMap { (pillar, value) -> (VitalityPillar, Int)? in
                value.map { (pillar, $0) }
            }
            guard let minPair = present.min(by: { $0.1 < $1.1 }) else { return nil }
            return (minPair.0, minPair.1)
        }
        
        return others.compactMap { m in
            guard let lp = lowestPillar(for: m) else { return nil }
            
            // Relevance gate (fallback): only create a notification if there is an actual issue right now.
            // This prevents "Terrible3 · Stress" from showing when all scores are 90+.
            let currentVsOptimalOK: Bool = (m.optimalScore > 0) ? (Double(m.currentScore) / Double(m.optimalScore) >= 0.90) : (m.currentScore >= 80)
            let pillarOK: Bool = lp.score >= 75
            if currentVsOptimalOK && pillarOK {
                return nil
            }
            
            let initials = m.initials
            let firstName = m.name.split(separator: " ").first.map(String.init) ?? m.name
            let title: String
            let body: String
            switch lp.pillar {
            case .sleep:
                title = "\(firstName) · Sleep"
                body = "Sleep is the biggest drag on \(firstName)'s vitality right now. A small bedtime consistency reset can help."
            case .movement:
                title = "\(firstName) · Movement"
                body = "Movement is trending low for \(firstName). A simple daily steps goal is a good first unlock."
            case .stress:
                title = "\(firstName) · Stress"
                body = "\(firstName)'s recovery signals look strained lately. Prioritizing rest and calm minutes can help."
            }
            return FamilyNotificationItem(
                id: (m.userId ?? m.name) + "-" + lp.pillar.rawValue,
                kind: .fallback(memberName: m.name, memberInitials: initials, memberUserId: m.userId, pillar: lp.pillar, title: title, body: body),
                pillar: lp.pillar,
                title: title,
                body: body,
                memberInitials: initials,
                memberName: m.name
            )
        }
        .prefix(3)
        .map { $0 }
    }
    
    private static func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.dropFirst().first?.prefix(1) ?? ""
        let combined = String(first + second)
        return combined.isEmpty ? String(name.prefix(2)).uppercased() : combined.uppercased()
    }
}

private struct FamilyNotificationsCard: View {
    let items: [FamilyNotificationItem]
    let onTap: (FamilyNotificationItem) -> Void
    
    private func pillarIcon(_ pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(_ pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return DashboardDesign.sleepColor
        case .movement: return DashboardDesign.movementColor
        case .stress: return DashboardDesign.stressColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            Text("Family notifications")
                .font(DashboardDesign.sectionHeaderFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            
            VStack(spacing: DashboardDesign.smallSpacing) {
                ForEach(items) { item in
                    Button {
                        onTap(item)
                    } label: {
                        HStack(spacing: DashboardDesign.internalSpacing) {
                            // Icon container (premium styling)
                            ZStack {
                                RoundedRectangle(cornerRadius: DashboardDesign.smallCornerRadius, style: .continuous)
                                    .fill(pillarColor(item.pillar).opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: pillarIcon(item.pillar))
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(pillarColor(item.pillar))
                            }
                            
                            // Text content (premium hierarchy)
                            VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
                                Text(item.title)
                                    .font(DashboardDesign.bodySemiboldFont)
                                    .foregroundColor(DashboardDesign.primaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.body)
                                    .font(DashboardDesign.secondaryFont)
                                    .foregroundColor(DashboardDesign.secondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer()
                            
                            // Chevron (premium alignment)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DashboardDesign.secondaryTextColor.opacity(0.5))
                        }
                        .padding(DashboardDesign.cardPadding)
                        .background(
                                RoundedRectangle(cornerRadius: DashboardDesign.smallCornerRadius, style: .continuous)
                                .fill(DashboardDesign.tertiaryBackgroundColor.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

private struct FamilyNotificationDetailSheet: View {
    let item: FamilyNotificationItem
    let onStartRecommendedChallenge: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    // MARK: - Pillar Configuration
    
    /// Configuration for each pillar/metric type
    private struct PillarConfig {
        let displayName: String
        let primaryMetricLabel: String  // "Steps", "Sleep", "HRV (recovery)"
        let primaryUnit: String         // "steps", "hours", "ms"
        let secondaryMetricLabel: String? // nil for Movement/Sleep, "Resting heart rate" for Stress
        let secondaryUnit: String?       // nil or "bpm"
        let optimalTargetLabel: String   // "Optimal steps", "Optimal sleep", "Optimal HRV"
        let fallbackExplanation: String
        
        static func forPillar(_ pillar: VitalityPillar) -> PillarConfig {
            switch pillar {
            case .sleep:
                return PillarConfig(
                    displayName: "Sleep",
                    primaryMetricLabel: "Sleep",
                    primaryUnit: "hours",
                    secondaryMetricLabel: nil,
                    secondaryUnit: nil,
                    optimalTargetLabel: "Optimal sleep",
                    fallbackExplanation: "Sleep quality and duration impact overall vitality."
                )
            case .movement:
                return PillarConfig(
                    displayName: "Movement",
                    primaryMetricLabel: "Steps",
                    primaryUnit: "steps",
                    secondaryMetricLabel: nil,
                    secondaryUnit: nil,
                    optimalTargetLabel: "Optimal steps",
                    fallbackExplanation: "Daily movement and activity levels support vitality."
                )
            case .stress:
                return PillarConfig(
                    displayName: "Stress",
                    primaryMetricLabel: "HRV (recovery)",
                    primaryUnit: "ms",
                    secondaryMetricLabel: "Resting heart rate",
                    secondaryUnit: "bpm",
                    optimalTargetLabel: "Optimal HRV",
                    fallbackExplanation: "Recovery signals like HRV and resting heart rate indicate stress levels."
                )
            }
        }
    }
    
    // MARK: - State
    
    @State private var selectedWindowDays: Int = 7
    @State private var historyRows: [(date: String, value: Int?)] = []
    @State private var rawMetrics: [(date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)] = []
    @State private var memberAge: Int?
    @State private var optimalTarget: (min: Double, max: Double)?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasMinimumCoverage = false
    @State private var showAskMiyaChat = false
    
    // AI Insight state
    @State private var aiInsightHeadline: String?
    @State private var aiInsightClinicalInterpretation: String?
    @State private var aiInsightDataConnections: String?
    @State private var aiInsightPossibleCauses: [String] = []
    @State private var aiInsightActionSteps: [String] = []
    @State private var aiInsightConfidence: String?
    @State private var aiInsightConfidenceReason: String?
    @State private var isLoadingAIInsight: Bool = false
    @State private var aiInsightError: String?
    @State private var suggestedMessages: [(label: String, text: String)] = []
    @State private var selectedSuggestedMessageIndex = 0
    @State private var showShareSheet = false
    @State private var aiInsightBaselineValue: Double?
    @State private var loadingStep: Int = 0  // For animated loading checklist
    @State private var isSection1Expanded: Bool = true  // What's Happening
    @State private var isSection2Expanded: Bool = false  // The Full Picture
    @State private var isSection3Expanded: Bool = false  // What Might Be Causing This
    @State private var isSection4Expanded: Bool = true  // What To Do Now (always defaults open)
    @State private var feedbackSubmitted: Bool = false
    @State private var feedbackIsHelpful: Bool? = nil
    @State private var aiInsightRecentValue: Double?
    @State private var aiInsightDeviationPercent: Double?
    
    private var config: PillarConfig {
        PillarConfig.forPillar(item.pillar)
    }
    
    // MARK: - Computed Properties
    
    private var severityLabel: String {
        switch item.kind {
        case .trend(let ins):
            switch ins.severity {
            case .celebrate: return "Trending up"
            case .watch: return "Watch"
            case .attention: return "Needs attention"
            }
        case .fallback:
            return "Needs attention"
        }
    }
    
    private var slicedHistory: [(date: String, value: Int?)] {
        Array(historyRows.suffix(selectedWindowDays))
    }
    
    private var averageValue: Double? {
        let values = slicedHistory.compactMap { $0.value }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    // Note: daysOffTarget and longestStreakOffTarget are now computed from raw metrics
    // See daysBelowOptimal and longestStreakBelowOptimal below
    
    // MARK: - Real Metrics Computed Properties
    
    private var slicedRawMetrics: [(date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)] {
        Array(rawMetrics.suffix(selectedWindowDays))
    }
    
    private var averageSteps: Double? {
        let values = slicedRawMetrics.compactMap { $0.steps }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    private var averageSleepHours: Double? {
        let values = slicedRawMetrics.compactMap { $0.sleepMinutes }
        guard !values.isEmpty else { return nil }
        let totalMinutes = values.reduce(0, +)
        return Double(totalMinutes) / Double(values.count) / 60.0
    }
    
    private var averageHRV: Double? {
        let values = slicedRawMetrics.compactMap { $0.hrvMs }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0.0) { $0 + $1 }) / Double(values.count)
    }
    
    private var averageRestingHR: Double? {
        let values = slicedRawMetrics.compactMap { $0.restingHr }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0.0) { $0 + $1 }) / Double(values.count)
    }
    
    private var daysBelowOptimal: Int {
        guard let optimal = optimalTarget else { return 0 }
        return slicedRawMetrics.filter { day in
            switch item.pillar {
            case .movement:
                guard let steps = day.steps else { return false }
                return Double(steps) < optimal.min
            case .sleep:
                guard let sleepMinutes = day.sleepMinutes else { return false }
                let sleepHours = Double(sleepMinutes) / 60.0
                return sleepHours < optimal.min
            case .stress:
                guard let hrv = day.hrvMs else { return false }
                return hrv < optimal.min
            }
        }.count
    }
    
    private var longestStreakBelowOptimal: Int {
        guard let optimal = optimalTarget else { return 0 }
        var maxStreak = 0
        var currentStreak = 0
        for day in slicedRawMetrics.reversed() {
            let isBelow: Bool
            switch item.pillar {
            case .movement:
                guard let steps = day.steps else {
                    isBelow = false
                    break
                }
                isBelow = Double(steps) < optimal.min
            case .sleep:
                guard let sleepMinutes = day.sleepMinutes else {
                    isBelow = false
                    break
                }
                let sleepHours = Double(sleepMinutes) / 60.0
                isBelow = sleepHours < optimal.min
            case .stress:
                guard let hrv = day.hrvMs else {
                    isBelow = false
                    break
                }
                isBelow = hrv < optimal.min
            }
            
            if isBelow {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        return maxStreak
    }
    
    // MARK: - Body
    
    @ViewBuilder
    private var whatsGoingOnContent: some View {
        if item.memberUserId == nil {
            // Graceful "no linked account" state
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No linked account yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("\(item.memberName) needs to complete onboarding to see detailed trends.")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else if isLoading {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.9)
                Text("Loading history...")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 8)
        } else if let error = loadError {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unable to load data")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else if historyRows.count < 7 {
            // Insufficient data state
            let daysAvailable = historyRows.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Need more data")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextPrimary)
                        
                        if daysAvailable == 0 {
                            Text("We need 7 days to detect a trend. No data is available yet.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("We need 7 days to detect a trend. Only \(daysAvailable) day\(daysAvailable == 1 ? "" : "s") \(daysAvailable == 1 ? "is" : "are") available so far.")
                                .font(.system(size: 13))
                                .foregroundColor(.miyaTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        } else {
            metricsDisplayView
        }
    }
    
    @ViewBuilder
    private var metricsDisplayView: some View {
        // Phase 2: prefer cached/GPT insight when available.
        if let h = aiInsightHeadline, let clinical = aiInsightClinicalInterpretation {
            VStack(alignment: .leading, spacing: 16) {
                // Medical Disclaimer (always visible)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    
                    Text("This insight is AI-generated to help you understand health trends. It is not medical advice and should not replace consultation with a healthcare provider. If you have medical concerns, please consult a doctor.")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                
                // Get baseline and recent values from AI insight evidence
                let baselineVal = getBaselineValue()
                let recentVal = getRecentValue()
                let deviationPct = getDeviationPercent()
                
                // Key metrics card - shows baseline vs current vs optimal prominently
                if let baseline = baselineVal, let recent = recentVal {
                    VStack(spacing: 16) {
                        // Baseline vs Current
                        HStack(spacing: 20) {
                            // Baseline
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Baseline")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Text(formatMetricValue(baseline))
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundColor(.miyaTextPrimary)
                            }
                            
                            // Arrow indicator
                            Image(systemName: deviationPct < 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(deviationPct < 0 ? .red.opacity(0.7) : .green.opacity(0.7))
                                .padding(.top, 12)
                            
                            // Current
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Text(formatMetricValue(recent))
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundColor(deviationPct < 0 ? .red : .green)
                            }
                            
                            Spacer()
                        }
                        
                        // Change indicator
                        if deviationPct != 0 {
                            HStack(spacing: 6) {
                                Image(systemName: deviationPct < 0 ? "arrow.down" : "arrow.up")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(abs(Int(deviationPct * 100)))% change")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(deviationPct < 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(deviationPct < 0 ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                            )
                        }
                        
                        // Optimal range (if available)
                        if let optimal = optimalTarget {
                            Divider()
                            HStack {
                                Text(config.optimalTargetLabel)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.miyaTextSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.3)
                                Spacer()
                                Text(formatOptimalRange(optimal))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.green.opacity(0.8))
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                
                // Headline
                Text(h)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Section 1: What's Happening (Clinical Interpretation) - DEFAULT EXPANDED
                ExpandableInsightSection(
                    icon: "📊",
                    title: "What's Happening",
                    isExpanded: $isSection1Expanded,
                    backgroundColor: Color.blue.opacity(0.08)
                ) {
                    Text(clinical)
                        .font(.system(size: 16))
                    .foregroundColor(.miyaTextPrimary)
                        .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                }
                
                // Section 2: The Full Picture (Data Connections) - DEFAULT COLLAPSED
                if let dataConnections = aiInsightDataConnections, !dataConnections.isEmpty {
                    ExpandableInsightSection(
                        icon: "🔍",
                        title: "The Full Picture",
                        isExpanded: $isSection2Expanded,
                        backgroundColor: Color.purple.opacity(0.08)
                    ) {
                        Text(dataConnections)
                            .font(.system(size: 16))
                                .foregroundColor(.miyaTextPrimary)
                            .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Section 3: What Might Be Causing This - DEFAULT COLLAPSED
                if !aiInsightPossibleCauses.isEmpty {
                    ExpandableInsightSection(
                        icon: "💡",
                        title: "What Might Be Causing This",
                        isExpanded: $isSection3Expanded,
                        backgroundColor: Color.orange.opacity(0.08)
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(aiInsightPossibleCauses.enumerated()), id: \.element) { index, cause in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    Text(cause)
                                        .font(.system(size: 16))
                                        .foregroundColor(.miyaTextPrimary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                
                // Section 4: What To Do Now - DEFAULT EXPANDED (ALWAYS)
                if !aiInsightActionSteps.isEmpty {
                    ExpandableInsightSection(
                        icon: "✅",
                        title: "What To Do Now",
                        isExpanded: $isSection4Expanded,
                        backgroundColor: Color.green.opacity(0.08)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(aiInsightActionSteps.enumerated()), id: \.element) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.green.opacity(0.15))
                                            .frame(width: 26, height: 26)
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                    .padding(.top, 2)
                                    
                                    Text(step)
                                        .font(.system(size: 16))
                                .foregroundColor(.miyaTextPrimary)
                                        .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                
                // Feedback buttons (after action steps)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Was this insight helpful?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                    
                    if feedbackSubmitted {
                        // Thank you message
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Thank you for your feedback!")
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    } else {
                        // Feedback buttons
                        HStack(spacing: 16) {
                            Button {
                                submitFeedback(isHelpful: true)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("👍")
                                        .font(.system(size: 20))
                                    Text("Yes")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                submitFeedback(isHelpful: false)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("👎")
                                        .font(.system(size: 20))
                                    Text("No")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                
                if let c = aiInsightConfidence, let why = aiInsightConfidenceReason, !c.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: c == "high" ? "checkmark.circle.fill" : c == "medium" ? "info.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(c == "high" ? .green : c == "medium" ? .orange : .red)
                    Text("Confidence: \(c) — \(why)")
                            .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.top, 4)
                }
                
                if let err = aiInsightError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 6)
        } else if isLoadingAIInsight {
            // Enhanced loading state with animated steps
            VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Analyzing \(item.memberName)'s health patterns...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.miyaTextPrimary)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    LoadingStepRow(step: 0, currentStep: loadingStep, text: "Reviewing movement data")
                    LoadingStepRow(step: 1, currentStep: loadingStep, text: "Checking sleep patterns")
                    LoadingStepRow(step: 2, currentStep: loadingStep, text: "Analyzing stress indicators")
                    LoadingStepRow(step: 3, currentStep: loadingStep, text: "Connecting the dots")
                }
                .padding(.leading, 8)
                
                Text("This usually takes 10-15 seconds")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.bottom, 8)
            .onAppear {
                // Animate through the steps
                loadingStep = 0
                Task {
                    for i in 0..<4 {
                        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds per step
                        await MainActor.run {
                            loadingStep = i + 1
                        }
                    }
                }
            }
        } else {
            // Headline sentence (pillar-specific fallback)
            let headline: String = {
                switch item.pillar {
                case .movement:
                    return "They're moving less than their optimal level."
                case .sleep:
                    return "Their sleep has been below their optimal level."
                case .stress:
                    return "Recovery signals suggest higher stress recently."
                }
            }()
            
            Text(headline)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
                .padding(.bottom, 12)
        }
        
        // Real metrics display (pillar-specific)
        VStack(spacing: 12) {
            switch item.pillar {
            case .movement:
                movementMetricsView
            case .sleep:
                sleepMetricsView
            case .stress:
                stressMetricsView
            }
        }
    }
    
    @ViewBuilder
    private var movementMetricsView: some View {
        if let avgSteps = averageSteps {
            HStack {
                Text("Average steps (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatSteps(Int(avgSteps.rounded())))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal average steps")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) steps")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal average steps")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
        
        if daysBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Days below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(daysBelowOptimal)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if longestStreakBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Longest streak below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(longestStreakBelowOptimal) days")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var sleepMetricsView: some View {
        if let avgSleep = averageSleepHours {
            HStack {
                Text("Average sleep (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(String(format: "%.1fh", avgSleep))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal sleep")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(String(format: "%.1f-%.1fh", optimal.min, optimal.max))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal sleep")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
        
        if daysBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Nights below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(daysBelowOptimal)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if longestStreakBelowOptimal > 0 {
            Divider()
            HStack {
                Text("Longest streak below optimal")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(longestStreakBelowOptimal) nights")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var stressMetricsView: some View {
        if let avgHRV = averageHRV {
            HStack {
                Text("Average HRV (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatHRV(avgHRV))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let avgRHR = averageRestingHR {
            HStack {
                Text("Average resting heart rate (last \(selectedWindowDays) days)")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text(formatRestingHR(avgRHR))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        }
        
        if let optimal = optimalTarget {
            Divider()
            HStack {
                Text("Optimal HRV")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            }
            .padding(.vertical, 4)
        } else {
            Divider()
            HStack {
                Text("Optimal HRV")
                    .font(.system(size: 15))
                    .foregroundColor(.miyaTextSecondary)
                Spacer()
                Text("Not set yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Premium Header with gradient background
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.memberName) · \(config.displayName)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("\(severityLabel) · Last \(selectedWindowDays) days")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.miyaTextSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.miyaBackground.opacity(0.5), Color.miyaBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // "What's going on" summary card (premium design)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What's going on")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.bottom, 4)
                        
                        whatsGoingOnContent
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                    
                    // Reach Out Section - ELEVATED DESIGN (only if AI insight loaded)
                    if !suggestedMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            // Header with icon
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reach Out")
                                        .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)
                                    Text("Share this insight with \(item.memberName)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.miyaTextSecondary)
                                }
                                
                                Spacer()
                            }
                            
                            Picker("Message style", selection: $selectedSuggestedMessageIndex) {
                                ForEach(0..<suggestedMessages.count, id: \.self) { idx in
                                    Text(suggestedMessages[idx].label).tag(idx)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Text(selectedShareText)
                                .font(.system(size: 15))
                                .foregroundColor(.miyaTextPrimary)
                                .lineSpacing(4)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                            
                            VStack(spacing: 12) {
                                // WhatsApp Button
                                Button {
                                    openWhatsApp(with: selectedShareText)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Send via WhatsApp")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "arrow.up.forward")
                                            .font(.system(size: 14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color(red: 0.15, green: 0.79, blue: 0.47)) // WhatsApp green
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                // Messages/SMS Button
                                Button {
                                    openMessages(with: selectedShareText)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "message.badge.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Send via Text Message")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "arrow.up.forward")
                                            .font(.system(size: 14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                // Keep the generic share sheet as a fallback
                                Button {
                                    showShareSheet = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("More Options...")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.miyaTextPrimary)
                                    .cornerRadius(12)
                                }
                                .sheet(isPresented: $showShareSheet) {
                                    MiyaShareSheetView(activityItems: [selectedShareText])
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    
                    // Ask Miya button (moved here, directly under "What's going on" card)
                    if item.memberUserId != nil {
                        Button {
                            #if DEBUG
                            print("📤 ASK_MIYA_TAPPED: pillar=\(item.pillar.rawValue) window=\(selectedWindowDays) userId=\(item.memberUserId ?? "nil")")
                            #endif
                            let payload = buildMiyaPayload()
                            #if DEBUG
                            print("📤 ASK_MIYA_PAYLOAD: \(payload)")
                            #endif
                            showAskMiyaChat = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.purple)
                                }
                                
                                Text("Ask Miya")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .disabled(item.memberUserId == nil)
                        .opacity(item.memberUserId == nil ? 0.6 : 1.0)
                    }
                    
                    // Segmented control (7/14/21 days)
                    if item.memberUserId != nil && hasMinimumCoverage {
                        Picker("Window", selection: $selectedWindowDays) {
                            Text("Last 7").tag(7)
                            Text("Last 14").tag(14)
                            Text("Last 21").tag(21)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                    }
                    
                    // Expandable trend details (premium design)
                    if item.memberUserId != nil && hasMinimumCoverage {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Daily breakdown")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                                .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                DisclosureGroup {
                                    dayByDayRows(Array(historyRows.suffix(7)))
                                } label: {
                                    Text("Last 7 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                                
                                DisclosureGroup {
                                    dayByDayRows(Array(historyRows.suffix(14)))
                                } label: {
                                    Text("Last 14 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                                
                                DisclosureGroup {
                                    dayByDayRows(historyRows)
                                } label: {
                                    Text("Last 21 days")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Actions section (premium design)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Actions")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.miyaTextPrimary)
                            .padding(.horizontal, 20)
                        
                        // Contact buttons (premium design with brand colors)
                        VStack(spacing: 10) {
                            Button {
                                // TODO: Open WhatsApp
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.green.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                    
                                    Text("WhatsApp")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                            
                            Button {
                                // TODO: Open Messages
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text("Text")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                            
                            Button {
                                // TODO: Open FaceTime
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text("FaceTime")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Spacer()
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                )
                            }
                            .disabled(true)
                        }
                        .padding(.horizontal, 20)
                        
                        Text("Add contact info to enable")
                            .font(.system(size: 13))
                            .foregroundColor(.miyaTextSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, -8)
                        
                        // Commit Together (primary CTA)
                        Button {
                            dismiss()
                            onStartRecommendedChallenge()
                        } label: {
                            Text(commitTogetherLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.miyaPrimary, Color.miyaPrimary.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: Color.miyaPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showAskMiyaChat) {
                MiyaInsightChatSheet(alertItem: item)
            }
            .alert("Data loading", isPresented: .constant(false)) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We're building personalized insights based on this data. Check back soon!")
            }
            .task {
                await loadHistory()
                await calculateOptimalTarget()
                await fetchAIInsightIfPossible()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadHistory() async {
        // Gracefully handle nil memberUserId (no red error box)
        guard let userId = item.memberUserId else {
            await MainActor.run {
                isLoading = false
                loadError = nil
                historyRows = []
                rawMetrics = []
                hasMinimumCoverage = false
            }
            #if DEBUG
            print("📊 FamilyNotificationDetailSheet: No memberUserId for \(item.memberName) - showing graceful state")
            #endif
            return
        }
        
        await MainActor.run {
            isLoading = true
            loadError = nil
            selectedWindowDays = item.triggerWindowDays ?? 7
        }
        
        #if DEBUG
        print("📊 INSIGHT_DETAIL_OPENED: memberName=\(item.memberName) userId=\(userId) pillar=\(item.pillar.rawValue) window=\(selectedWindowDays)")
        print("📊 FamilyNotificationDetailSheet: Loading history for \(item.memberName) (userId: \(userId), pillar: \(item.pillar.rawValue), days: 21)")
        #endif
        
        do {
            // Fetch pillar scores from vitality_scores
            let pillarRows = try await dataManager.fetchUserPillarHistory(
                userId: userId,
                pillar: item.pillar,
                days: 21
            )
            
            // Fetch raw metrics from wearable_daily_metrics
            let wearableRows = try await dataManager.fetchWearableDailyMetricsForUser(userId: userId, days: 21)
            
            // Deduplicate pillar rows by date
            let deduplicatedPillarRows = Dictionary(grouping: pillarRows, by: { $0.date })
                .compactMapValues { dayRows -> (date: String, value: Int?)? in
                    let sorted = dayRows.sorted { ($0.value ?? -1) > ($1.value ?? -1) }
                    return sorted.first
                }
                .values
                .sorted { $0.date < $1.date }
            
            // Convert wearable rows to our format and merge by date
            let rawMetricsDict = Dictionary(grouping: wearableRows, by: { $0.metricDate })
                .compactMapValues { dayRows -> (steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)? in
                    // If multiple rows for same date, prefer rows with more data
                    let sorted = dayRows.sorted { row1, row2 in
                        let count1 = [row1.steps, row1.sleepMinutes, row1.hrvMs, row1.restingHr].compactMap { $0 }.count
                        let count2 = [row2.steps, row2.sleepMinutes, row2.hrvMs, row2.restingHr].compactMap { $0 }.count
                        return count1 > count2
                    }
                    guard let best = sorted.first else { return nil }
                    return (best.steps, best.sleepMinutes, best.hrvMs, best.restingHr)
                }
            
            // Create merged raw metrics array sorted by date
            let mergedRawMetrics = rawMetricsDict.map { (date, metrics) in
                (date: date, steps: metrics.steps, sleepMinutes: metrics.sleepMinutes, hrvMs: metrics.hrvMs, restingHr: metrics.restingHr)
            }.sorted { $0.date < $1.date }
            
            await MainActor.run {
                historyRows = deduplicatedPillarRows
                rawMetrics = mergedRawMetrics
                hasMinimumCoverage = deduplicatedPillarRows.count >= 7
                isLoading = false
                
                #if DEBUG
                print("📊 FamilyNotificationDetailSheet: Loaded \(deduplicatedPillarRows.count) pillar rows, \(mergedRawMetrics.count) raw metric rows")
                if deduplicatedPillarRows.count < 7 {
                    print("  ⚠️ Insufficient coverage: \(deduplicatedPillarRows.count) < 7 days")
                }
                #endif
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
                hasMinimumCoverage = false
                historyRows = []
                rawMetrics = []
            }
            #if DEBUG
            print("❌ FamilyNotificationDetailSheet: Error loading history: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func calculateOptimalTarget() async {
        guard let userId = item.memberUserId else {
            await MainActor.run { optimalTarget = nil }
            return
        }
        
        // Fetch age
        let age = try? await dataManager.fetchMemberAge(userId: userId)
        await MainActor.run { memberAge = age }
        
        guard let age = age else {
            await MainActor.run { optimalTarget = nil }
            return
        }
        
        // Get age group
        let ageGroup = AgeGroup.from(age: age)
        
        // Get optimal range from ScoringSchema based on pillar
        let range: (min: Double, max: Double)?
        switch item.pillar {
        case .movement:
            // Get steps optimal range
            if let stepsDef = vitalityScoringSchema
                .first(where: { $0.id == .movement })?
                .subMetrics.first(where: { $0.id == .steps }),
               let benchmarks = stepsDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        case .sleep:
            // Get sleep duration optimal range
            if let sleepDef = vitalityScoringSchema
                .first(where: { $0.id == .sleep })?
                .subMetrics.first(where: { $0.id == .sleepDuration }),
               let benchmarks = sleepDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        case .stress:
            // Get HRV optimal range
            if let hrvDef = vitalityScoringSchema
                .first(where: { $0.id == .stress })?
                .subMetrics.first(where: { $0.id == .hrv }),
               let benchmarks = hrvDef.ageSpecificBenchmarks.byAgeGroup[ageGroup] {
                range = (benchmarks.optimalMin, benchmarks.optimalMax)
            } else {
                range = nil
            }
        }
        
        await MainActor.run { optimalTarget = range }
    }
    
    // MARK: - Formatter Helpers
    
    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: steps)) ?? "\(steps)") steps"
    }
    
    private func formatSleepMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
    
    private func formatHRV(_ hrv: Double) -> String {
        return "\(Int(hrv.rounded())) ms"
    }
    
    private func formatRestingHR(_ hr: Double) -> String {
        return "\(Int(hr.rounded())) bpm"
    }
    
    private func dayByDayRows(_ rows: [(date: String, value: Int?)]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.reversed()), id: \.date) { row in
                dayByDayRow(row: row)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func dayByDayRow(row: (date: String, value: Int?)) -> some View {
        // Find matching raw metric for this date
        let rawMetric = rawMetrics.first(where: { $0.date == row.date })
        
        HStack(spacing: 16) {
            // Date
            Text(formatDate(row.date))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.miyaTextPrimary)
                .frame(width: 90, alignment: .leading)
            
            // Real metric value (pillar-specific)
            dayByDayMetricValue(rawMetric: rawMetric)
            
            Spacer()
            
            // Optimal target and indicator
            dayByDayOptimalIndicator(rawMetric: rawMetric)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
    
    @ViewBuilder
    private func dayByDayMetricValue(rawMetric: (date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)?) -> some View {
        switch item.pillar {
        case .movement:
            if let steps = rawMetric?.steps {
                Text(formatSteps(steps))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
        case .sleep:
            if let sleepMinutes = rawMetric?.sleepMinutes {
                Text(formatSleepMinutes(sleepMinutes))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
        case .stress:
            VStack(alignment: .leading, spacing: 2) {
                if let hrv = rawMetric?.hrvMs {
                    Text(formatHRV(hrv))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                }
                if let rhr = rawMetric?.restingHr {
                    Text(formatRestingHR(rhr))
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                }
                if rawMetric?.hrvMs == nil && rawMetric?.restingHr == nil {
                    Text("—")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func dayByDayOptimalIndicator(rawMetric: (date: String, steps: Int?, sleepMinutes: Int?, hrvMs: Double?, restingHr: Double?)?) -> some View {
        if let optimal = optimalTarget {
            let isBelowOptimal: Bool = {
                switch item.pillar {
                case .movement:
                    if let steps = rawMetric?.steps {
                        return Double(steps) < optimal.min
                    } else {
                        return false
                    }
                case .sleep:
                    if let sleepMinutes = rawMetric?.sleepMinutes {
                        let sleepHours = Double(sleepMinutes) / 60.0
                        return sleepHours < optimal.min
                    } else {
                        return false
                    }
                case .stress:
                    if let hrv = rawMetric?.hrvMs {
                        return hrv < optimal.min
                    } else {
                        return false
                    }
                }
            }()
            
            HStack(spacing: 8) {
                switch item.pillar {
                case .movement:
                    Text("Opt: \(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded()))")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                case .sleep:
                    Text(String(format: "Opt: %.1f-%.1fh", optimal.min, optimal.max))
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                case .stress:
                    Text("Opt: \(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                }
                
                // Indicator
                if rawMetric != nil {
                    Circle()
                        .fill(isBelowOptimal ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        } else {
            if rawMetric == nil {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        return displayFormatter.string(from: date)
    }
    
    private var commitTogetherLabel: String {
        switch item.pillar {
        case .sleep:
            return "Plan a wind-down routine together"
        case .movement:
            return "Commit to walking together daily"
        case .stress:
            return "Do a 5-min reset together"
        }
    }
    
    private func buildMiyaPayload() -> [String: Any] {
        let sliced = slicedHistory
        let optimalMin = optimalTarget?.min ?? 0.0
        let optimalMax = optimalTarget?.max ?? 0.0
        return [
            "memberName": item.memberName,
            "memberUserId": item.memberUserId ?? "",
            "pillar": item.pillar.rawValue,
            "selectedWindowDays": selectedWindowDays,
            "optimalTarget": ["min": optimalMin, "max": optimalMax],
            "dailyValues": sliced.map { ["date": $0.date, "value": $0.value ?? 0] },
            "summary": [
                "average": averageValue ?? 0,
                "daysBelowOptimal": daysBelowOptimal,
                "longestStreakBelowOptimal": longestStreakBelowOptimal
            ],
            "triggerReason": item.debugWhy ?? config.fallbackExplanation
        ]
    }
    
    private func fetchAIInsightIfPossible() async {
        print("🤖 AI_INSIGHT: fetchAIInsightIfPossible() called for \(item.memberName)")
        print("🤖 AI_INSIGHT: debugWhy = \(item.debugWhy ?? "nil")")
        
        // Only fetch for server pattern alerts with an alertStateId
        guard let debugWhy = item.debugWhy else {
            print("❌ AI_INSIGHT: No debugWhy found - exiting")
            return
        }
        
        guard debugWhy.contains("serverPattern") else {
            print("❌ AI_INSIGHT: debugWhy does not contain 'serverPattern' - exiting")
            return
        }
        
        guard let alertStateId = extractAlertStateId(from: debugWhy) else {
            print("❌ AI_INSIGHT: Could not extract alertStateId from debugWhy - exiting")
            return
        }
        
        print("✅ AI_INSIGHT: Found alertStateId = \(alertStateId)")
        
        await MainActor.run {
            isLoadingAIInsight = true
            aiInsightError = nil
        }
        
        do {
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight") else { throw URLError(.badURL) }
            
            print("🌐 AI_INSIGHT: Calling Edge Function at \(url)")
            print("🌐 AI_INSIGHT: Payload = {\"alert_state_id\": \"\(alertStateId)\"}")
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            print("📥 AI_INSIGHT: Response status = \(httpStatus)")
            print("📥 AI_INSIGHT: Response data = \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                print("❌ AI_INSIGHT: Edge Function returned error: \(errBody)")
                throw NSError(domain: "miya_insight", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "AI insight failed (status \(httpStatus)): \(errBody)"])
            }
            
            print("✅ AI_INSIGHT: Successfully received response")
            
            await MainActor.run {
                aiInsightHeadline = obj?["headline"] as? String
                aiInsightClinicalInterpretation = obj?["clinical_interpretation"] as? String
                aiInsightDataConnections = obj?["data_connections"] as? String
                aiInsightPossibleCauses = obj?["possible_causes"] as? [String] ?? []
                aiInsightActionSteps = obj?["action_steps"] as? [String] ?? []
                aiInsightConfidence = obj?["confidence"] as? String
                aiInsightConfidenceReason = obj?["confidence_reason"] as? String
                
                print("📊 AI_INSIGHT: Parsed fields:")
                print("  - headline: \(aiInsightHeadline ?? "nil")")
                print("  - clinical_interpretation: \(aiInsightClinicalInterpretation?.prefix(50) ?? "nil")...")
                print("  - data_connections: \(aiInsightDataConnections?.prefix(50) ?? "nil")...")
                print("  - possible_causes: \(aiInsightPossibleCauses.count) items")
                print("  - action_steps: \(aiInsightActionSteps.count) items")
                
                // Extract evidence data for metric display
                if let evidence = obj?["evidence"] as? [String: Any] {
                    aiInsightBaselineValue = evidence["baseline_value"] as? Double
                    aiInsightRecentValue = evidence["recent_value"] as? Double
                    aiInsightDeviationPercent = evidence["deviation_percent"] as? Double
                    print("  - evidence baseline: \(aiInsightBaselineValue ?? 0)")
                    print("  - evidence recent: \(aiInsightRecentValue ?? 0)")
                    print("  - evidence deviation: \(aiInsightDeviationPercent ?? 0)")
                }
                
                if let ms = obj?["message_suggestions"] as? [[String: Any]] {
                    suggestedMessages = ms.compactMap { d in
                        guard let label = d["label"] as? String, let text = d["text"] as? String else { return nil }
                        return (label: label, text: text)
                    }
                    print("  - message_suggestions: \(suggestedMessages.count) items")
                }
            }
        } catch {
            print("❌ AI_INSIGHT: Error occurred: \(error)")
            print("❌ AI_INSIGHT: Error description: \(error.localizedDescription)")
            print("❌ AI_INSIGHT: Error type: \(type(of: error))")
            if let urlError = error as? URLError {
                print("❌ AI_INSIGHT: URLError code: \(urlError.code)")
            }
            if let nsError = error as? NSError {
                print("❌ AI_INSIGHT: NSError domain: \(nsError.domain)")
                print("❌ AI_INSIGHT: NSError code: \(nsError.code)")
                print("❌ AI_INSIGHT: NSError userInfo: \(nsError.userInfo)")
            }
            await MainActor.run {
                aiInsightError = error.localizedDescription
            }
        }
        
        await MainActor.run { isLoadingAIInsight = false }
    }
    
    private func extractAlertStateId(from debugWhy: String) -> String? {
        // Format: "serverPattern ... alertStateId=<uuid> ..."
        let pattern = "alertStateId=([a-f0-9-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: debugWhy, options: [], range: NSRange(debugWhy.startIndex..., in: debugWhy)),
              let range = Range(match.range(at: 1), in: debugWhy)
        else { return nil }
        return String(debugWhy[range])
    }
    
    private func getBaselineValue() -> Double? {
        return aiInsightBaselineValue
    }
    
    private func getRecentValue() -> Double? {
        return aiInsightRecentValue
    }
    
    private func getDeviationPercent() -> Double {
        return aiInsightDeviationPercent ?? 0
    }
    
    private func submitFeedback(isHelpful: Bool) {
        // Extract alert state ID from debugWhy
        guard let debugWhy = item.debugWhy,
              debugWhy.contains("serverPattern"),
              let alertStateId = extractAlertStateId(from: debugWhy)
        else {
            print("❌ FEEDBACK: Could not extract alertStateId")
            return
        }
        
        Task {
            do {
                let supabase = SupabaseConfig.client
                let userId = try await supabase.auth.session.user.id
                
                // Create feedback record
                struct FeedbackInsert: Encodable {
                    let alert_state_id: String
                    let user_id: String
                    let is_helpful: Bool
                }
                
                let feedback = FeedbackInsert(
                    alert_state_id: alertStateId,
                    user_id: userId.uuidString,
                    is_helpful: isHelpful
                )
                
                // Insert feedback into database
                try await supabase
                    .from("alert_insight_feedback")
                    .insert(feedback)
                    .execute()
                
                await MainActor.run {
                    feedbackSubmitted = true
                    feedbackIsHelpful = isHelpful
                }
                
                print("✅ FEEDBACK: Submitted \(isHelpful ? "helpful" : "not helpful") for alert \(alertStateId)")
            } catch {
                print("❌ FEEDBACK: Failed to submit - \(error.localizedDescription)")
                // Don't show error to user, just log it
            }
        }
    }
    
    private func openWhatsApp(with message: String) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try WhatsApp first
        if let url = URL(string: "whatsapp://send?text=\(encoded)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback: Open WhatsApp in App Store if not installed
            if let appStoreURL = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997") {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }
    
    private func openMessages(with message: String, phoneNumber: String? = nil) {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var urlString = "sms:"
        if let phone = phoneNumber {
            urlString += phone
        }
        urlString += "&body=\(encoded)"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func formatMetricValue(_ value: Double) -> String {
        let unit = config.primaryUnit
        
        // Format based on metric type
        switch item.pillar {
        case .sleep:
            // Convert minutes to hours
            let hours = value / 60.0
            return String(format: "%.1fh", hours)
        case .movement:
            // Steps
            return String(format: "%.0f", value)
        case .stress:
            // HRV or HR
            if config.primaryMetricLabel.contains("HRV") {
                return String(format: "%.0f ms", value)
            } else {
                return String(format: "%.0f bpm", value)
            }
        }
    }
    
    private func formatOptimalRange(_ optimal: (min: Double, max: Double)) -> String {
        switch item.pillar {
        case .sleep:
            // Convert minutes to hours for sleep
            return String(format: "%.1f-%.1fh", optimal.min, optimal.max)
        case .movement:
            // Steps
            return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) steps"
        case .stress:
            // HRV in ms
            if config.primaryMetricLabel.contains("HRV") {
                return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) ms"
            } else {
                return "\(Int(optimal.min.rounded()))-\(Int(optimal.max.rounded())) bpm"
            }
        }
    }
    
    private var selectedShareText: String {
        guard selectedSuggestedMessageIndex < suggestedMessages.count else {
            return "Hey, just checking in on you."
        }
        return suggestedMessages[selectedSuggestedMessageIndex].text
    }
}

// MARK: - Debug Upload Picker (choose which family member to apply the dataset to)

#if DEBUG
private struct DebugUploadPickerView: View {
    let members: [FamilyMemberScore]
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Text("Choose who this dataset belongs to. This will write vitality history for that user_id so trends/notifications can be tested without logging in/out.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            
            Section("Family members") {
                ForEach(members.filter { $0.userId != nil }) { m in
                    NavigationLink {
                        VitalityImportView(overrideUserId: m.userId)
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    } label: {
                        HStack {
                            Text(m.isMe ? "\(m.name) (Me)" : m.name)
                            Spacer()
                            Text(m.initials)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Upload dataset (debug)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}
#endif

private struct FamilyVitalityInsightsCard: View {
    let snapshot: FamilyVitalitySnapshot
    let trendInsights: [TrendInsight]
    let trendCoverage: TrendCoverageStatus?
    let membersWithData: Int?
    let membersTotal: Int?
    let onStartChallenge: (VitalityPillar) -> Void

    // MARK: - Pillar Visual Mapping
    
    private func pillarIcon(for pillar: VitalityPillar?) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        case .none: return "sparkles"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar?) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        case .none: return .miyaPrimary
        }
    }
    
    /// Whether we have actionable trend insights to show
    private var hasTrendInsights: Bool {
        !trendInsights.isEmpty
    }
    
    private var recommendations: [FamilyRecommendationRow] {
        FamilyRecommendationEngine.build(
            snapshot: snapshot,
            trendInsights: trendInsights,
            coverage: trendCoverage
        )
    }
    
    private var coverageState: (title: String, subtitle: String)? {
        guard let cov = trendCoverage else { return nil }
        if cov.daysAvailable == 0 {
            // Don't show this message - we're already showing snapshot insights below
            // The user is getting value from current-state insights, no need to confuse with "no trends"
            return nil
        }
        if !cov.hasMinimumCoverage {
            return ("Collecting your baseline", "Need \(cov.needMoreDataDays) more day\(cov.needMoreDataDays == 1 ? "" : "s") to detect patterns (based on last 21 days).")
        }
        return nil
    }
    
    /// The primary pillar to focus on (from trends or fallback to snapshot)
    private var primaryPillar: VitalityPillar? {
        trendInsights.first?.pillar ?? snapshot.focusPillar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // SECTION HEADER
            if hasTrendInsights {
                Text("What needs attention this week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            // TREND INSIGHT CARDS (highest priority - only show if we have trend data)
            if trendCoverage?.hasMinimumCoverage == true && hasTrendInsights {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(trendInsights.prefix(2)) { insight in
                        TrendInsightCard(insight: insight) {
                            onStartChallenge(insight.pillar)
                        }
                    }
                }
            } else if trendCoverage?.hasMinimumCoverage == true && !hasTrendInsights {
                // Have trend data but no insights detected
                VStack(alignment: .leading, spacing: 6) {
                    Text("No patterns detected")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Text("We'll alert you when a meaningful change appears.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if snapshot.membersIncluded == 0 {
                // No members with data at all
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No recent data yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Connect wearables and sync data to see family insights.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            } else {
                // FALLBACK: Show snapshot-based insights (from current member scores)
                // This shows even when we don't have trend data yet
                
                // Show coverage message as informational context (not a blocker)
                if let cov = coverageState {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cov.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        Text(cov.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Show snapshot headline and help cards
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(pillarColor(for: primaryPillar).opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: pillarIcon(for: primaryPillar))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(pillarColor(for: primaryPillar))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let sub = snapshot.subheadline {
                            Text(sub)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Show help cards from snapshot (member-based insights)
                if !snapshot.helpCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.helpCards.prefix(2)) { card in
                            FamilyHelpActionCard(card: card) {
                                onStartChallenge(card.focusPillar)
                            }
                        }
                    }
                }
            }
            
            // ACTIONABLE RECOMMENDATIONS (if coverage ok and insights exist)
            if trendCoverage?.hasMinimumCoverage == true && !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What to do this week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(recommendations.prefix(2)) { row in
                        RecommendationRowView(row: row, onTap: {
                            onStartChallenge(row.pillar)
                        })
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Trend Insight Card

private struct TrendInsightCard: View {
    let insight: TrendInsight
    let onAction: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    private func severityColor(for severity: TrendSeverity) -> Color {
        switch severity {
        case .attention: return .orange
        case .watch: return .yellow
        case .celebrate: return .green
        }
    }
    
    private func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: Avatar + Title
            HStack(spacing: 10) {
                // Avatar with pillar color
                Circle()
                    .fill(pillarColor(for: insight.pillar).opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(makeInitials(from: insight.memberName))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pillarColor(for: insight.pillar))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    // Title: "Dad · Sleep"
                    Text(insight.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Body: one-liner insight
                    Text(insight.body)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            // CTA Button
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Image(systemName: pillarIcon(for: insight.pillar))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start \(insight.pillar.displayName) Challenge")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pillarColor(for: insight.pillar))
                .foregroundColor(.white)
                .cornerRadius(999)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Recommendation Row View

private struct RecommendationRowView: View {
    let row: FamilyRecommendationRow
    let onTap: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "bed.double.fill"
        case .movement: return "figure.walk"
        case .stress: return "exclamationmark.circle"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pillarIcon(for: row.pillar))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(pillarColor(for: row.pillar))
                .frame(width: 20)
            
            Text(row.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Family Help Action Card (Premium Style)

private struct FamilyHelpActionCard: View {
    let card: MemberHelpCard
    let onAction: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    private func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Member row
            HStack(spacing: 10) {
                // Avatar
                Circle()
                    .fill(pillarColor(for: card.focusPillar).opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(makeInitials(from: card.memberName))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pillarColor(for: card.focusPillar))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(card.recommendation)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            // CTA Button (full width, pill style)
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Image(systemName: pillarIcon(for: card.focusPillar))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start \(card.focusPillar.displayName) Challenge")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pillarColor(for: card.focusPillar))
                .foregroundColor(.white)
                .cornerRadius(999)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Ask Miya Chat Sheet

private struct MiyaInsightChatSheet: View {
    let alertItem: FamilyNotificationItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isSending = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if errorText != nil || messages.isEmpty {
                    VStack(spacing: 12) {
                        if let err = errorText {
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                        if messages.isEmpty {
                            Text("Ask a question about this pattern")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            HStack {
                                if msg.role == "user" {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .trailing)
                                } else {
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .leading)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                    }
                    .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Ask Miya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        errorText = nil
        
        messages.append((role: "user", text: text))
        isSending = true
        defer { isSending = false }
        
        do {
            // Extract alert_state_id from debugWhy (format: "serverPattern ... alertStateId=<uuid> ...")
            guard let debugWhy = alertItem.debugWhy,
                  debugWhy.contains("serverPattern"),
                  let alertStateId = extractAlertStateId(from: debugWhy)
            else {
                errorText = "Ask Miya is available for server pattern alerts."
                return
            }
            
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight_chat") else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId, "message": text])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                throw NSError(domain: "miya_insight_chat", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Chat failed (status \(httpStatus)): \(errBody)"])
            }
            let reply = obj?["reply"] as? String ?? "Sorry — I couldn't generate a response."
            messages.append((role: "assistant", text: reply))
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func extractAlertStateId(from debugWhy: String) -> String? {
        // Format: "serverPattern ... alertStateId=<uuid> ..."
        let pattern = "alertStateId=([a-f0-9-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: debugWhy, options: [], range: NSRange(debugWhy.startIndex..., in: debugWhy)),
              let range = Range(match.range(at: 1), in: debugWhy)
        else { return nil }
        return String(debugWhy[range])
    }
}

// MARK: - Loading Step Row Helper View
struct LoadingStepRow: View {
    let step: Int
    let currentStep: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(textColor)
        }
    }
    
    private var iconName: String {
        if currentStep > step {
            return "checkmark.circle.fill"
        } else if currentStep == step {
            return "arrow.right.circle.fill"
        } else {
            return "circle"
        }
    }
    
    private var iconColor: Color {
        if currentStep > step {
            return .green
        } else if currentStep == step {
            return .blue
        } else {
            return .miyaTextSecondary.opacity(0.4)
        }
    }
    
    private var textColor: Color {
        if currentStep >= step {
            return .miyaTextPrimary
        } else {
            return .miyaTextSecondary.opacity(0.6)
        }
    }
}

// MARK: - Expandable Insight Section
struct ExpandableInsightSection<Content: View>: View {
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    let backgroundColor: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible, tappable)
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(icon)
                        .font(.system(size: 20))
                    
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(20)
                .background(backgroundColor)
                .cornerRadius(12, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
            }
            .buttonStyle(.plain)
            
            // Content (collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(20)
                .padding(.top, 0)
                .background(backgroundColor)
                .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// Helper for selective corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
