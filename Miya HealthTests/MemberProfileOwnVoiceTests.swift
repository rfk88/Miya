import XCTest
@testable import Miya_Health

final class MemberProfileOwnVoiceTests: XCTestCase {

    // MARK: - isViewingOwnProfile

    func test_isViewingOwnProfile_trueWhenFamilyStripSaysCurrentUser() {
        XCTAssertTrue(
            MemberProfileOwnVoice.isViewingOwnProfile(
                isCurrentUser: true,
                memberUserId: "any-id",
                authUserId: "00000000-0000-0000-0000-000000000099"
            )
        )
    }

    func test_isViewingOwnProfile_trueWhenMemberIdMatchesAuthCaseInsensitive() {
        let auth = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        XCTAssertTrue(
            MemberProfileOwnVoice.isViewingOwnProfile(
                isCurrentUser: false,
                memberUserId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                authUserId: auth
            )
        )
    }

    func test_isViewingOwnProfile_falseWhenDifferentMember() {
        XCTAssertFalse(
            MemberProfileOwnVoice.isViewingOwnProfile(
                isCurrentUser: false,
                memberUserId: "11111111-1111-1111-1111-111111111111",
                authUserId: "22222222-2222-2222-2222-222222222222"
            )
        )
    }

    func test_isViewingOwnProfile_falseWhenAuthMissing() {
        XCTAssertFalse(
            MemberProfileOwnVoice.isViewingOwnProfile(
                isCurrentUser: false,
                memberUserId: "11111111-1111-1111-1111-111111111111",
                authUserId: nil
            )
        )
    }

    // MARK: - rewriteMemberFacingCopy

    func test_rewrite_possessiveNameBecomesYour() {
        let out = MemberProfileOwnVoice.rewriteMemberFacingCopy(
            memberName: "Work",
            text: "I'm here to help with Work's health. What would you like to know?"
        )
        XCTAssertTrue(out.contains("your health"), "got: \(out)")
        XCTAssertFalse(out.localizedCaseInsensitiveContains("work's"))
    }

    func test_rewrite_curlyApostrophePossessive() {
        let out = MemberProfileOwnVoice.rewriteMemberFacingCopy(
            memberName: "Work",
            text: "Over the last few weeks, Work\u{2019}s overall health has remained stable."
        )
        XCTAssertTrue(out.contains("your overall"), "got: \(out)")
    }

    func test_rewrite_whatIsNameDoingWell() {
        let out = MemberProfileOwnVoice.rewriteMemberFacingCopy(
            memberName: "Work",
            text: "What is work doing well?"
        )
        XCTAssertEqual(out, "What am I doing well?")
    }

    func test_rewrite_whereDoesNameNeedSupport() {
        let out = MemberProfileOwnVoice.rewriteMemberFacingCopy(
            memberName: "Rami",
            text: "Where does Rami need support today?"
        )
        XCTAssertEqual(out, "Where do I need support today?")
    }

    func test_rewrite_howIsNameSleep() {
        let out = MemberProfileOwnVoice.rewriteMemberFacingCopy(
            memberName: "Sarah",
            text: "How is Sarah's sleep?"
        )
        XCTAssertEqual(out, "How is my sleep?")
    }

    // MARK: - suggestedPillTitleForOwnProfile

    func test_suggestedPill_knownIntentsIgnoreServerTitle() {
        XCTAssertEqual(
            MemberProfileOwnVoice.suggestedPillTitleForOwnProfile(
                memberName: "Work",
                intent: "member_doing_well",
                serverTitle: "What is Work doing well?"
            ),
            "What am I doing well?"
        )
    }

    func test_suggestedPill_unknownIntentUsesRewrite() {
        XCTAssertEqual(
            MemberProfileOwnVoice.suggestedPillTitleForOwnProfile(
                memberName: "Work",
                intent: "custom_xyz",
                serverTitle: "What is Work doing well?"
            ),
            "What am I doing well?"
        )
    }

    // MARK: - possessive / patternAlertBody

    private let joshId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private let emmaId = "11111111-1111-1111-1111-111111111111"

    func test_possessive_selfReturnsYour() {
        XCTAssertEqual(
            MemberProfileOwnVoice.possessive(firstName: "Josh", memberUserId: joshId, authUserId: joshId),
            "your"
        )
    }

    func test_possessive_otherReturnsNamePossessive() {
        XCTAssertEqual(
            MemberProfileOwnVoice.possessive(firstName: "Josh", memberUserId: emmaId, authUserId: joshId),
            "Josh's"
        )
    }

    func test_possessive_nameEndingInS() {
        XCTAssertEqual(
            MemberProfileOwnVoice.possessiveThirdPerson(firstName: "James"),
            "James'"
        )
    }

    func test_patternAlertBody_selfUsesYourBaseline() {
        let body = MemberProfileOwnVoice.patternAlertBody(
            metricDisplay: "Resting HR",
            patternDesc: "below",
            deviationText: "12%",
            levelDesc: "7d",
            firstName: "Josh",
            memberUserId: joshId,
            authUserId: joshId
        )
        XCTAssertTrue(body.contains("your baseline"), "got: \(body)")
        XCTAssertFalse(body.localizedCaseInsensitiveContains("josh's"))
    }

    func test_patternAlertBody_otherUsesNameBaseline() {
        let body = MemberProfileOwnVoice.patternAlertBody(
            metricDisplay: "Resting HR",
            patternDesc: "below",
            deviationText: "12%",
            levelDesc: "7d",
            firstName: "Emma",
            memberUserId: emmaId,
            authUserId: joshId
        )
        XCTAssertTrue(body.contains("Emma's baseline"), "got: \(body)")
    }

    func test_metricBelowBaselineSummary_self() {
        XCTAssertEqual(
            MemberProfileOwnVoice.metricBelowBaselineSummary(
                pillarLabels: ["Sleep"],
                firstName: "Josh",
                memberUserId: joshId,
                authUserId: joshId
            ),
            "Your Sleep low"
        )
    }

    func test_metricBelowBaselineSummary_other() {
        XCTAssertEqual(
            MemberProfileOwnVoice.metricBelowBaselineSummary(
                pillarLabels: ["Sleep", "Recovery"],
                firstName: "Josh",
                memberUserId: emmaId,
                authUserId: joshId
            ),
            "Josh's Sleep & Recovery low"
        )
    }

    func test_isCurrentUser_nilIds() {
        XCTAssertFalse(MemberProfileOwnVoice.isCurrentUser(memberUserId: nil, authUserId: joshId))
        XCTAssertFalse(MemberProfileOwnVoice.isCurrentUser(memberUserId: joshId, authUserId: nil))
    }
}
