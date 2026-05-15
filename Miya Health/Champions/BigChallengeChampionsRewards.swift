import Foundation

/// Champions bonus points for BIG (competitive) challenge outcomes.
/// Tune with product; server should log grants in `big_challenge_champion_point_events` when evaluation ships.
enum BigChallengeChampionsRewards {
    /// Winner of a 1v1 BIG challenge.
    static let duelWinnerPoints: Int = 50
    /// First place in a family brawl (max 6 participants).
    static let brawlFirstPlacePoints: Int = 75
    static let brawlSecondPlacePoints: Int = 40
    static let brawlThirdPlacePoints: Int = 25
    /// Everyone else who finished a brawl with a recorded score (optional product lever).
    static let brawlParticipantCompletionPoints: Int = 10

    static func pointsForBrawl(placement: Int) -> Int? {
        switch placement {
        case 1: return brawlFirstPlacePoints
        case 2: return brawlSecondPlacePoints
        case 3: return brawlThirdPlacePoints
        case 4...6: return brawlParticipantCompletionPoints
        default: return nil
        }
    }
}
