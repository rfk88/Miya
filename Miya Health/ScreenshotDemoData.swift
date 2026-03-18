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

    // Fixed UUIDs for demo family (so notification items can reference them)
    static let familyIdUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111")!
    static let simonUserId = "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"
    static let sarahUserId = "AAAAAAAA-BBBB-CCCC-DDDD-333333333333"
    static let emmaUserId  = "AAAAAAAA-BBBB-CCCC-DDDD-444444444444"
    static let liamUserId = "AAAAAAAA-BBBB-CCCC-DDDD-555555555555"
    static let dadRecoveryAlertStateId = "AAAAAAAA-BBBB-CCCC-DDDD-666666666666"
    static let emmaMovementAlertStateId = "AAAAAAAA-BBBB-CCCC-DDDD-777777777777"

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
        ]
    }
}

#endif
