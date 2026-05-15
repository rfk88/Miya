import Foundation

/// First-person vs third-person copy for alerts, notifications, profile, and chat. Pure helpers — unit tested.
enum MemberProfileOwnVoice {

    /// `true` when the profile row said “me”, or when `memberUserId` matches the signed-in auth id (covers missing/wrong `isMe` on the family payload).
    static func isViewingOwnProfile(isCurrentUser: Bool, memberUserId: String, authUserId: String?) -> Bool {
        if isCurrentUser { return true }
        return isCurrentUser(memberUserId: memberUserId, authUserId: authUserId)
    }

    /// `true` when `memberUserId` matches the signed-in auth user.
    static func isCurrentUser(memberUserId: String?, authUserId: String?) -> Bool {
        guard let memberUserId, !memberUserId.isEmpty,
              let auth = authUserId?.lowercased(), !auth.isEmpty else { return false }
        return auth == memberUserId.lowercased()
    }

    /// Possessive for copy: `"your"` when self, else `"Josh's"` / `"James'"` for names ending in s.
    static func possessive(firstName: String, memberUserId: String?, authUserId: String?) -> String {
        if isCurrentUser(memberUserId: memberUserId, authUserId: authUserId) {
            return "your"
        }
        return possessiveThirdPerson(firstName: firstName)
    }

    /// Third-person possessive only (e.g. `"Josh's"`, `"James'"`).
    static func possessiveThirdPerson(firstName: String) -> String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "their" }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        if first.lowercased().hasSuffix("s") {
            return "\(first)'"
        }
        return "\(first)'s"
    }

    /// `"your baseline"` or `"Josh's baseline"`.
    static func baselinePhrase(firstName: String, memberUserId: String?, authUserId: String?) -> String {
        "\(possessive(firstName: firstName, memberUserId: memberUserId, authUserId: authUserId)) baseline"
    }

    /// Pattern-alert title: e.g. `"Resting HR below baseline"`.
    static func patternAlertTitle(metricDisplay: String, patternDesc: String) -> String {
        "\(metricDisplay) \(patternDesc) baseline"
    }

    /// Pattern-alert body for dashboard / notifications.
    static func patternAlertBody(
        metricDisplay: String,
        patternDesc: String,
        deviationText: String,
        levelDesc: String,
        firstName: String,
        memberUserId: String?,
        authUserId: String?
    ) -> String {
        let baseline = baselinePhrase(firstName: firstName, memberUserId: memberUserId, authUserId: authUserId)
        if deviationText.isEmpty {
            return "\(metricDisplay) has been \(patternDesc) \(baseline) for \(levelDesc)."
        }
        return "\(metricDisplay) is \(deviationText) \(patternDesc) \(baseline) (last \(levelDesc))."
    }

    /// Grouped notification summary: `"Your Sleep low"` vs `"Josh's Sleep low"`.
    static func metricBelowBaselineSummary(
        pillarLabels: [String],
        firstName: String,
        memberUserId: String?,
        authUserId: String?
    ) -> String {
        let poss = possessive(firstName: firstName, memberUserId: memberUserId, authUserId: authUserId)
        let joined: String
        if pillarLabels.isEmpty {
            joined = "Check in"
        } else if pillarLabels.count == 1 {
            joined = pillarLabels[0]
        } else if pillarLabels.count == 2 {
            joined = "\(pillarLabels[0]) & \(pillarLabels[1])"
        } else {
            joined = "Multiple pillars"
        }
        let prefix = poss == "your" ? "Your" : poss
        return "\(prefix) \(joined) low"
    }

    /// Subject reference: `"you"` or first name.
    static func subjectRef(firstName: String, memberUserId: String?, authUserId: String?) -> String {
        if isCurrentUser(memberUserId: memberUserId, authUserId: authUserId) {
            return "you"
        }
        return firstName.split(separator: " ").first.map(String.init) ?? firstName
    }

    /// Rewrites common third-person phrases using `memberName` for the signed-in member’s own profile/chat.
    static func rewriteMemberFacingCopy(memberName: String, text: String) -> String {
        let n = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: n)
        func apply(_ s: String, pattern: String, template: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return s }
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
        }
        var s = text
        s = apply(s, pattern: "How\\s+is\\s+\(escaped)['\u{2019}]s\\b", template: "How is my")
        s = apply(s, pattern: "What\\s+is\\s+\(escaped)\\b", template: "What am I")
        s = apply(s, pattern: "Where\\s+does\\s+\(escaped)\\b", template: "Where do I")
        s = apply(s, pattern: "\(escaped)['\u{2019}]s\\b", template: "your")
        return s
    }

    /// Pill title when the overview chat is for your own profile (fixed intents + rewrite fallback for server titles).
    static func suggestedPillTitleForOwnProfile(memberName: String, intent: String, serverTitle: String) -> String {
        switch intent {
        case "member_doing_well": return "What am I doing well?"
        case "member_needs_support": return "Where do I need support?"
        case "member_sleep": return "How is my sleep?"
        case "member_movement": return "How is my movement?"
        case "member_recovery": return "How is my recovery?"
        default:
            return rewriteMemberFacingCopy(memberName: memberName, text: serverTitle)
        }
    }
}
