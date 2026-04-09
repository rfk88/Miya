//
//  ScreenshotDemoData.swift
//  Miya Health
//
//  DEBUG-only mock data for App Store screenshots: family of 4, two drifting
//  notifications (dad recovery, Emma movement), and chat content tied to them.
//

import Foundation

#if DEBUG

enum ScreenshotDemoData {

    static let userDefaultsKey = "MiyaUseScreenshotDemoData"

    /// Fixed credentials for "Try demo" – one-tap login that shows a full dashboard (no real data needed).
    static let demoEmail = "demo@miya.health"
    static let demoPassword = "DemoPass123!"

    static var isScreenshotModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    static func enableDemoMode() {
        isScreenshotModeEnabled = true
    }

    static func disableDemoMode() {
        isScreenshotModeEnabled = false
    }

    /// Keeps demo mode exclusive to the fixed demo account.
    /// - Note: This does NOT auto-enable demo mode. It only clears it for non-demo users.
    static func syncForAuthenticatedUser(email: String?) {
        let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized != demoEmail.lowercased() {
            disableDemoMode()
        }
    }

    // Fixed UUIDs for demo family (so notification items can reference them)
    static let familyIdUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111")!
    static let simonUserId = "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"
    static let sarahUserId = "AAAAAAAA-BBBB-CCCC-DDDD-333333333333"
    static let emmaUserId  = "AAAAAAAA-BBBB-CCCC-DDDD-444444444444"
    static let liamUserId = "AAAAAAAA-BBBB-CCCC-DDDD-555555555555"
    static let dadRecoveryAlertStateId = "AAAAAAAA-BBBB-CCCC-DDDD-666666666666"
    static let emmaMovementAlertStateId = "AAAAAAAA-BBBB-CCCC-DDDD-777777777777"

    static func isDemoMemberUserId(_ uid: String) -> Bool {
        let lower = uid.lowercased()
        return lower == simonUserId.lowercased()
            || lower == sarahUserId.lowercased()
            || lower == emmaUserId.lowercased()
            || lower == liamUserId.lowercased()
    }

    private static let now = Date()
    private static let freshDate = now.addingTimeInterval(-24 * 3600) // yesterday

    // MARK: - Family members (Simon = "Me")

    /// Asset catalog name for a demo member's avatar (e.g. "DemoAvatarSimon").
    static func demoAvatarAssetName(for memberName: String) -> String {
        "DemoAvatar\(memberName)"
    }

    static func makeFamilyMembers(currentUserId: String?) -> [FamilyMemberScore] {
        let isSimonMe = (currentUserId?.lowercased() == simonUserId.lowercased())
        return [
            member(name: "Simon", initials: "Si", userId: simonUserId, currentScore: 72, optimalScore: 85, isMe: isSimonMe),
            member(name: "Sarah", initials: "S", userId: sarahUserId, currentScore: 78, optimalScore: 85, isMe: false),
            member(name: "Emma", initials: "E", userId: emmaUserId, currentScore: 65, optimalScore: 80, isMe: false),
            member(name: "Liam", initials: "L", userId: liamUserId, currentScore: 70, optimalScore: 80, isMe: false),
        ]
    }

    private static func member(name: String, initials: String, userId: String, currentScore: Int, optimalScore: Int, isMe: Bool) -> FamilyMemberScore {
        FamilyMemberScore(
            name: name,
            initials: initials,
            userId: userId,
            hasScore: true,
            isScoreFresh: true,
            isStale: false,
            currentScore: currentScore,
            optimalScore: optimalScore,
            progressScore: min(100, Int((Double(currentScore) / Double(optimalScore)) * 100)),
            inviteStatus: "accepted",
            onboardingType: "Self Setup",
            guidedSetupStatus: nil,
            isMe: isMe,
            vitalityScoreUpdatedAt: freshDate
        )
    }

    // MARK: - Family member records (minimal for any lookups)

    static func makeFamilyMemberRecords() -> [FamilyMemberRecord] {
        func decodeRecord(id: String, userId: String, firstName: String) -> FamilyMemberRecord {
            let dict: [String: Any] = [
                "id": id,
                "user_id": userId,
                "family_id": familyIdUUID.uuidString,
                "role": "member",
                "relationship": NSNull(),
                "first_name": firstName,
                "invite_code": NSNull(),
                "invite_status": "accepted",
                "onboarding_type": "Self Setup",
                "guided_data_complete": NSNull(),
                "guided_setup_status": NSNull(),
                "guided_data_filled_at": NSNull(),
                "guided_data_reviewed_at": NSNull(),
            ]
            let data = try! JSONSerialization.data(withJSONObject: dict)
            return try! JSONDecoder().decode(FamilyMemberRecord.self, from: data)
        }
        return [
            decodeRecord(id: "AAAAAAAA-BBBB-CCCC-DDDD-201201201201", userId: simonUserId, firstName: "Simon"),
            decodeRecord(id: "AAAAAAAA-BBBB-CCCC-DDDD-202202202202", userId: sarahUserId, firstName: "Sarah"),
            decodeRecord(id: "AAAAAAAA-BBBB-CCCC-DDDD-203203203203", userId: emmaUserId, firstName: "Emma"),
            decodeRecord(id: "AAAAAAAA-BBBB-CCCC-DDDD-204204204204", userId: liamUserId, firstName: "Liam"),
        ]
    }

    // MARK: - Server pattern alerts (notification cards + chat-enabled)

    static func makeServerPatternAlerts() -> [FamilyNotificationItem] {
        let dadInsight = TrendInsight(
            memberName: "Simon",
            memberUserId: simonUserId,
            pillar: .stress,
            severity: .watch,
            title: "Recovery below baseline",
            body: "Recovery has been down compared to Simon's baseline for 14 days.",
            debugWhy: "serverPattern metric=hrv_ms pattern=drop_vs_baseline level=14 severity=watch deviation=-15 alertStateId=\(dadRecoveryAlertStateId) activeSince=unknown",
            windowDays: 21,
            requiredDays: 7,
            missingDays: 0,
            confidence: 1.0
        )
        let emmaInsight = TrendInsight(
            memberName: "Emma",
            memberUserId: emmaUserId,
            pillar: .movement,
            severity: .watch,
            title: "Movement below baseline",
            body: "Movement has been down compared to Emma's baseline for 14 days.",
            debugWhy: "serverPattern metric=steps pattern=drop_vs_baseline level=14 severity=watch deviation=-12 alertStateId=\(emmaMovementAlertStateId) activeSince=unknown",
            windowDays: 21,
            requiredDays: 7,
            missingDays: 0,
            confidence: 1.0
        )
        return [
            FamilyNotificationItem(
                id: dadRecoveryAlertStateId,
                kind: .trend(dadInsight),
                pillar: .stress,
                title: "Recovery drifting",
                body: "Recovery has been down compared to Simon's baseline for 14 days.",
                memberInitials: "Si",
                memberName: "Simon",
                careState: nil,
                actedByUserId: nil,
                actedAt: nil,
                followUpDueDate: nil,
                outcomeMessage: nil,
                cycleCount: 0,
                lastInterventionType: nil,
                myChallengeStatus: nil
            ),
            FamilyNotificationItem(
                id: emmaMovementAlertStateId,
                kind: .trend(emmaInsight),
                pillar: .movement,
                title: "Movement drifting",
                body: "Movement has been down compared to Emma's baseline for 14 days.",
                memberInitials: "E",
                memberName: "Emma",
                careState: nil,
                actedByUserId: nil,
                actedAt: nil,
                followUpDueDate: nil,
                outcomeMessage: nil,
                cycleCount: 0,
                lastInterventionType: nil,
                myChallengeStatus: nil
            ),
        ]
    }

    // MARK: - Bell notifications

    static func makeBellNotifications(currentUserId: String?) -> [BellNotification] {
        return [
            BellNotification(
                id: dadRecoveryAlertStateId,
                createdAt: now.addingTimeInterval(-3600),
                title: "Recovery drifting",
                subtitle: "For 14 days",
                kind: .patternAlert(pillar: .stress, durationDays: 14, severity: .watch, alertStateId: dadRecoveryAlertStateId),
                memberUserId: simonUserId
            ),
            BellNotification(
                id: emmaMovementAlertStateId,
                createdAt: now.addingTimeInterval(-7200),
                title: "Movement drifting",
                subtitle: "For 14 days",
                kind: .patternAlert(pillar: .movement, durationDays: 14, severity: .watch, alertStateId: emmaMovementAlertStateId),
                memberUserId: emmaUserId
            ),
        ]
    }

    // MARK: - Vitality factors (Sleep, Activity, Recovery) from same 4 members

    static func makeVitalityFactors(members: [FamilyMemberScore]) -> [VitalityFactor] {
        let sleepAvg = 71
        let movementAvg = 71
        let stressAvg = 71
        return [
            VitalityFactor(
                name: "Sleep",
                iconName: "bed.double.fill",
                percent: sleepAvg,
                description: "Your family's sleep pillar reflects duration, efficiency, and consistency.",
                actionPlan: ["Keep a consistent bedtime", "Aim for a wind-down routine"],
                memberScores: members
            ),
            VitalityFactor(
                name: "Activity",
                iconName: "figure.walk",
                percent: movementAvg,
                description: "Your family's activity pillar reflects daily movement and energy.",
                actionPlan: ["Take a short walk today", "Add movement breaks"],
                memberScores: members
            ),
            VitalityFactor(
                name: "Recovery",
                iconName: "heart.fill",
                percent: stressAvg,
                description: "Your family's recovery reflects heart health signals like HRV and resting heart rate. Higher is better.",
                actionPlan: ["Try a short breathing exercise", "Prioritize rest and recovery"],
                memberScores: members
            ),
        ]
    }

    // MARK: - Arlo chat (main) – canned reply

    static let arloCannedReply = "I'd suggest starting with a 7-day recovery challenge for Simon — that's often the quickest win when recovery's been down. For Emma, a short daily step goal can help movement get back on track. Want me to walk you through setting either of these up?"

    // MARK: - Notification detail chat – opening + canned replies per pillar

    static func notificationChatOpeningMessage(memberName: String, pillar: VitalityPillar) -> String {
        let metric = pillar.displayName.lowercased()
        return "\(memberName)'s \(metric) has been drifting for 14 days. I can suggest a simple 7-day challenge or some small steps to turn this around — what would help most?"
    }

    static func notificationChatCannedReply(pillar: VitalityPillar) -> String {
        switch pillar {
        case .stress:
            return "A 7-day recovery challenge for Simon could help — focus on consistent sleep and a short wind-down routine. I can set that up from here if you’d like."
        case .movement:
            return "For Emma, a 7-day movement challenge with a small daily step goal often works well. Want me to create that challenge?"
        default:
            return "I can suggest a 7-day challenge or some next steps. Tell me what you’d prefer."
        }
    }

    static func notificationChatDemoPrompts(pillar: VitalityPillar) -> [String] {
        switch pillar {
        case .stress:
            return ["Start a 7-day recovery challenge", "What small steps help most?", "How do I compare to baseline?"]
        case .movement:
            return ["Start a 7-day movement challenge", "What’s a good daily step goal?", "How do I compare to baseline?"]
        default:
            return ["Start a 7-day challenge", "What small steps help?", "Compare to baseline"]
        }
    }

    /// Pre-loaded 4-message thread for Simon's notification (demo): "support dad" conversation.
    static func simonNotificationPreloadedChat() -> [ChatMessage] {
        let user1 = "Hey Miya, how can I support dad and help him?"
        let miya1 = """
        I've been tracking your dad's movement over the last 14 days — he's averaging 3,200 steps/day, down from 5,800 the previous 2 weeks.

        His longest inactive blocks are 90–120 minutes in the afternoon, especially between 2–5pm.

        This drop usually links to lower energy + joint stiffness, which makes restarting harder.

        The goal isn't to push him — it's to make movement feel easy again.
        """
        let user2 = "Okay, what should I actually do?"
        let miya2 = """
        Start small and social — that's what works best for him.

        Here are 3 ways to help this week:

        1. Break his 2–5pm slump (priority window)
        That's where he's least active.
        Ask him for a 10-minute walk around 2:30–3pm — this is the highest impact change right now.

        2. Lower the barrier to starting
        On low-energy days, he's less likely to initiate.
        Instead of asking if he wants to go, try:
        "I'm heading out for 5 minutes, come with me."
        → removes decision fatigue.

        3. Pair movement with something he already does
        He's most consistent when it's tied to routine.
        Example: walk straight after lunch or a phone call — not a separate task.
        """
        return [
            ChatMessage(role: .user, text: user1),
            ChatMessage(role: .miya, text: miya1),
            ChatMessage(role: .user, text: user2),
            ChatMessage(role: .miya, text: miya2),
        ]
    }

    /// Opening message for the main "Chat with Miya" box in demo mode (family summary).
    static func chatWithMiyaDemoOpeningMessage(firstName: String) -> String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "there" : firstName
        return """
        Hey \(name) — here's how your family's doing today.

        Mum is consistent — sleep and daily routine are steady, which is keeping her energy stable.
        Dad has slowed slightly over the last 14 days, especially with afternoon movement — a small nudge will help him get back on track.
        Sarah is doing really well — strong consistency across movement and routine.
        Liam has been a bit irregular this week, but nothing concerning — just needs a light reset.

        Overall, your family's in a good place — just a small window to step in early and keep everything moving in the right direction.
        """
    }

    // MARK: - Vitality factor detail sheet (per-member rows)

    /// Rich mock rows for `VitalityFactorDetailSheet` when demo mode is on.
    static func makePillarMemberDetails(pillar: VitalityPillar, members: [FamilyMemberScore]) -> [PillarMemberDetail] {
        members.map { member in
            let (score, trend, pct, subs) = demoSubmetricsForPillarMember(pillar: pillar, member: member)
            return PillarMemberDetail(
                member: member,
                todayScore: score,
                trendDirection: trend,
                trendPercentChange: pct,
                subMetrics: subs,
                hasBackfilledData: false,
                oldestSourceAgeInDays: nil
            )
        }
    }

    private static func demoSubmetricsForPillarMember(
        pillar: VitalityPillar,
        member: FamilyMemberScore
    ) -> (Int?, TrendDirection, Double?, [SubMetric]) {
        let uid = member.userId?.lowercased() ?? ""
        switch pillar {
        case .sleep:
            switch uid {
            case simonUserId.lowercased():
                return (70, .stable, 2.0, [
                    SubMetric(name: "Sleep Duration", value: "6.8 hours", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Deep Sleep", value: "82 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "REM Sleep", value: "98 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Efficiency", value: "87%", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case sarahUserId.lowercased():
                return (82, .up, 4.0, [
                    SubMetric(name: "Sleep Duration", value: "7.5 hours", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Deep Sleep", value: "95 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "REM Sleep", value: "110 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Efficiency", value: "91%", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case emmaUserId.lowercased():
                return (62, .down, 3.0, [
                    SubMetric(name: "Sleep Duration", value: "6.2 hours", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Deep Sleep", value: "68 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "REM Sleep", value: "85 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Efficiency", value: "79%", isBackfilled: false, sourceAgeInDays: nil),
                ])
            default: // Liam
                return (74, .stable, 1.5, [
                    SubMetric(name: "Sleep Duration", value: "7.0 hours", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Deep Sleep", value: "78 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "REM Sleep", value: "98 min", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Efficiency", value: "87%", isBackfilled: false, sourceAgeInDays: nil),
                ])
            }
        case .movement:
            switch uid {
            case simonUserId.lowercased():
                return (71, .stable, 2.0, [
                    SubMetric(name: "Steps", value: "8,200 steps", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Active Minutes", value: "48 min", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case sarahUserId.lowercased():
                return (79, .up, 3.0, [
                    SubMetric(name: "Steps", value: "9,100 steps", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Active Minutes", value: "62 min", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case emmaUserId.lowercased():
                return (58, .down, 6.0, [
                    SubMetric(name: "Steps", value: "5,800 steps", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Active Minutes", value: "32 min", isBackfilled: false, sourceAgeInDays: nil),
                ])
            default:
                return (72, .stable, 1.0, [
                    SubMetric(name: "Steps", value: "7,400 steps", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Active Minutes", value: "44 min", isBackfilled: false, sourceAgeInDays: nil),
                ])
            }
        case .stress:
            switch uid {
            case simonUserId.lowercased():
                return (68, .down, 4.0, [
                    SubMetric(name: "HRV", value: "58 ms", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Resting HR", value: "62 bpm", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case sarahUserId.lowercased():
                return (78, .stable, 2.0, [
                    SubMetric(name: "HRV", value: "65 ms", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Resting HR", value: "58 bpm", isBackfilled: false, sourceAgeInDays: nil),
                ])
            case emmaUserId.lowercased():
                return (65, .stable, 1.0, [
                    SubMetric(name: "HRV", value: "52 ms", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Resting HR", value: "64 bpm", isBackfilled: false, sourceAgeInDays: nil),
                ])
            default:
                return (71, .stable, 2.0, [
                    SubMetric(name: "HRV", value: "60 ms", isBackfilled: false, sourceAgeInDays: nil),
                    SubMetric(name: "Resting HR", value: "60 bpm", isBackfilled: false, sourceAgeInDays: nil),
                ])
            }
        }
    }

    // MARK: - Member pillar history (90d) for PillarDiveDeeperSheet charts

    /// Demo-only: ascending dates, `days` rows, values 0–100 for charts.
    static func makeDemoPillarHistory(userId: String, pillar: VitalityPillar, days: Int) -> [(date: String, value: Int?)] {
        let calendar = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let base = demoBasePillarScore(userId: userId, pillar: pillar)
        var rows: [(String, Int?)] = []
        rows.reserveCapacity(days)
        for i in 0..<days {
            let dayOffset = i - (days - 1)
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) else { continue }
            let dayStr = df.string(from: date)
            let wave = 5.0 * sin(Double(i) * 0.15)
            let bump = (i % 9) - 4
            let v = max(42, min(96, base + Int(wave) + bump))
            rows.append((dayStr, v))
        }
        return rows
    }

    private static func demoBasePillarScore(userId: String, pillar: VitalityPillar) -> Int {
        let u = userId.lowercased()
        let member: Int
        switch u {
        case simonUserId.lowercased(): member = 0
        case sarahUserId.lowercased(): member = 1
        case emmaUserId.lowercased(): member = 2
        case liamUserId.lowercased(): member = 3
        default: member = 0
        }
        let bases: [[Int]] = [
            [70, 71, 68], // Simon sleep, movement, stress
            [82, 79, 78], // Sarah
            [62, 58, 65], // Emma
            [74, 72, 71], // Liam
        ]
        let pi: Int
        switch pillar {
        case .sleep: pi = 0
        case .movement: pi = 1
        case .stress: pi = 2
        }
        return bases[member][pi]
    }

    // MARK: - Member overview chat (demo)

    /// Returns canned assistant text for `ArloMemberChatAPI.sendMemberOverview` in demo mode.
    static func memberOverviewDemoReplyText(memberName: String, intent: String?) -> String {
        switch intent {
        case "member_doing_well":
            return "\(memberName) has been steady — consistency in routine and sleep is the backbone. Movement and recovery are both in a healthy band for the last few weeks. If you want to go further, we can pick one small upgrade next."
        case "member_needs_support":
            return "The clearest window is gentle movement: short walks tied to something \(memberName) already does work best. If recovery dips, prioritize sleep timing first — it’s usually the fastest lever."
        case "member_sleep":
            return "\(memberName)'s sleep duration and efficiency look good. If anything, keep wake time consistent — that’s what usually moves the needle for energy the next day."
        case "member_movement":
            return "Steps and active minutes are in a solid range. If you want a nudge, try a 5–10 minute walk after lunch — it’s often the easiest habit to add without feeling like a ‘workout.’"
        case "member_recovery":
            return "HRV and resting heart rate are in a reasonable range. If stress spikes, focus on wind-down before bed — the watch picks up recovery best when sleep is regular."
        default:
            return "Here’s a quick read: \(memberName)’s scores are in a healthy range with a few small ups and downs — that’s normal. Tell me if you want to zoom in on sleep, movement, or recovery."
        }
    }

    static func memberOverviewDemoSuggestedPrompts(memberName: String) -> [(id: String, title: String, intent: String)] {
        [
            ("well", "What is \(memberName) doing well?", "member_doing_well"),
            ("support", "Where does \(memberName) need support?", "member_needs_support"),
            ("sleep", "How is \(memberName)’s sleep?", "member_sleep"),
            ("move", "How is \(memberName)’s movement?", "member_movement"),
        ]
    }

    // MARK: - Demo family challenges (for Family Challenges tab)

    static func makeDemoFamilyChallenges() -> [FamilyChallenge] {
        let iso = ISO8601DateFormatter()
        return [
            FamilyChallenge(
                id: "AAAAAAAA-BBBB-CCCC-DDDD-301301301301",
                pillar: "stress",
                status: "active",
                memberUserId: simonUserId,
                memberName: "Simon",
                daysSucceeded: 4,
                daysEvaluated: 5,
                endDate: iso.string(from: now.addingTimeInterval(2 * 24 * 3600)),
                sourceAlertMetric: "Recovery",
                sourceAlertDays: 14,
                myRole: "challenger",
                challengerCount: 2
            ),
            FamilyChallenge(
                id: "AAAAAAAA-BBBB-CCCC-DDDD-302302302302",
                pillar: "movement",
                status: "active",
                memberUserId: emmaUserId,
                memberName: "Emma",
                daysSucceeded: 3,
                daysEvaluated: 4,
                endDate: iso.string(from: now.addingTimeInterval(3 * 24 * 3600)),
                sourceAlertMetric: "Movement",
                sourceAlertDays: 14,
                myRole: "challengee",
                challengerCount: 1
            ),
            FamilyChallenge(
                id: "AAAAAAAA-BBBB-CCCC-DDDD-303303303303",
                pillar: "sleep",
                status: "completed_success",
                memberUserId: sarahUserId,
                memberName: "Sarah",
                daysSucceeded: 7,
                daysEvaluated: 7,
                endDate: iso.string(from: now.addingTimeInterval(-4 * 24 * 3600)),
                sourceAlertMetric: "Sleep",
                sourceAlertDays: 14,
                myRole: "challenger",
                challengerCount: 2
            ),
            FamilyChallenge(
                id: "AAAAAAAA-BBBB-CCCC-DDDD-304304304304",
                pillar: "stress",
                status: "completed_failed",
                memberUserId: liamUserId,
                memberName: "Liam",
                daysSucceeded: 4,
                daysEvaluated: 7,
                endDate: iso.string(from: now.addingTimeInterval(-10 * 24 * 3600)),
                sourceAlertMetric: "Recovery",
                sourceAlertDays: 21,
                myRole: "challenger",
                challengerCount: 1
            ),
        ]
    }
}

#endif
