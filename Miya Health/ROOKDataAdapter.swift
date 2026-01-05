//
//  ROOKDataAdapter.swift
//  Miya Health
//
//  Transforms ROOK Health API data into Miya's VitalityRawMetrics
//  Follows locked transformation rules from docs/ROOK_TO_MIYA_MAPPING.md
//

import Foundation

struct ROOKDataAdapter {
    
    /// Map a single day of ROOK data to VitalityRawMetrics
    /// - Parameters:
    ///   - age: User's age (for scoring engine)
    ///   - rookPayload: ROOK daily data (sleep + physical summaries)
    /// - Returns: VitalityRawMetrics with transformed values (nil for missing data)
    static func mapDay(age: Int, rookPayload: ROOKDayPayload) -> VitalityRawMetrics {
        let sleep = rookPayload.sleep_summary
        let physical = rookPayload.physical_summary
        
        // SLEEP DURATION (Rule B)
        // Convert seconds to hours
        let sleepHours: Double? = sleep?.sleep_duration_seconds_int.map { Double($0) / 3600.0 }
        
        // RESTORATIVE SLEEP % (Rule C)
        // (REM + Deep) / Total * 100
        let restorativePct: Double? = {
            guard let rem = sleep?.rem_sleep_duration_seconds_int,
                  let deep = sleep?.deep_sleep_duration_seconds_int,
                  let total = sleep?.sleep_duration_seconds_int,
                  total > 0 else { return nil }
            return (Double(rem + deep) / Double(total)) * 100.0
        }()
        
        // SLEEP EFFICIENCY % (Rule D)
        // Prefer ROOK's score, else calculate from duration/time_in_bed
        let efficiencyPct: Double? = {
            if let score = sleep?.sleep_efficiency_1_100_score_int {
                return Double(score)
            } else if let duration = sleep?.sleep_duration_seconds_int,
                      let timeInBed = sleep?.time_in_bed_seconds_int,
                      timeInBed > 0 {
                return (Double(duration) / Double(timeInBed)) * 100.0
            }
            return nil
        }()
        
        // AWAKE % (Rule E)
        // Awake / TimeInBed * 100, fallback to duration as denominator
        let awakePct: Double? = {
            guard let awake = sleep?.time_awake_during_sleep_seconds_int else { return nil }
            let denominator = sleep?.time_in_bed_seconds_int ?? sleep?.sleep_duration_seconds_int
            guard let denom = denominator, denom > 0 else { return nil }
            return (Double(awake) / Double(denom)) * 100.0
        }()
        
        // HRV (Rule A)
        // Primary: SDNN, Secondary: RMSSD
        // Track which type was used
        let (hrv, hrvType): (Double?, String?) = {
            if let sdnn = sleep?.hrv_sdnn_ms_double {
                return (sdnn, "sdnn")
            } else if let rmssd = sleep?.hrv_rmssd_ms_double {
                return (rmssd, "rmssd")
            } else if let sdnn = physical?.hrv_sdnn_avg_ms {
                return (sdnn, "sdnn")
            } else if let rmssd = physical?.hrv_rmssd_avg_ms {
                return (rmssd, "rmssd")
            }
            return (nil, nil)
        }()
        
        // RESTING HEART RATE (Rule G)
        // Prefer sleep-based, fallback to physical
        let rhr: Double? = sleep?.hr_resting_bpm_int.map { Double($0) }
                           ?? physical?.hr_resting_bpm_int.map { Double($0) }
        
        // BREATHING RATE (Rule F)
        let breathingRate: Double? = sleep?.breaths_avg_per_min_int.map { Double($0) }
        
        // STEPS (Rule H)
        let steps: Int? = physical?.steps_int
        
        // MOVEMENT MINUTES (Rule I)
        // Use active_minutes_total_int directly
        // (Session aggregation fallback not implemented in this phase)
        let movementMin: Double? = physical?.active_minutes_total_int.map { Double($0) }
        
        // ACTIVE CALORIES (Rule J)
        // NEVER use total_calories as fallback
        let activeCal: Double? = physical?.active_calories_kcal_double
        
        return VitalityRawMetrics(
            age: age,
            sleepDurationHours: sleepHours,
            restorativeSleepPercent: restorativePct,
            sleepEfficiencyPercent: efficiencyPct,
            awakePercent: awakePct,
            movementMinutes: movementMin,
            steps: steps,
            activeCalories: activeCal,
            hrvMs: hrv,
            hrvType: hrvType,
            restingHeartRate: rhr,
            breathingRate: breathingRate
        )
    }
}

