import SwiftUI
import Supabase

// MARK: - DashboardView Data Loading Extension
// Extracted from DashboardView.swift for better organization and compilation performance

extension DashboardView {
    // MARK: - Badges (Daily computed; Weekly persisted)
    
    internal func utcDayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    internal func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date) ?? date
    }
    
    internal func computeFamilyBadgesIfNeeded() async {
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
    internal func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.dropFirst().first?.prefix(1) ?? ""
        let combined = first + second
        return combined.isEmpty ? "?" : combined.uppercased()
    }
    
    internal func loadFamilyName() {
        if let fname = dataManager.familyName, !fname.isEmpty {
            resolvedFamilyName = fname
        } else {
            resolvedFamilyName = familyName
        }
    }
    
    /// Consolidated dashboard initialization logic (extracted from .task for compiler performance)
    internal func onDashboardAppear() async {
        print("DashboardView .task started")
        loadFamilyName()
        currentUserIdString = await dataManager.currentUserIdString
        if let uid = currentUserIdString {
            loadDismissedMissingWearable(for: uid)
            loadDismissedGuidedMembers(for: uid)
        }
        await dataManager.clearFamilyCachesIfAuthChanged()
        await detectMissingWearableData()

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
        // Check and update current user's vitality if needed
        await checkAndUpdateCurrentUserVitality()
        await computeAndStoreFamilySnapshot()
        await computeTrendInsights()
        await computeFamilyBadgesIfNeeded()
        print("DashboardView .task finished, familyVitalityScore=\(String(describing: familyVitalityScore))")
    }
    
    /// Pull-to-refresh handler (extracted for compiler performance)
    internal func onPullToRefresh() async {
        // Avoid overlapping refresh calls that can trigger cancellation
        if isLoadingFamilyMembers || isLoadingFamilyVitality {
            print("ℹ️ Dashboard: refresh skipped (already loading)")
            return
        }
        await refreshFamilyVitalitySnapshotsIfPossible()
        await loadFamilyMembers()
        await loadServerPatternAlerts()
        await loadFamilyVitality()
        if WeeklyVitalityScheduler.shared.shouldRefreshFamilyVitality() {
            await refreshFamilyVitalitySnapshotsIfPossible()
            await loadFamilyVitality()
            WeeklyVitalityScheduler.shared.markRefreshed()
        } else if WeeklyVitalityScheduler.shared.needsInitialRefresh() {
            await refreshFamilyVitalitySnapshotsIfPossible()
            await loadFamilyVitality()
            WeeklyVitalityScheduler.shared.markRefreshed()
        }
        familyMembersRefreshID = UUID()
        await computeAndStoreFamilySnapshot()
        await computeTrendInsights()
        await computeFamilyBadgesIfNeeded()
    }
    
    internal func membersDisplayString() -> String {
        let memberNames = familyMemberRecords.map { record in
            if record.userId?.uuidString == currentUserIdString {
                return "\(record.firstName) (you)"
            } else {
                return record.firstName
            }
        }
        return memberNames.joined(separator: ", ")
    }
    
    internal func vitalityLabel(for score: Int) -> String {
        switch score {
        case 80...100: return "Great week"
        case 60..<80: return "Good week"
        case 40..<60: return "Needs attention"
        default: return "Let's improve"
        }
    }
    
    internal func loadFamilyMembers() async {
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
                if let fallback = fallbackMovement { return fallback }
                return profileMovement
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

    internal func loadFamilyVitality() async {
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
    internal func checkDataBackfillStatus() async {
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

    internal func computeAndStoreFamilySnapshot() async {
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
    internal func loadServerPatternAlerts() async {
        let result = await fetchServerPatternAlerts()
        if case .success(let alerts) = result {
        await MainActor.run {
            serverPatternAlerts = alerts
        }
        }
        // On .failure: do not overwrite serverPatternAlerts; keep last good value
    }

    internal func snoozeNotification(_ notification: FamilyNotificationItem, days: Int?) async {
        guard UUID(uuidString: notification.id) != nil else {
            print("❌ Invalid alert ID: \(notification.id)")
            return
        }
        
        do {
            let supabase = SupabaseConfig.client
            
            struct SimpleResult: Decodable {
                let success: Bool
            }
            
            if let days = days {
                let result: SimpleResult = try await supabase
                    .rpc("snooze_pattern_alert", params: [
                        "alert_id": AnyJSON.string(notification.id),
                        "snooze_for_days": AnyJSON.integer(days)
                    ])
                    .execute()
                    .value
                
                if result.success {
                    print("✅ Snoozed notification for \(days) days")
                } else {
                    print("❌ Failed to snooze notification")
                }
            } else {
                let result: SimpleResult = try await supabase
                    .rpc("dismiss_pattern_alert", params: [
                        "alert_id": AnyJSON.string(notification.id)
                    ])
                    .execute()
                    .value
                
                if result.success {
                    print("✅ Dismissed notification permanently")
                } else {
                    print("❌ Failed to dismiss notification")
                }
            }
            
            await loadServerPatternAlerts()
        } catch {
            print("❌ Failed to snooze/dismiss notification: \(error.localizedDescription)")
        }
    }

    /// Best-effort: refresh user_profiles vitality snapshot values from latest vitality_scores.
    /// This keeps pillar scores accurate when the latest daily scores exist but the snapshot
    /// has not yet been updated (e.g. movement showing 0 despite fresh data).
    internal func refreshFamilyVitalitySnapshotsIfPossible() async {
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
    
    /// Helper to parse ISO date string
    internal func parseISODateForVitality(_ dateStr: String?) -> Date? {
        guard let str = dateStr else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
    
    /// Checks if current user's vitality needs updating and computes if necessary
    internal func checkAndUpdateCurrentUserVitality() async {
        // Prevent concurrent executions
        guard !isCheckingVitality else {
            print("⚠️ Dashboard: Vitality check already in progress, skipping")
            return
        }
        
        guard let userId = currentUserIdString else { return }
        
        await MainActor.run {
            isCheckingVitality = true
        }
        
        defer {
            Task { @MainActor in
                isCheckingVitality = false
                lastVitalityCheck = Date()
            }
        }
        
        do {
            // Get current user's profile to check vitality status
            let profile = try await dataManager.loadUserProfile()
            
            // Check if vitality exists and how old it is
            let hasVitality = profile?.vitality_score_current != nil
            let lastUpdate = profile?.vitality_score_updated_at
            
            let needsUpdate: Bool = {
                // If no vitality at all, definitely need to compute
                if !hasVitality { return true }
                
                // If vitality is older than 7 days, refresh
                guard let updateStr = lastUpdate,
                      let updated = parseISODateForVitality(updateStr) else {
                    return true
                }
                
                let freshCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return updated < freshCutoff
            }()
            
            if needsUpdate {
                print("🔄 Dashboard: Vitality needs update, attempting to compute...")
                
                // Show syncing state
                await MainActor.run {
                    isWearableSyncing = true
                    wearableSyncStatus = "Checking for new data..."
                }
                
                // Attempt to compute (with retries for webhook delivery)
                let result = try await computeVitalityWithRetries(maxAttempts: 4)
                
                await MainActor.run {
                    isWearableSyncing = false
                    wearableSyncStatus = result.success ? nil : result.message
                    
                    if result.success {
                        print("✅ Dashboard: Vitality updated successfully")
                        // Reload family members to show updated score
                        Task { await loadFamilyMembers() }
                    } else {
                        print("⚠️ Dashboard: Vitality update incomplete - \(result.message)")
                    }
                }
            } else {
                print("✅ Dashboard: Vitality is fresh, no update needed")
            }
        } catch {
            print("❌ Dashboard: Error checking vitality status: \(error.localizedDescription)")
            await MainActor.run {
                isWearableSyncing = false
                wearableSyncStatus = nil
            }
        }
    }
    
    /// Attempts to compute vitality with retries and exponential backoff
    internal func computeVitalityWithRetries(maxAttempts: Int) async throws -> (success: Bool, message: String) {
        for attempt in 1...maxAttempts {
            let result = try await dataManager.computeAndPersistWearableBaseline(days: 21)
            
            if result.snapshot != nil {
                // Success!
                return (true, "Vitality updated")
            }
            
            // Update pillar tracking
            await MainActor.run {
                sleepDays = result.sleepDays
                stepDays = result.stepDays
                stressSignalDays = result.stressSignalDays
                isDataInsufficient = result.snapshot == nil && result.rowsCount > 0
            }
            
            // Not enough data yet - check what we have
            let message: String
            if result.rowsCount == 0 {
                message = "Waiting for wearable data to sync... (\(attempt)/\(maxAttempts))"
            } else {
                message = "Building baseline - \(result.sleepDays) sleep, \(result.stepDays) movement, \(result.stressSignalDays) recovery days (\(attempt)/\(maxAttempts))"
            }
            
            await MainActor.run {
                wearableSyncStatus = message
            }
            
            // Wait before next attempt (capped exponential backoff: 5s, 10s, 10s, 10s)
            if attempt < maxAttempts {
                let delay = UInt64(min(attempt * 5, 10) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        
        // All attempts exhausted
        let finalResult = try await dataManager.computeAndPersistWearableBaseline(days: 21)
        
        if finalResult.rowsCount == 0 {
            return (false, "No wearable data yet - wear your device and check back soon")
        } else {
            return (false, "Need more data - \(finalResult.sleepDays) sleep days, \(finalResult.stepDays) movement days. Wear your device for a few more days.")
        }
    }
    
    /// Helper to determine if vitality check should run
    internal func shouldCheckVitality() -> Bool {
        // Don't check if already syncing
        if isWearableSyncing || isCheckingVitality { return false }
        
        // Don't check if we checked in the last 5 minutes
        if let lastCheck = lastVitalityCheck {
            let fiveMinutesAgo = Calendar.current.date(byAdding: .minute, value: -5, to: Date()) ?? Date()
            if lastCheck > fiveMinutesAgo { return false }
        }
        
        return true
    }
    
    /// Fetch server pattern alerts from the database.
    /// Returns .success([...]) on success (possibly empty), .failure on error.
    /// Caller should only overwrite serverPatternAlerts on .success to avoid replacing
    /// good data with fallback when the RPC fails or the task is cancelled.
    internal func fetchServerPatternAlerts() async -> Result<[FamilyNotificationItem], Error> {
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
    internal func computeTrendInsights() async {
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

}