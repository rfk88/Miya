//
//  ROOKAdapterManualTest.swift
//  Miya Health
//
//  Manual test runner for ROOK adapter (can be called from app)
//  Uncomment in Miya_HealthApp.swift to run
//

import Foundation

struct ROOKAdapterManualTest {
    
    static func runAllTests() {
        print("\n" + String(repeating: "=", count: 60))
        print("ROOK DATA ADAPTER MANUAL TESTS")
        print(String(repeating: "=", count: 60) + "\n")
        
        testWhoopFullCoverage()
        testAppleMinimal()
        testFitbitRMSSD()
        testMissingDataHandling()
        
        print("\n" + String(repeating: "=", count: 60))
        print("ALL TESTS COMPLETED")
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    // MARK: - Test 1: Whoop Full Coverage
    
    static func testWhoopFullCoverage() {
        print("TEST 1: Whoop Full Coverage")
        print(String(repeating: "-", count: 60))
        
        let json = """
        {
          "sleep_summary": {
            "sleep_duration_seconds_int": 28800,
            "time_in_bed_seconds_int": 30600,
            "time_awake_during_sleep_seconds_int": 1800,
            "rem_sleep_duration_seconds_int": 6480,
            "deep_sleep_duration_seconds_int": 7200,
            "light_sleep_duration_seconds_int": 14400,
            "sleep_efficiency_1_100_score_int": 94,
            "hrv_sdnn_ms_double": 55.3,
            "hr_resting_bpm_int": 58,
            "breaths_avg_per_min_int": 14
          },
          "physical_summary": {
            "steps_int": 9234,
            "active_minutes_total_int": 47,
            "active_calories_kcal_double": 487.3,
            "total_calories_kcal_double": 2340.8
          }
        }
        """
        
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ROOKDayPayload.self, from: data) else {
            print("❌ FAILED: Could not parse JSON")
            return
        }
        
        let raw = ROOKDataAdapter.mapDay(age: 35, rookPayload: payload)
        
        // Verify all transformations
        assert(raw.sleepDurationHours == 8.0, "Sleep duration should be 8.0 hours")
        assert(abs(raw.restorativeSleepPercent! - 47.5) < 0.1, "Restorative % should be ~47.5%")
        assert(raw.sleepEfficiencyPercent == 94.0, "Efficiency should be 94%")
        assert(abs(raw.awakePercent! - 5.88) < 0.1, "Awake % should be ~5.88%")
        assert(raw.hrvMs == 55.3, "HRV should be 55.3")
        assert(raw.hrvType == "sdnn", "HRV type should be sdnn")
        assert(raw.restingHeartRate == 58.0, "RHR should be 58")
        assert(raw.breathingRate == 14.0, "Breathing rate should be 14")
        assert(raw.steps == 9234, "Steps should be 9234")
        assert(raw.movementMinutes == 47.0, "Movement minutes should be 47")
        assert(raw.activeCalories == 487.3, "Active calories should be 487.3")
        
        print("✅ PASSED: All 11 metrics mapped correctly")
        print("   Sleep: \(raw.sleepDurationHours!)h, Restorative: \(raw.restorativeSleepPercent!)%")
        print("   HRV: \(raw.hrvMs!)ms (\(raw.hrvType!)), RHR: \(raw.restingHeartRate!)bpm")
        print("   Steps: \(raw.steps!), Active Cal: \(raw.activeCalories!)kcal\n")
    }
    
    // MARK: - Test 2: Apple Health Minimal
    
    static func testAppleMinimal() {
        print("TEST 2: Apple Health Minimal Coverage")
        print(String(repeating: "-", count: 60))
        
        let json = """
        {
          "sleep_summary": {
            "sleep_duration_seconds_int": 25200,
            "time_in_bed_seconds_int": 27000,
            "time_awake_during_sleep_seconds_int": 1800
          },
          "physical_summary": {
            "steps_int": 8500,
            "hr_resting_bpm_int": 62
          }
        }
        """
        
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ROOKDayPayload.self, from: data) else {
            print("❌ FAILED: Could not parse JSON")
            return
        }
        
        let raw = ROOKDataAdapter.mapDay(age: 45, rookPayload: payload)
        
        // Verify minimal coverage
        assert(raw.sleepDurationHours == 7.0, "Sleep duration should be 7.0 hours")
        assert(raw.restorativeSleepPercent == nil, "Restorative % should be nil (missing data)")
        assert(abs(raw.sleepEfficiencyPercent! - 93.33) < 0.1, "Efficiency should be calculated ~93.33%")
        assert(abs(raw.awakePercent! - 6.67) < 0.1, "Awake % should be ~6.67%")
        assert(raw.hrvMs == nil, "HRV should be nil")
        assert(raw.hrvType == nil, "HRV type should be nil")
        assert(raw.restingHeartRate == 62.0, "RHR should use physical fallback")
        assert(raw.steps == 8500, "Steps should be 8500")
        assert(raw.movementMinutes == nil, "Movement minutes should be nil")
        assert(raw.activeCalories == nil, "Active calories should be nil")
        
        print("✅ PASSED: Minimal coverage with nil preservation")
        print("   Sleep: \(raw.sleepDurationHours!)h, Steps: \(raw.steps!), RHR: \(raw.restingHeartRate!)bpm")
        print("   Missing (nil): Restorative%, HRV, Movement, Calories\n")
    }
    
    // MARK: - Test 3: Fitbit RMSSD
    
    static func testFitbitRMSSD() {
        print("TEST 3: Fitbit RMSSD Fallback")
        print(String(repeating: "-", count: 60))
        
        let json = """
        {
          "sleep_summary": {
            "sleep_duration_seconds_int": 27000,
            "time_in_bed_seconds_int": 28800,
            "time_awake_during_sleep_seconds_int": 1440,
            "rem_sleep_duration_seconds_int": 5400,
            "deep_sleep_duration_seconds_int": 8100,
            "light_sleep_duration_seconds_int": 12600,
            "hrv_rmssd_ms_double": 42.7,
            "hr_resting_bpm_int": 60
          },
          "physical_summary": {
            "steps_int": 7800,
            "active_minutes_total_int": 35,
            "active_calories_kcal_double": 320.5,
            "total_calories_kcal_double": 2100.0
          }
        }
        """
        
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ROOKDayPayload.self, from: data) else {
            print("❌ FAILED: Could not parse JSON")
            return
        }
        
        let raw = ROOKDataAdapter.mapDay(age: 50, rookPayload: payload)
        
        // Verify RMSSD fallback
        assert(raw.hrvMs == 42.7, "HRV should use RMSSD value")
        assert(raw.hrvType == "rmssd", "HRV type should be rmssd")
        assert(raw.hrvMs != 42.7 * 1.3, "HRV should NOT be converted")
        
        print("✅ PASSED: RMSSD fallback without conversion")
        print("   HRV: \(raw.hrvMs!)ms (type: \(raw.hrvType!))")
        print("   ⚠️  Correctly preserved RMSSD raw value (no SDNN conversion)\n")
    }
    
    // MARK: - Test 4: Missing Data Handling
    
    static func testMissingDataHandling() {
        print("TEST 4: Missing Data Handling (Never Substitute Zero)")
        print(String(repeating: "-", count: 60))
        
        let json = """
        {
          "sleep_summary": {
            "sleep_duration_seconds_int": 25200
          },
          "physical_summary": {
            "steps_int": 5000
          }
        }
        """
        
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ROOKDayPayload.self, from: data) else {
            print("❌ FAILED: Could not parse JSON")
            return
        }
        
        let raw = ROOKDataAdapter.mapDay(age: 40, rookPayload: payload)
        
        // Verify nil preservation (never 0)
        assert(raw.sleepDurationHours != nil, "Sleep should be present")
        assert(raw.steps != nil, "Steps should be present")
        assert(raw.restorativeSleepPercent == nil, "Restorative % should be nil, not 0")
        assert(raw.sleepEfficiencyPercent == nil, "Efficiency should be nil, not 0")
        assert(raw.awakePercent == nil, "Awake % should be nil, not 0")
        assert(raw.hrvMs == nil, "HRV should be nil, not 0")
        assert(raw.restingHeartRate == nil, "RHR should be nil, not 0")
        assert(raw.breathingRate == nil, "Breathing should be nil, not 0")
        assert(raw.movementMinutes == nil, "Movement should be nil, not 0")
        assert(raw.activeCalories == nil, "Calories should be nil, not 0")
        
        print("✅ PASSED: All missing fields are nil (never 0)")
        print("   Present: Sleep (\(raw.sleepDurationHours!)h), Steps (\(raw.steps!))")
        print("   Missing (nil): 8 other metrics\n")
    }
}

