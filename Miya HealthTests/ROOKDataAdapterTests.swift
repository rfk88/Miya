//
//  ROOKDataAdapterTests.swift
//  Miya HealthTests
//
//  Unit tests for ROOK data adapter
//  Tests all transformation rules from docs/ROOK_TO_MIYA_MAPPING.md
//

import XCTest
@testable import Miya_Health

final class ROOKDataAdapterTests: XCTestCase {
    
    // MARK: - Test Data Loading
    
    func loadROOKSample(_ filename: String) throws -> ROOKDayPayload {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            // Fallback: try loading from project root
            let projectRoot = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let fileURL = projectRoot.appendingPathComponent("\(filename).json")
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ROOKDayPayload.self, from: data)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ROOKDayPayload.self, from: data)
    }
    
    // MARK: - Full Coverage Tests (Whoop)
    
    func testWhoopFullCoverage() throws {
        let payload = try loadROOKSample("rook_sample_whoop_day")
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Sleep Duration (Rule B): 28800 seconds / 3600 = 8.0 hours
        XCTAssertEqual(raw.sleepDurationHours, 8.0, accuracy: 0.01)
        
        // Restorative Sleep % (Rule C): (6480 + 7200) / 28800 * 100 = 47.5%
        XCTAssertNotNil(raw.restorativeSleepPercent)
        XCTAssertEqual(raw.restorativeSleepPercent!, 47.5, accuracy: 0.1)
        
        // Sleep Efficiency % (Rule D): Use ROOK's score directly
        XCTAssertEqual(raw.sleepEfficiencyPercent, 94.0, accuracy: 0.01)
        
        // Awake % (Rule E): 1800 / 30600 * 100 = 5.88%
        XCTAssertNotNil(raw.awakePercent)
        XCTAssertEqual(raw.awakePercent!, 5.88, accuracy: 0.1)
        
        // HRV (Rule A): SDNN present, should use it
        XCTAssertEqual(raw.hrvMs, 55.3, accuracy: 0.01)
        XCTAssertEqual(raw.hrvType, "sdnn")
        
        // Resting Heart Rate (Rule G): Sleep-based RHR
        XCTAssertEqual(raw.restingHeartRate, 58.0, accuracy: 0.01)
        
        // Breathing Rate (Rule F): Direct mapping
        XCTAssertEqual(raw.breathingRate, 14.0, accuracy: 0.01)
        
        // Steps (Rule H): Direct mapping
        XCTAssertEqual(raw.steps, 9234)
        
        // Movement Minutes (Rule I): Direct mapping
        XCTAssertEqual(raw.movementMinutes, 47.0, accuracy: 0.01)
        
        // Active Calories (Rule J): Direct mapping, NOT total calories
        XCTAssertEqual(raw.activeCalories, 487.3, accuracy: 0.1)
    }
    
    // MARK: - Minimal Coverage Tests (Apple Health)
    
    func testAppleHealthMinimal() throws {
        let payload = try loadROOKSample("rook_sample_apple_minimal")
        let raw = ROOKDataAdapter.mapDay(age: 45, rookPayload: payload)
        
        // Sleep Duration: 25200 / 3600 = 7.0 hours
        XCTAssertEqual(raw.sleepDurationHours, 7.0, accuracy: 0.01)
        
        // Restorative Sleep %: Missing REM/Deep data
        XCTAssertNil(raw.restorativeSleepPercent)
        
        // Sleep Efficiency %: No ROOK score, calculate from duration/time_in_bed
        // 25200 / 27000 * 100 = 93.33%
        XCTAssertNotNil(raw.sleepEfficiencyPercent)
        XCTAssertEqual(raw.sleepEfficiencyPercent!, 93.33, accuracy: 0.1)
        
        // Awake %: 1800 / 27000 * 100 = 6.67%
        XCTAssertNotNil(raw.awakePercent)
        XCTAssertEqual(raw.awakePercent!, 6.67, accuracy: 0.1)
        
        // HRV: Missing
        XCTAssertNil(raw.hrvMs)
        XCTAssertNil(raw.hrvType)
        
        // Resting Heart Rate: Physical summary fallback
        XCTAssertEqual(raw.restingHeartRate, 62.0, accuracy: 0.01)
        
        // Breathing Rate: Missing
        XCTAssertNil(raw.breathingRate)
        
        // Steps: Present
        XCTAssertEqual(raw.steps, 8500)
        
        // Movement Minutes: Missing
        XCTAssertNil(raw.movementMinutes)
        
        // Active Calories: Missing
        XCTAssertNil(raw.activeCalories)
    }
    
    // MARK: - HRV Fallback Tests (Fitbit RMSSD)
    
    func testFitbitRMSSDFallback() throws {
        let payload = try loadROOKSample("rook_sample_fitbit_rmssd")
        let raw = ROOKDataAdapter.mapDay(age: 50, rookPayload: payload)
        
        // HRV: SDNN missing, should use RMSSD
        XCTAssertEqual(raw.hrvMs, 42.7, accuracy: 0.01)
        XCTAssertEqual(raw.hrvType, "rmssd")
        
        // Verify RMSSD was NOT converted to SDNN
        // (If it was converted, value would be different)
        XCTAssertNotEqual(raw.hrvMs, 42.7 * 1.3) // Common but wrong conversion
    }
    
    // MARK: - Missing Data Handling
    
    func testMissingDataPreservesNil() throws {
        let payload = try loadROOKSample("rook_sample_apple_minimal")
        let raw = ROOKDataAdapter.mapDay(age: 40, rookPayload: payload)
        
        // Verify nil is preserved, NOT substituted with 0
        XCTAssertNil(raw.restorativeSleepPercent)
        XCTAssertNil(raw.hrvMs)
        XCTAssertNil(raw.breathingRate)
        XCTAssertNil(raw.movementMinutes)
        XCTAssertNil(raw.activeCalories)
    }
    
    // MARK: - Active Calories Never Uses Total
    
    func testActiveCaloriesNeverUsesTotal() throws {
        let payload = try loadROOKSample("rook_sample_apple_minimal")
        let raw = ROOKDataAdapter.mapDay(age: 30, rookPayload: payload)
        
        // Active calories missing, total calories present
        // Verify active calories is nil, NOT set to total
        XCTAssertNil(raw.activeCalories)
        
        // If we had incorrectly used total_calories, this would fail
        // (Apple minimal has no active_calories but would have total in real data)
    }
    
    // MARK: - Safe Division Tests
    
    func testSafeDivisionForEfficiency() {
        // Test with zero time_in_bed (should return nil, not crash)
        let payload = ROOKDayPayload(
            sleep_summary: ROOKSleepSummary(
                sleep_duration_seconds_int: 28800,
                time_in_bed_seconds_int: 0,  // Zero denominator
                time_awake_during_sleep_seconds_int: nil,
                rem_sleep_duration_seconds_int: nil,
                deep_sleep_duration_seconds_int: nil,
                light_sleep_duration_seconds_int: nil,
                sleep_efficiency_1_100_score_int: nil,
                hrv_sdnn_ms_double: nil,
                hrv_rmssd_ms_double: nil,
                hr_resting_bpm_int: nil,
                breaths_avg_per_min_int: nil
            ),
            physical_summary: nil
        )
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Should be nil, not crash or produce invalid value
        XCTAssertNil(raw.sleepEfficiencyPercent)
    }
    
    func testSafeDivisionForAwakePercent() {
        // Test with zero denominator
        let payload = ROOKDayPayload(
            sleep_summary: ROOKSleepSummary(
                sleep_duration_seconds_int: 0,  // Will be used as fallback denominator
                time_in_bed_seconds_int: 0,
                time_awake_during_sleep_seconds_int: 1800,
                rem_sleep_duration_seconds_int: nil,
                deep_sleep_duration_seconds_int: nil,
                light_sleep_duration_seconds_int: nil,
                sleep_efficiency_1_100_score_int: nil,
                hrv_sdnn_ms_double: nil,
                hrv_rmssd_ms_double: nil,
                hr_resting_bpm_int: nil,
                breaths_avg_per_min_int: nil
            ),
            physical_summary: nil
        )
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Should be nil, not crash
        XCTAssertNil(raw.awakePercent)
    }
    
    func testSafeDivisionForRestorativePercent() {
        // Test with zero total sleep duration
        let payload = ROOKDayPayload(
            sleep_summary: ROOKSleepSummary(
                sleep_duration_seconds_int: 0,  // Zero denominator
                time_in_bed_seconds_int: nil,
                time_awake_during_sleep_seconds_int: nil,
                rem_sleep_duration_seconds_int: 3600,
                deep_sleep_duration_seconds_int: 3600,
                light_sleep_duration_seconds_int: nil,
                sleep_efficiency_1_100_score_int: nil,
                hrv_sdnn_ms_double: nil,
                hrv_rmssd_ms_double: nil,
                hr_resting_bpm_int: nil,
                breaths_avg_per_min_int: nil
            ),
            physical_summary: nil
        )
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Should be nil, not crash or produce invalid value
        XCTAssertNil(raw.restorativeSleepPercent)
    }
    
    // MARK: - Awake Percent Denominator Fallback
    
    func testAwakePercentFallbackDenominator() {
        // Test with time_in_bed missing, should use sleep_duration
        let payload = ROOKDayPayload(
            sleep_summary: ROOKSleepSummary(
                sleep_duration_seconds_int: 28800,
                time_in_bed_seconds_int: nil,  // Missing
                time_awake_during_sleep_seconds_int: 1800,
                rem_sleep_duration_seconds_int: nil,
                deep_sleep_duration_seconds_int: nil,
                light_sleep_duration_seconds_int: nil,
                sleep_efficiency_1_100_score_int: nil,
                hrv_sdnn_ms_double: nil,
                hrv_rmssd_ms_double: nil,
                hr_resting_bpm_int: nil,
                breaths_avg_per_min_int: nil
            ),
            physical_summary: nil
        )
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Should use sleep_duration as denominator: 1800 / 28800 * 100 = 6.25%
        XCTAssertNotNil(raw.awakePercent)
        XCTAssertEqual(raw.awakePercent!, 6.25, accuracy: 0.1)
    }
    
    // MARK: - RHR Fallback Tests
    
    func testRHRFallbackToPhysical() {
        // Test with sleep RHR missing, should use physical
        let payload = ROOKDayPayload(
            sleep_summary: ROOKSleepSummary(
                sleep_duration_seconds_int: 28800,
                time_in_bed_seconds_int: nil,
                time_awake_during_sleep_seconds_int: nil,
                rem_sleep_duration_seconds_int: nil,
                deep_sleep_duration_seconds_int: nil,
                light_sleep_duration_seconds_int: nil,
                sleep_efficiency_1_100_score_int: nil,
                hrv_sdnn_ms_double: nil,
                hrv_rmssd_ms_double: nil,
                hr_resting_bpm_int: nil,  // Missing in sleep
                breaths_avg_per_min_int: nil
            ),
            physical_summary: ROOKPhysicalSummary(
                steps_int: 8000,
                active_minutes_total_int: nil,
                active_calories_kcal_double: nil,
                total_calories_kcal_double: nil,
                hr_resting_bpm_int: 65,  // Present in physical
                hrv_sdnn_avg_ms: nil,
                hrv_rmssd_avg_ms: nil
            )
        )
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Should use physical RHR
        XCTAssertEqual(raw.restingHeartRate, 65.0, accuracy: 0.01)
    }
}

