import Foundation

/// First-person vs third-person copy for the family member profile and overview chat. Pure helpers — unit tested.
enum MemberProfileOwnVoice {

    /// `true` when the profile row said “me”, or when `memberUserId` matches the signed-in auth id (covers missing/wrong `isMe` on the family payload).
    static func isViewingOwnProfile(isCurrentUser: Bool, memberUserId: String, authUserId: String?) -> Bool {
        if isCurrentUser { return true }
        guard let auth = authUserId?.lowercased(), !auth.isEmpty, !memberUserId.isEmpty else { return false }
        return auth == memberUserId.lowercased()
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
