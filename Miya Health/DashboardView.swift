import SwiftUI
import UIKit
import Foundation
import Supabase
import RookSDK

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
    @State private var dataBackfillStatus: DataBackfillStatus? = nil
    
    struct DataBackfillStatus {
        let affectedMemberCount: Int
        let oldestSourceDays: Int
        let pillarsAffected: [String] // ["Activity", "Sleep"]
    }
    
    // Family badges (Daily computed; Weekly persisted)
    @State private var dailyBadgeWinners: [BadgeEngine.Winner] = []
    @State private var weeklyBadgeWinners: [BadgeEngine.Winner] = []
    @State private var weeklyBadgeWeekStart: String? = nil
    @State private var weeklyBadgeWeekEnd: String? = nil
    @State private var selectedBadge: BadgeEngine.Winner? = nil

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
                        // Data backfill notification banner
                        if let status = dataBackfillStatus {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                                Text("Some data estimated from \(status.oldestSourceDays)d ago (\(status.affectedMemberCount) member\(status.affectedMemberCount == 1 ? "" : "s"))")
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Dismiss") {
                                    withAnimation {
                                        dataBackfillStatus = nil
                                    }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.yellow.opacity(0.15))
                            .cornerRadius(8)
                            .padding(.horizontal, DashboardDesign.cardPadding)
                            .padding(.top, 8)
                        }
                        
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
                            weekEnd: weeklyBadgeWeekEnd,
                            onBadgeTapped: { selectedBadge = $0 }
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
                    await refreshFamilyVitalitySnapshotsIfPossible()
                    await loadFamilyMembers()
                    // Run loadServerPatternAlerts early (while we have fresh familyMembers/familyMemberRecords)
                    // so server alerts are less likely to be skipped if the refresh is cancelled later.
                    await loadServerPatternAlerts()
                    // ALWAYS load vitality on pull-to-refresh (to show current score)
                    await loadFamilyVitality()
                    // Weekly refresh logic: only refresh from server on Sundays
                    if WeeklyVitalityScheduler.shared.shouldRefreshFamilyVitality() {
                        await refreshFamilyVitalitySnapshotsIfPossible()
                        await loadFamilyVitality() // Reload after server refresh
                        WeeklyVitalityScheduler.shared.markRefreshed()
                    } else if WeeklyVitalityScheduler.shared.needsInitialRefresh() {
                        // First-time user or >7 days since last refresh - allow refresh
                        await refreshFamilyVitalitySnapshotsIfPossible()
                        await loadFamilyVitality() // Reload after server refresh
                        WeeklyVitalityScheduler.shared.markRefreshed()
                    }
                    familyMembersRefreshID = UUID()
                    await computeAndStoreFamilySnapshot()
                    await computeTrendInsights()
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
            VitalityFactorDetailSheet(factor: factor, dataManager: dataManager)
        }
        .sheet(item: $selectedBadge) { winner in
            BadgeDetailSheet(winner: winner)
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
                },
                dataManager: dataManager
            )
        }
        .onChange(of: selectedFamilyNotification?.id) { _, newId in
            // When the notification detail sheet is dismissed, refetch server pattern alerts
            // so we can show the correct server-style list (with AI) if it was empty before.
            if newId == nil {
                Task { await loadServerPatternAlerts() }
            }
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugUpload) {
            NavigationStack {
                DebugUploadPickerView(members: familyMembers, onboardingManager: onboardingManager, dataManager: dataManager)
            }
        }
        .onChange(of: isShowingDebugUpload) { _, isPresented in
            // After a debug upload finishes and the sheet is dismissed, refresh dashboard data
            // so new daily vitality rows + notifications appear immediately.
            guard !isPresented else { return }
            Task {
                #if DEBUG
                print("DEBUG_UPLOAD: sheet dismissed → refreshing family + trends")
                #endif
                await refreshFamilyVitalitySnapshotsIfPossible()
                await loadFamilyMembers()
                await loadServerPatternAlerts()
                await loadFamilyVitality()
                familyMembersRefreshID = UUID()
                await computeAndStoreFamilySnapshot()
                await computeTrendInsights()
                await computeFamilyBadgesIfNeeded()
            }
        }
        .sheet(isPresented: $isShowingDebugAddRecord) {
            NavigationStack {
                DebugAddRecordView(members: familyMembers, dataManager: dataManager)
            }
        }
        #endif
        .onChange(of: isShowingDebugAddRecord) { _, isPresented in
            guard !isPresented else { return }
            Task {
                #if DEBUG
                print("DEBUG_ADD_RECORD: sheet dismissed → refreshing family + trends")
                #endif
                await refreshFamilyVitalitySnapshotsIfPossible()
                await loadFamilyMembers()
                await loadServerPatternAlerts()
                await loadFamilyVitality()
                familyMembersRefreshID = UUID()
                await computeAndStoreFamilySnapshot()
                await computeTrendInsights()
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
            await refreshFamilyVitalitySnapshotsIfPossible()
            await loadFamilyMembers()
            await loadServerPatternAlerts()
            // ALWAYS load vitality on app launch (to show cached score)
            await loadFamilyVitality()
            // Weekly refresh logic: only refresh from server on Sundays
            if WeeklyVitalityScheduler.shared.shouldRefreshFamilyVitality() {
                await refreshFamilyVitalitySnapshotsIfPossible()
                await loadFamilyVitality() // Reload after server refresh
                WeeklyVitalityScheduler.shared.markRefreshed()
            } else if WeeklyVitalityScheduler.shared.needsInitialRefresh() {
                // First-time user or >7 days since last refresh - allow refresh
                await refreshFamilyVitalitySnapshotsIfPossible()
                await loadFamilyVitality() // Reload after server refresh
                WeeklyVitalityScheduler.shared.markRefreshed()
            }
            await computeAndStoreFamilySnapshot()
            await computeTrendInsights()
            await computeFamilyBadgesIfNeeded()
            print("DashboardView .task finished, familyVitalityScore=\(String(describing: familyVitalityScore))")
        }
    } // 👈 END OF `var body: some View`
    // MARK: - Share text builder

    private func prepareShareText() {
        let sleep = vitalityFactors.first(where: { $0.name == "Sleep" })?.percent
        let activity = vitalityFactors.first(where: { $0.name == "Activity" })?.percent
        let stress = vitalityFactors.first(where: { $0.name == "Recovery" })?.percent

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
            var latestMovementByUserId: [String: Int] = [:]
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

                // Fallback: if user_profiles doesn't have movement pillar scores, try latest vitality_scores.
                // This helps when recompute has produced daily scores but the snapshot hasn't been updated yet.
                struct LatestMovementRow: Decodable {
                    let user_id: String?
                    let vitality_movement_pillar_score: Int?
                    let score_date: String?
                }

                if !userIds.isEmpty {
                    for userId in userIds {
                        do {
                            let rows: [LatestMovementRow] = try await supabase
                                .from("vitality_scores")
                                .select("user_id, vitality_movement_pillar_score, score_date")
                                .eq("user_id", value: userId)
                                .order("score_date", ascending: false)
                                .limit(1)
                                .execute()
                                .value
                            if let row = rows.first,
                               let uid = row.user_id,
                               let movement = row.vitality_movement_pillar_score {
                                latestMovementByUserId[uid.lowercased()] = movement
                            }
                        } catch {
                            #if DEBUG
                            print("⚠️ Dashboard: Failed to load latest movement pillar score for user_id=\(userId): \(error.localizedDescription)")
                            #endif
                        }
                    }
                }
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

            func memberScoresForMovement() -> [FamilyMemberScore] {
                return records.map { rec in
                    let name = rec.firstName
                    let uid = rec.userId?.uuidString
                    let isMe = (uid != nil && uid == currentUserIdString)
                    let profile = uid.flatMap { profileByUserId[$0.lowercased()] }
                    let updatedAt = parseISODate(profile?.vitality_score_updated_at)
                    let isFresh = (updatedAt != nil && (updatedAt ?? .distantPast) >= freshCutoff)
                    let profileMovement = profile?.vitality_movement_pillar_score
                    let fallbackMovement = uid.flatMap { latestMovementByUserId[$0.lowercased()] }
                    let movement = (profileMovement != nil && (profileMovement ?? 0) > 0) ? profileMovement : (fallbackMovement ?? profileMovement)
                    let hasPillar = (uid != nil && (movement ?? -1) >= 0)
                    let isPillarFresh = (hasPillar && isFresh)
                    let isPillarStale = (hasPillar && !isFresh)
                    return FamilyMemberScore(
                        name: name,
                        initials: makeInitials(from: name),
                        userId: uid,
                        hasScore: hasPillar,
                        isScoreFresh: isPillarFresh,
                        isStale: isPillarStale,
                        currentScore: (hasPillar ? (movement ?? 0) : 0),
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
                let profileMovement = profile?.vitality_movement_pillar_score
                let fallbackMovement = latestMovementByUserId[uid.lowercased()]
                if let v = profileMovement, v > 0 { return v }
                return fallbackMovement ?? profileMovement
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
                        memberScores: memberScoresForMovement()
                    )
                )
            }
            if let stressAvg {
                factors.append(
                    VitalityFactor(
                        name: "Recovery",
                        iconName: "heart.fill",
                        percent: stressAvg,
                        description: "Your family's recovery reflects heart health signals like HRV and resting heart rate. Higher is better.",
                        actionPlan: ["Try a short breathing exercise", "Prioritize rest and recovery"],
                        memberScores: memberScoresForPillar { $0.vitality_stress_pillar_score }
                    )
                )
            }

            await MainActor.run {
                familyMembers = ordered
                vitalityFactors = factors
                loadFamilyName()
            }
            
            // Check for backfilled data after members are loaded
            await checkDataBackfillStatus()
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
    
    /// Check for backfilled data across family members and update banner status
    private func checkDataBackfillStatus() async {
        // Only check if we have members with user IDs
        let eligibleUserIds = familyMembers.compactMap { $0.userId }.filter { !$0.isEmpty }
        guard !eligibleUserIds.isEmpty else {
            await MainActor.run {
                dataBackfillStatus = nil
            }
            return
        }
        
        // Lightweight check: fetch last 7 days of data per member and check for gaps
        var totalBackfilledDays = 0
        var oldestSourceAge = 0
        var affectedPillars = Set<String>()
        var membersWithBackfill = 0
        
        for userId in eligibleUserIds {
            do {
                // Fetch last 7 days of wearable metrics
                let wearableRows = try await dataManager.fetchWearableDailyMetricsForUser(userId: userId, days: 7)
                
                // Convert to DailyDataPoint format for backfill check
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                let today = Date()
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
                
                // Build expected date range
                var expectedDates: [String] = []
                var currentDate = sevenDaysAgo
                while currentDate <= today {
                    expectedDates.append(dateFormatter.string(from: currentDate))
                    guard let next = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else { break }
                    currentDate = next
                }
                
                // Check for missing days
                let existingDates = Set(wearableRows.map { $0.metricDate })
                let missingDates = expectedDates.filter { !existingDates.contains($0) }
                
                if !missingDates.isEmpty {
                    // Check if we can backfill (look back up to 3 days)
                    for missingDate in missingDates {
                        guard let missing = dateFormatter.date(from: missingDate) else { continue }
                        
                        // Look back up to 3 days
                        for daysBack in 1...3 {
                            guard let lookbackDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: missing),
                                  let lookbackString = Optional(dateFormatter.string(from: lookbackDate)) else {
                                continue
                            }
                            
                            if existingDates.contains(lookbackString) {
                                // Found backfillable data
                                totalBackfilledDays += 1
                                oldestSourceAge = max(oldestSourceAge, daysBack)
                                membersWithBackfill += 1
                                
                                // Determine affected pillars based on available metrics
                                if let row = wearableRows.first(where: { $0.metricDate == lookbackString }) {
                                    if row.steps != nil || row.movementMinutes != nil {
                                        affectedPillars.insert("Activity")
                                    }
                                    if row.sleepMinutes != nil || row.deepSleepMinutes != nil {
                                        affectedPillars.insert("Sleep")
                                    }
                                    if row.hrvMs != nil || row.restingHr != nil {
                                        affectedPillars.insert("Recovery")
                                    }
                                }
                                break
                            }
                        }
                    }
                }
            } catch {
                // Silently skip errors for backfill check (non-critical)
                #if DEBUG
                print("⚠️ Dashboard: Backfill check failed for user \(userId): \(error.localizedDescription)")
                #endif
            }
        }
        
        // Update banner status if we found backfilled data
        await MainActor.run {
            if totalBackfilledDays > 0 {
                dataBackfillStatus = DataBackfillStatus(
                    affectedMemberCount: membersWithBackfill,
                    oldestSourceDays: oldestSourceAge,
                    pillarsAffected: Array(affectedPillars)
                )
            } else {
                dataBackfillStatus = nil
            }
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
    
    /// Load server pattern alerts from the database into state.
    /// Only updates serverPatternAlerts when the fetch succeeds; on failure we keep the previous
    /// value so we don't replace good server alerts with fallback due to transient errors or
    /// refresh cancellation.
    private func loadServerPatternAlerts() async {
        let result = await fetchServerPatternAlerts()
        if case .success(let alerts) = result {
        await MainActor.run {
            serverPatternAlerts = alerts
        }
        }
        // On .failure: do not overwrite serverPatternAlerts; keep last good value
    }

    /// Best-effort: refresh user_profiles vitality snapshot values from latest vitality_scores.
    /// This keeps pillar scores accurate when the latest daily scores exist but the snapshot
    /// has not yet been updated (e.g. movement showing 0 despite fresh data).
    private func refreshFamilyVitalitySnapshotsIfPossible() async {
        guard let familyId = dataManager.currentFamilyId else { return }
        do {
            let supabase = SupabaseConfig.client
            _ = try await supabase
                .rpc("refresh_family_vitality_snapshots", params: ["family_id": AnyJSON.string(familyId)])
                .execute()
        } catch {
            #if DEBUG
            print("⚠️ Dashboard: refresh_family_vitality_snapshots failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Fetch server pattern alerts from the database.
    /// Returns .success([...]) on success (possibly empty), .failure on error.
    /// Caller should only overwrite serverPatternAlerts on .success to avoid replacing
    /// good data with fallback when the RPC fails or the task is cancelled.
    private func fetchServerPatternAlerts() async -> Result<[FamilyNotificationItem], Error> {
        do {
            let supabase = SupabaseConfig.client
            
            // Require familyId to scope alerts
            guard let familyId = dataManager.currentFamilyId else {
                print("❌ Dashboard: No familyId available for get_family_pattern_alerts")
                return .success([])
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
                // Find member name (prefer computed members, fall back to raw records)
                let memberName: String = {
                    if let member = familyMembers.first(where: { $0.userId?.lowercased() == row.member_user_id.lowercased() }) {
                        return member.name
                    }
                    if let record = familyMemberRecords.first(where: { $0.userId?.uuidString.lowercased() == row.member_user_id.lowercased() }) {
                        return record.firstName
                    }
                    return "Family member"
                }()
                
                // Map metric to pillar
                let pillar: VitalityPillar
                switch row.metric_type.lowercased() {
                case "steps", "movement_minutes":
                    pillar = .movement
                case "sleep_minutes", "sleep_efficiency_pct", "deep_sleep_minutes":
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
                case "movement_minutes": metricDisplay = "Activity"
                case "sleep_minutes": metricDisplay = "Sleep"
                case "sleep_efficiency_pct": metricDisplay = "Sleep Quality"
                case "deep_sleep_minutes": metricDisplay = "Deep Sleep"
                case "hrv_ms": metricDisplay = "HRV"
                case "resting_hr": metricDisplay = "Resting HR"
                default: metricDisplay = row.metric_type
                }
                
                let patternDesc = row.pattern_type?.contains("rise") == true ? "above" : "below"
                let levelDesc = "\(row.current_level)d"
                
                let title = "\(metricDisplay) \(patternDesc) baseline"
                let deviationText = row.deviation_percent.map { String(format: "%.0f%%", abs($0 * 100)) } ?? ""
                let body = deviationText.isEmpty ? 
                    "\(metricDisplay) has been \(patternDesc) \(memberName)'s baseline for \(levelDesc)." :
                    "\(metricDisplay) is \(deviationText) \(patternDesc) \(memberName)'s baseline (last \(levelDesc))."
                
                // Create a TrendInsight to store the server pattern data with debugWhy
                let debugWhy = "serverPattern metric=\(row.metric_type) pattern=\(row.pattern_type ?? "unknown") level=\(row.current_level) severity=\(row.severity ?? "watch") deviation=\(row.deviation_percent ?? 0) alertStateId=\(row.id) activeSince=\(row.active_since ?? "unknown")"
                
                let insight = TrendInsight(
                    memberName: memberName,
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
                    memberInitials: makeInitials(from: memberName),
                    memberName: memberName
                )
                items.append(item)
            }
            
            print("🔔 Dashboard: Converted \(items.count) server pattern alerts to notification items")
            return .success(items)
            
        } catch {
            print("❌ Dashboard: Failed to fetch server pattern alerts: \(error.localizedDescription)")
            return .failure(error)
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
    
#Preview {
    NavigationStack {
        DashboardView(familyName: "The Kempton Family")
            .environmentObject(AuthManager())
            .environmentObject(DataManager())
            .environmentObject(OnboardingManager())
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
        @State private var isWearableSyncing: Bool = false
        @State private var wearableSyncErrorMessage: String?
        @State private var isWearableSyncErrorPresented: Bool = false
        @State private var showWearableSelectionSheet: Bool = false
        
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
            .alert("Wearable sync error", isPresented: $isWearableSyncErrorPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(wearableSyncErrorMessage ?? "Something went wrong while syncing your wearables.")
            }
            .sheet(isPresented: $showWearableSelectionSheet, onDismiss: {
                Task {
                    await recomputeWearableBaselineWithRetries()
                }
            }) {
                NavigationStack {
                    WearableSelectionView(isGuidedSetupInvite: false, isReconnectMode: true)
                        .environmentObject(authManager)
                        .environmentObject(dataManager)
                        .environmentObject(onboardingManager)
                }
            }
        }

        private func triggerWearableSync() {
            showWearableSelectionSheet = true
        }

        private func recomputeWearableBaselineWithRetries() async {
            guard !isWearableSyncing else { return }
            await MainActor.run {
                isWearableSyncing = true
                wearableSyncErrorMessage = nil
            }
            defer {
                Task { @MainActor in
                    isWearableSyncing = false
                }
            }

            var lastAttempt: DataManager.WearableBaselineAttempt?
            for attempt in 1...6 {
                do {
                    let attemptResult = try await dataManager.computeAndPersistWearableBaseline(days: 21)
                    lastAttempt = attemptResult
                    if attemptResult.snapshot != nil {
                        // Success! Refresh dashboard to show updated vitality
                        print("✅ Dashboard: Wearable baseline recomputed successfully, refreshing dashboard")
                        onReloadMembers()
                        return
                    }
                } catch {
                    await MainActor.run {
                        wearableSyncErrorMessage = "Wearable sync error: \(error.localizedDescription)"
                        isWearableSyncErrorPresented = true
                    }
                    return
                }

                if attempt < 6 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }

            if let info = lastAttempt {
                await MainActor.run {
                    wearableSyncErrorMessage =
                        "We’re still missing enough data to calculate your Vitality. Days: \(info.daysUsed)/7, sleep: \(info.sleepDays), steps: \(info.stepDays), heart signal: \(info.stressSignalDays)."
                    isWearableSyncErrorPresented = true
                }
            } else {
                await MainActor.run {
                    wearableSyncErrorMessage =
                        "We haven’t received enough wearable data yet to compute Vitality. Try again after your next device sync."
                    isWearableSyncErrorPresented = true
                }
            }
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
                    isSyncingWearables: isWearableSyncing,
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
                    onConnectWearables: {
                        triggerWearableSync()
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


// MARK: - PERSONAL VITALITY CARD


// MARK: - FAMILY VITALITY INSIGHTS CARD (Premium Redesign)

// MARK: - Family Notifications (lightweight, drill-in)
// NOTE: Notification components have been extracted to Dashboard/DashboardNotifications.swift

// MARK: - Insight Components
// NOTE: Insight components have been extracted to Dashboard/DashboardInsights.swift

// MARK: - Loading Step Row Helper View

