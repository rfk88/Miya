import Foundation

enum AlertSupportStage {
    case earlyCheckIn
    case persistentConcern
    case longRunningConcern
    case challengeActive
    case noAction
}

enum AlertSupportAction {
    case sendMessage
    case startChallenge
}

struct AlertSupportPresentation {
    let stage: AlertSupportStage
    let title: String
    let explanation: String
    let statusLine: String?
    let primaryAction: AlertSupportAction?
    let primaryLabel: String?
    let secondaryAction: AlertSupportAction?
    let secondaryLabel: String?
    let challengeGoal: String
    let suggestedMessages: [(label: String, text: String)]
}

struct AlertSupportSelection: Identifiable {
    let item: FamilyNotificationItem
    let alert: ConsolidatedMemberAlert
    let presentation: AlertSupportPresentation

    var id: String { item.id }
}

enum DashboardAlertSupportPolicy {
    static func presentation(
        for item: FamilyNotificationItem,
        alert: ConsolidatedMemberAlert,
        isRelevant: Bool = true,
        authUserId: String? = nil
    ) -> AlertSupportPresentation {
        let duration = item.patternDurationDays ?? alert.maxDurationDays
        let firstName = alert.firstName
        let isSelf = MemberProfileOwnVoice.isCurrentUser(memberUserId: item.memberUserId, authUserId: authUserId)
        let goal = challengeGoal(for: item.pillar, isForSelf: isSelf)
        let suggestions = messageSuggestions(for: item, firstName: firstName, isForSelf: isSelf)

        guard isRelevant, item.isServerAlert else {
            return AlertSupportPresentation(
                stage: .noAction,
                title: "Support action unavailable",
                explanation: "This alert is no longer current enough for a support action.",
                statusLine: nil,
                primaryAction: nil,
                primaryLabel: nil,
                secondaryAction: nil,
                secondaryLabel: nil,
                challengeGoal: goal,
                suggestedMessages: suggestions
            )
        }

        if let outcome = item.outcomeMessage, !outcome.isEmpty {
            let status = isSelf
                ? MemberProfileOwnVoice.rewriteMemberFacingCopy(memberName: alert.memberName, text: outcome)
                : outcome
            return basePresentation(
                stage: .noAction,
                title: "Follow-up recorded",
                explanation: "Miya has already captured the latest update for this alert.",
                statusLine: status,
                goal: goal,
                suggestions: suggestions
            )
        }

        if item.careState == .resolved || item.careState == .archived || item.careState == .improving {
            let handledExplanation = isSelf
                ? "Your alert is already being handled."
                : "\(firstName)'s alert is already being handled."
            return basePresentation(
                stage: .noAction,
                title: "No action needed",
                explanation: handledExplanation,
                statusLine: item.careState == .improving ? "Miya is seeing signs of improvement." : nil,
                goal: goal,
                suggestions: suggestions
            )
        }

        if item.myChallengeStatus == "active" || item.myChallengeStatus == "pending_invite" {
            let explanation = isSelf
                ? "A support challenge is already in progress for you."
                : "A support challenge is already in progress for \(firstName)."
            let statusLine: String? = item.myChallengeStatus == "pending_invite"
                ? (isSelf ? "Challenge invite sent — waiting for you." : "Challenge invite sent - waiting for \(firstName).")
                : (isSelf ? "Challenge active — Miya is tracking your progress." : "Challenge active - Miya is tracking progress.")
            return basePresentation(
                stage: .challengeActive,
                title: "Support challenge active",
                explanation: explanation,
                statusLine: statusLine,
                goal: goal,
                suggestions: suggestions
            )
        }

        if item.lastInterventionType == "reach_out" {
            let explanation = isSelf
                ? "Your family has already checked in with you."
                : "You have already checked in with \(firstName)."
            return basePresentation(
                stage: .noAction,
                title: "Message sent",
                explanation: explanation,
                statusLine: followUpText(for: item) ?? "Waiting to hear back.",
                goal: goal,
                suggestions: suggestions
            )
        }

        if item.lastInterventionType == "challenge" {
            return basePresentation(
                stage: .challengeActive,
                title: "Support challenge sent",
                explanation: "A support challenge has already been sent for this alert.",
                statusLine: followUpText(for: item) ?? "Waiting to hear back.",
                goal: goal,
                suggestions: suggestions
            )
        }

        if duration <= 3 {
            return AlertSupportPresentation(
                stage: .earlyCheckIn,
                title: "Best next step: check in",
                explanation: "This is an early change. A quick message is usually the best first step.",
                statusLine: followUpText(for: item),
                primaryAction: .sendMessage,
                primaryLabel: "Send message",
                secondaryAction: nil,
                secondaryLabel: nil,
                challengeGoal: goal,
                suggestedMessages: suggestions
            )
        }

        if duration >= 14 {
            let explanation = isSelf
                ? "This has continued for two weeks. A small 7-day support challenge may help you reset."
                : "This has continued for two weeks. A small 7-day support challenge may help \(firstName) reset."
            return AlertSupportPresentation(
                stage: .longRunningConcern,
                title: "This has persisted",
                explanation: explanation,
                statusLine: followUpText(for: item),
                primaryAction: .startChallenge,
                primaryLabel: "Start support challenge",
                secondaryAction: .sendMessage,
                secondaryLabel: "Send message",
                challengeGoal: goal,
                suggestedMessages: suggestions
            )
        }

        return AlertSupportPresentation(
            stage: .persistentConcern,
            title: "Check in first",
            explanation: "This has continued for a week. Check in first, or start a small 7-day support challenge.",
            statusLine: followUpText(for: item),
            primaryAction: .sendMessage,
            primaryLabel: "Send message",
            secondaryAction: .startChallenge,
            secondaryLabel: "Start support challenge",
            challengeGoal: goal,
            suggestedMessages: suggestions
        )
    }

    static func challengeGoal(for pillar: VitalityPillar, isForSelf: Bool = false) -> String {
        switch pillar {
        case .sleep:
            return isForSelf
                ? "Protect your sleep window for 5 of the next 7 nights."
                : "Protect their sleep window for 5 of the next 7 nights."
        case .movement:
            return isForSelf
                ? "Hit your movement target or add a 10-minute walk for 5 of the next 7 days."
                : "Hit their movement target or add a 10-minute walk for 5 of the next 7 days."
        case .stress:
            return isForSelf
                ? "Keep the last hour lighter and avoid late intense activity for 5 of the next 7 days."
                : "Keep the last hour lighter and avoid late intense activity for 5 of the next 7 days."
        }
    }

    static func supportReason(
        for item: FamilyNotificationItem,
        firstName: String,
        authUserId: String? = nil
    ) -> String {
        let duration = item.patternDurationDays ?? item.triggerWindowDays ?? 7
        let pillarName = item.pillar.dashboardDisplayName.lowercased()
        if MemberProfileOwnVoice.isCurrentUser(memberUserId: item.memberUserId, authUserId: authUserId) {
            return "Your \(pillarName) has been below your usual pattern for \(duration) days."
        }
        return "\(firstName)'s \(pillarName) has been below their usual pattern for \(duration) days."
    }

    private static func basePresentation(
        stage: AlertSupportStage,
        title: String,
        explanation: String,
        statusLine: String?,
        goal: String,
        suggestions: [(label: String, text: String)]
    ) -> AlertSupportPresentation {
        AlertSupportPresentation(
            stage: stage,
            title: title,
            explanation: explanation,
            statusLine: statusLine,
            primaryAction: nil,
            primaryLabel: nil,
            secondaryAction: nil,
            secondaryLabel: nil,
            challengeGoal: goal,
            suggestedMessages: suggestions
        )
    }

    private static func followUpText(for item: FamilyNotificationItem) -> String? {
        if item.careState == .monitoring, let due = item.followUpDueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Follow-up due \(formatter.string(from: due))"
        }
        return nil
    }

    private static func messageSuggestions(
        for item: FamilyNotificationItem,
        firstName: String,
        isForSelf: Bool
    ) -> [(label: String, text: String)] {
        let name = isForSelf ? "you" : firstName
        switch item.pillar {
        case .sleep:
            return [
                ("Gentle check-in", "Hey \(name), I noticed sleep has looked a bit harder this week. How are you feeling?"),
                ("Offer support", "Hey \(name), want to try an easier wind-down tonight? I can help keep things calm in the last hour."),
                ("Light nudge", "Hey \(name), shall we protect your sleep window tonight and keep the evening a bit lighter?")
            ]
        case .movement:
            return [
                ("Gentle check-in", "Hey \(name), activity has looked a bit lower this week. How are you feeling?"),
                ("Offer support", "Hey \(name), fancy a short walk together today? Even 10 minutes could help."),
                ("Light nudge", "Hey \(name), want to pick one easy movement win today and do it together?")
            ]
        case .stress:
            return [
                ("Gentle check-in", "Hey \(name), recovery has looked a bit stretched this week. How are you feeling?"),
                ("Offer support", "Hey \(name), want to keep the last hour lighter tonight and have a quick reset?"),
                ("Light nudge", "Hey \(name), shall we avoid late intense stuff tonight and make the evening calmer?")
            ]
        }
    }
}
