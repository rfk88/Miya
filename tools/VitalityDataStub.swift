import Foundation

// Stub for building the scoring fixture generator with `swiftc`.
// The app target defines legacy `VitalityData` elsewhere, but that file may not
// compile in this minimal CLI build. The scoring engine references `VitalityData`
// only in `VitalityMetricsBuilder` helpers, which are not used by the fixture tool.
struct VitalityData {
    let date: Date
    let sleepHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    let steps: Int?
    let hrvMs: Double?
    let restingHr: Double?
}


