import Foundation

/// Row content for member profile pillar cards (sleep / movement / recovery).
struct ProfilePillarData: Equatable {
    let value: String
    let status: PillarStatus
    let changeText: String
    let context: String
}

enum PillarStatus: Equatable {
    case above, stable, below
}
