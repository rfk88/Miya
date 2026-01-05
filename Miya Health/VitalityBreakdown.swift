import Foundation

enum VitalityStatus: String, Codable {
    case optimal
    case ok
    case low
    case missing
}

struct SubmetricBreakdown: Codable, Identifiable {
    let id: String              // stable key, e.g. "sleep.duration"
    let label: String           // "Sleep duration"
    let valueText: String       // "8.13 h" or "nil"
    let targetText: String      // "7.5–8.5 h" (from schema) or "see engine"
    let points: Double
    let maxPoints: Double
    let status: VitalityStatus
    let notes: String?
}

struct PillarBreakdown: Codable {
    let id: String              // "sleep" | "movement" | "stress"
    let label: String
    let score: Double
    let maxScore: Double
    let submetrics: [SubmetricBreakdown]
}

struct VitalityBreakdown: Codable {
    let totalScore: Double
    let totalMaxScore: Double
    let pillarsUsed: Int
    let pillarsPossible: Int
    let pillars: [PillarBreakdown]
}


