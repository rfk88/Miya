//
//  ROOKDayToMiyaAdapter.swift
//  Miya Health
//
//  Maps one day of ROOK summary data to VitalityRawMetrics.
//  No scoring, no windowing—pure one-day transformation.
//
//  Paths used:
//    Sleep:  sleep_health.sleep_summaries[i].sleep_health.summary.sleep_summary
//    Physical: physical_health.physical_summaries[i].physical_health.summary.physical_summary
//

import Foundation

struct ROOKDayToMiyaAdapter {
    
    /// Map one day of ROOK summaries to VitalityRawMetrics
    /// - Parameters:
    ///   - age: User's age (passed through for scoring engine)
    ///   - sleepSummary: One element from sleep_health.sleep_summaries[]
    ///   - physicalSummary: One element from physical_health.physical_summaries[]
    /// - Returns: VitalityRawMetrics with all 10 fields mapped (nil if missing)
    static func mapOneDay(
        age: Int,
        sleepSummary: ROOKSleepSummaryWrapper?,
        physicalSummary: ROOKPhysicalSummaryWrapper?
    ) -> VitalityRawMetrics {
        
        // Extract nested data
        let sleep = sleepSummary?.sleep_health?.summary?.sleep_summary
        let physical = physicalSummary?.physical_health?.summary?.physical_summary
        
        // SLEEP DURATION
        // Path: duration.sleep_duration_seconds_int / 3600
        let sleepHours: Double? = sleep?.duration?.sleep_duration_seconds_int.map { Double($0) / 3600.0 }
        
        // RESTORATIVE SLEEP %
        // Formula: (REM + Deep) / TotalSleep * 100
        let restorativePct: Double? = {
            guard let rem = sleep?.duration?.rem_sleep_duration_seconds_int,
                  let deep = sleep?.duration?.deep_sleep_duration_seconds_int,
                  let total = sleep?.duration?.sleep_duration_seconds_int,
                  total > 0 else { return nil }
            return (Double(rem + deep) / Double(total)) * 100.0
        }()
        
        // SLEEP EFFICIENCY %
        // Path: scores.sleep_efficiency_1_100_score_int (nil if missing, no fallback calc here)
        let efficiencyPct: Double? = sleep?.scores?.sleep_efficiency_1_100_score_int.map { Double($0) }
        
        // AWAKE %
        // Formula: time_awake / time_in_bed * 100 (fallback: time_awake / sleep_duration * 100)
        let awakePct: Double? = {
            guard let awake = sleep?.duration?.time_awake_during_sleep_seconds_int else { return nil }
            let timeInBed = sleep?.duration?.time_in_bed_seconds_int
            let sleepDur = sleep?.duration?.sleep_duration_seconds_int
            // Use time_in_bed if present and > 0, else fall back to sleep_duration
            if let tib = timeInBed, tib > 0 {
                return (Double(awake) / Double(tib)) * 100.0
            } else if let dur = sleepDur, dur > 0 {
                return (Double(awake) / Double(dur)) * 100.0
            }
            return nil
        }()
        
        // HRV (prefer SDNN, else RMSSD; prefer sleep, else physical)
        let (hrvMs, hrvType): (Double?, String?) = {
            // Sleep summary HRV
            if let sdnn = sleep?.heart_rate?.hrv_avg_sdnn_float {
                return (sdnn, "sdnn")
            }
            if let rmssd = sleep?.heart_rate?.hrv_avg_rmssd_float {
                return (rmssd, "rmssd")
            }
            // Physical summary HRV fallback
            if let sdnn = physical?.heart_rate?.hrv_avg_sdnn_float {
                return (sdnn, "sdnn")
            }
            if let rmssd = physical?.heart_rate?.hrv_avg_rmssd_float {
                return (rmssd, "rmssd")
            }
            return (nil, nil)
        }()
        
        // RESTING HEART RATE (prefer sleep, else physical)
        let restingHR: Double? = {
            if let hr = sleep?.heart_rate?.hr_resting_bpm_int {
                return Double(hr)
            }
            if let hr = physical?.heart_rate?.hr_resting_bpm_int {
                return Double(hr)
            }
            return nil
        }()
        
        // BREATHING RATE
        // Path: breathing.breaths_avg_per_min_int
        let breathingRate: Double? = sleep?.breathing?.breaths_avg_per_min_int.map { Double($0) }
        
        // STEPS
        // Path: physical.distance.steps_int (optional)
        let steps: Int? = physical?.distance?.steps_int
        
        // ACTIVE CALORIES
        // Path: physical.calories.calories_net_active_kcal_float (optional)
        let activeCal: Double? = physical?.calories?.calories_net_active_kcal_float
        
        // MOVEMENT MINUTES
        // Not present in these files → nil
        let movementMin: Double? = nil
        
        return VitalityRawMetrics(
            age: age,
            sleepDurationHours: sleepHours,
            restorativeSleepPercent: restorativePct,
            sleepEfficiencyPercent: efficiencyPct,
            awakePercent: awakePct,
            movementMinutes: movementMin,
            steps: steps,
            activeCalories: activeCal,
            hrvMs: hrvMs,
            hrvType: hrvType,
            restingHeartRate: restingHR,
            breathingRate: breathingRate
        )
    }
}

