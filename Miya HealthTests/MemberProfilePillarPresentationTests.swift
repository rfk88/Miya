import XCTest
@testable import Miya_Health

final class MemberProfilePillarPresentationTests: XCTestCase {

    func test_fromStoredScore_mapsBands_andCopy() {
        let high = MemberProfilePillarPresentation.pillarData(fromStoredScore: 88, displayName: "Sleep")
        XCTAssertEqual(high.value, "88")
        XCTAssertEqual(high.status, .above)
        XCTAssertEqual(high.changeText, "Out of 100")
        XCTAssertEqual(high.context, "Sleep pillar · from your wearables")

        let mid = MemberProfilePillarPresentation.pillarData(fromStoredScore: 72, displayName: "Movement")
        XCTAssertEqual(mid.status, .stable)

        let low = MemberProfilePillarPresentation.pillarData(fromStoredScore: 45, displayName: "Recovery")
        XCTAssertEqual(low.status, .below)

        let boundaryHigh = MemberProfilePillarPresentation.pillarData(fromStoredScore: 80, displayName: "Sleep")
        XCTAssertEqual(boundaryHigh.status, .above)

        let boundaryStable = MemberProfilePillarPresentation.pillarData(fromStoredScore: 79, displayName: "Sleep")
        XCTAssertEqual(boundaryStable.status, .stable)
    }

    func test_merge_prefersStoredWhenNonNegative() {
        let raw = ProfilePillarData(
            value: "5000 steps",
            status: .stable,
            changeText: "legacy",
            context: "legacy"
        )
        let merged = MemberProfilePillarPresentation.pillarData(stored: 100, raw: raw, displayName: "Movement")
        XCTAssertEqual(merged?.value, "100")
        XCTAssertEqual(merged?.status, .above)
    }

    func test_merge_nilStoredUsesRaw() {
        let raw = ProfilePillarData(
            value: "7.0 hours",
            status: .below,
            changeText: "↓",
            context: "Sleep vs baseline"
        )
        let merged = MemberProfilePillarPresentation.pillarData(stored: nil, raw: raw, displayName: "Sleep")
        XCTAssertEqual(merged, raw)
    }

    func test_merge_negativeStoredUsesRaw() {
        let raw = ProfilePillarData(
            value: "legacy",
            status: .stable,
            changeText: "x",
            context: "y"
        )
        let merged = MemberProfilePillarPresentation.pillarData(stored: -1, raw: raw, displayName: "Sleep")
        XCTAssertEqual(merged, raw)
    }

    func test_merge_zeroStoredUsesStored_notRaw() {
        let raw = ProfilePillarData(value: "raw", status: .above, changeText: "r", context: "r")
        let merged = MemberProfilePillarPresentation.pillarData(stored: 0, raw: raw, displayName: "Recovery")
        XCTAssertEqual(merged?.value, "0")
        XCTAssertEqual(merged?.status, .below)
    }
}
