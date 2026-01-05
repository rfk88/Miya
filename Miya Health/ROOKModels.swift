//
//  ROOKModels.swift
//  Miya Health
//
//  ROOK Health API data structures
//  Field names match ROOK's snake_case JSON exactly
//

import Foundation

/// Root structure for ROOK daily data payload
struct ROOKDayPayload: Codable {
    let sleep_summary: ROOKSleepSummary?
    let physical_summary: ROOKPhysicalSummary?
}

/// Sleep summary from ROOK API
struct ROOKSleepSummary: Codable {
    // Duration metrics
    let sleep_duration_seconds_int: Int?
    let time_in_bed_seconds_int: Int?
    let time_awake_during_sleep_seconds_int: Int?
    
    // Sleep stages
    let rem_sleep_duration_seconds_int: Int?
    let deep_sleep_duration_seconds_int: Int?
    let light_sleep_duration_seconds_int: Int?
    
    // Quality metrics
    let sleep_efficiency_1_100_score_int: Int?
    
    // HRV (may have SDNN, RMSSD, or both)
    let hrv_sdnn_ms_double: Double?
    let hrv_rmssd_ms_double: Double?
    
    // Heart rate
    let hr_resting_bpm_int: Int?
    
    // Breathing
    let breaths_avg_per_min_int: Int?
}

/// Physical activity summary from ROOK API
struct ROOKPhysicalSummary: Codable {
    // Movement
    let steps_int: Int?
    let active_minutes_total_int: Int?
    
    // Calories
    let active_calories_kcal_double: Double?
    let total_calories_kcal_double: Double?
    
    // Heart rate (fallback if not in sleep)
    let hr_resting_bpm_int: Int?
    
    // HRV (fallback if not in sleep)
    let hrv_sdnn_avg_ms: Double?
    let hrv_rmssd_avg_ms: Double?
}

