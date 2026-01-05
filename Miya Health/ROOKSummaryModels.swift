//
//  ROOKSummaryModels.swift
//  Miya Health
//
//  Codable models matching the nested ROOK export JSON structure.
//  Paths:
//    sleep_health.sleep_summaries[i].sleep_health.summary.sleep_summary
//    physical_health.physical_summaries[i].physical_health.summary.physical_summary
//

import Foundation

// MARK: - Root Dataset

struct ROOKDataset: Codable {
    let data_structure: String?
    let version: Int?
    let created_at: String?
    let body_health: ROOKBodyHealth?
    let physical_health: ROOKPhysicalHealth?
    let sleep_health: ROOKSleepHealth?
}

// MARK: - Sleep Health

struct ROOKSleepHealth: Codable {
    let sleep_summaries: [ROOKSleepSummaryWrapper]?
}

struct ROOKSleepSummaryWrapper: Codable {
    let version: Int?
    let data_structure: String?
    let client_uuid: String?
    let user_id: String?
    let document_version: Int?
    let sleep_health: ROOKSleepSummaryContainer?
}

struct ROOKSleepSummaryContainer: Codable {
    let summary: ROOKSleepSummarySummary?
}

struct ROOKSleepSummarySummary: Codable {
    let sleep_summary: ROOKSleepSummaryData?
}

struct ROOKSleepSummaryData: Codable {
    let duration: ROOKSleepDuration?
    let scores: ROOKSleepScores?
    let heart_rate: ROOKSleepHeartRate?
    let breathing: ROOKSleepBreathing?
    let metadata: ROOKMetadata?
}

struct ROOKSleepDuration: Codable {
    let sleep_start_datetime_string: String?
    let sleep_end_datetime_string: String?
    let sleep_date_string: String?
    let sleep_duration_seconds_int: Int?
    let time_in_bed_seconds_int: Int?
    let light_sleep_duration_seconds_int: Int?
    let rem_sleep_duration_seconds_int: Int?
    let deep_sleep_duration_seconds_int: Int?
    let time_to_fall_asleep_seconds_int: Int?
    let time_awake_during_sleep_seconds_int: Int?
}

struct ROOKSleepScores: Codable {
    let sleep_quality_rating_1_5_score_int: Int?
    let sleep_efficiency_1_100_score_int: Int?
    let sleep_goal_seconds_int: Int?
    let sleep_continuity_1_5_score_int: Int?
    let sleep_continuity_1_5_rating_int: Int?
}

struct ROOKSleepHeartRate: Codable {
    let hr_maximum_bpm_int: Int?
    let hr_minimum_bpm_int: Int?
    let hr_avg_bpm_int: Int?
    let hr_resting_bpm_int: Int?
    let hr_basal_bpm_int: Int?
    let hrv_avg_rmssd_float: Double?
    let hrv_avg_sdnn_float: Double?
}

struct ROOKSleepBreathing: Codable {
    let breaths_minimum_per_min_int: Int?
    let breaths_avg_per_min_int: Int?
    let breaths_maximum_per_min_int: Int?
    let saturation_avg_percentage_int: Int?
    let saturation_minimum_percentage_int: Int?
    let saturation_maximum_percentage_int: Int?
}

// MARK: - Physical Health

struct ROOKPhysicalHealth: Codable {
    let physical_summaries: [ROOKPhysicalSummaryWrapper]?
    let activity_events: [ROOKActivityEvent]?
}

struct ROOKPhysicalSummaryWrapper: Codable {
    let version: Int?
    let data_structure: String?
    let client_uuid: String?
    let user_id: String?
    let document_version: Int?
    let physical_health: ROOKPhysicalSummaryContainer?
}

struct ROOKPhysicalSummaryContainer: Codable {
    let summary: ROOKPhysicalSummarySummary?
}

struct ROOKPhysicalSummarySummary: Codable {
    let physical_summary: ROOKPhysicalSummaryData?
}

struct ROOKPhysicalSummaryData: Codable {
    let distance: ROOKPhysicalDistance?
    let calories: ROOKPhysicalCalories?
    let heart_rate: ROOKPhysicalHeartRate?
    let activity: ROOKPhysicalActivity?
    let metadata: ROOKMetadata?
}

struct ROOKPhysicalDistance: Codable {
    let steps_int: Int?
    let active_steps_int: Int?
    let walked_distance_meters_float: Double?
    let traveled_distance_meters_float: Double?
    let floors_climbed_float: Double?
}

struct ROOKPhysicalCalories: Codable {
    let calories_net_intake_kcal_float: Double?
    let calories_expenditure_kcal_float: Double?
    let calories_net_active_kcal_float: Double?
    let calories_basal_metabolic_rate_kcal_float: Double?
}

struct ROOKPhysicalHeartRate: Codable {
    let hr_maximum_bpm_int: Int?
    let hr_minimum_bpm_int: Int?
    let hr_avg_bpm_int: Int?
    let hr_resting_bpm_int: Int?
    let hrv_avg_rmssd_float: Double?
    let hrv_avg_sdnn_float: Double?
}

struct ROOKPhysicalActivity: Codable {
    let active_seconds_int: Int?
    let rest_seconds_int: Int?
    let low_intensity_seconds_int: Int?
    let moderate_intensity_seconds_int: Int?
    let vigorous_intensity_seconds_int: Int?
    let inactivity_seconds_int: Int?
}

// MARK: - Body Health (for completeness)

struct ROOKBodyHealth: Codable {
    let body_summaries: [ROOKBodySummaryWrapper]?
}

struct ROOKBodySummaryWrapper: Codable {
    let version: Int?
    let user_id: String?
}

// MARK: - Activity Events

struct ROOKActivityEvent: Codable {
    let version: Int?
    let user_id: String?
}

// MARK: - Shared

struct ROOKMetadata: Codable {
    let datetime_string: String?
    let user_id_string: String?
    let sources_of_data_array: [String]?
}

