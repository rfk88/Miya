import XCTest
@testable import Miya_Health

/// Behavior-driven tests for `DashboardVitalityBannerEvaluator` (banner priority: initialIngest > resync > none).
/// Inputs mirror dashboard state for the logged-in user only.
final class DashboardVitalityBannerEvaluatorTests: XCTestCase {

    private let uid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    // MARK: - Helpers

    private func makeMe(hasScore: Bool) -> FamilyMemberScore {
        FamilyMemberScore(
            name: "Me",
            initials: "M",
            userId: uid,
            hasScore: hasScore,
            isScoreFresh: hasScore,
            isStale: false,
            currentScore: hasScore ? 72 : 0,
            optimalScore: 80,
            progressScore: hasScore ? 70 : nil,
            inviteStatus: nil,
            onboardingType: nil,
            guidedSetupStatus: nil,
            isMe: true,
            vitalityScoreUpdatedAt: hasScore ? Date() : nil
        )
    }

    // MARK: - No user id → no banner

    func test_banner_none_whenCurrentUserIdNil() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: nil,
            me: makeMe(hasScore: false),
            isWearableSyncing: true,
            isDataInsufficient: true,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .none)
    }

    // MARK: - Banner A: initial ingest

    func test_banner_initialIngest_whenSyncingAndNoBaselineYet() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: true,
            isDataInsufficient: false,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .initialIngest)
    }

    func test_banner_initialIngest_whenDataInsufficientEvenIfNotSyncing() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: false,
            isDataInsufficient: true,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .initialIngest)
    }

    /// First dashboard paint: no sync flags yet — still show "please wait" (Banner A), not resync.
    func test_banner_initialIngest_whenFirstBaselineAttemptNotYetRun_evenIfIdle() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .initialIngest)
    }

    func test_banner_initialIngest_takesPriorityOverResync_whenBothCouldApply() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: true,
            isDataInsufficient: true,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .initialIngest)
    }

    func test_banner_none_whenUserHasScore_evenIfBaselineFlagFalse() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: true),
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .none)
        XCTAssertTrue(e.initialBaselineComplete)
    }

    /// Persisted baseline complete but family strip not loaded yet — suppress Banner B until `me` hydrates.
    func test_banner_none_whenPersistedBaselineCompleted_evenIfMeRowMissing() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: nil,
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: true,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .none)
    }

    // MARK: - Banner B: resync

    func test_banner_resync_whenNotInIngestPhase_andNoVitality() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: true,
            hasCompletedFirstBaselineAttempt: true
        )
        XCTAssertEqual(e.banner, .resync)
    }

    /// No `me` row yet; first baseline attempt finished — missing vitality resync.
    func test_banner_resync_whenMeNil_andFirstAttemptFinished() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: nil,
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: true
        )
        XCTAssertEqual(e.banner, .resync)
    }

    /// No `me` row yet; still waiting on first baseline attempt — stay on Banner A.
    func test_banner_initialIngest_whenMeNil_andFirstAttemptNotFinished() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: nil,
            isWearableSyncing: false,
            isDataInsufficient: false,
            initialBaselineEverCompleted: false,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertEqual(e.banner, .initialIngest)
    }

    // MARK: - Derived flags

    func test_currentUserHasVitality_followsMeHasScore() {
        XCTAssertFalse(
            DashboardVitalityBannerEvaluator(
                currentUserId: uid,
                me: makeMe(hasScore: false),
                isWearableSyncing: false,
                isDataInsufficient: false,
                initialBaselineEverCompleted: true,
                hasCompletedFirstBaselineAttempt: true
            ).currentUserHasVitality
        )
        XCTAssertTrue(
            DashboardVitalityBannerEvaluator(
                currentUserId: uid,
                me: makeMe(hasScore: true),
                isWearableSyncing: false,
                isDataInsufficient: false,
                initialBaselineEverCompleted: false,
                hasCompletedFirstBaselineAttempt: false
            ).currentUserHasVitality
        )
    }

    func test_isInInitialIngestPhase_falseWhenBaselineCompleteViaPersistence() {
        let e = DashboardVitalityBannerEvaluator(
            currentUserId: uid,
            me: makeMe(hasScore: false),
            isWearableSyncing: true,
            isDataInsufficient: true,
            initialBaselineEverCompleted: true,
            hasCompletedFirstBaselineAttempt: false
        )
        XCTAssertFalse(e.isInInitialIngestPhase)
        XCTAssertEqual(e.banner, .resync)
    }
}
