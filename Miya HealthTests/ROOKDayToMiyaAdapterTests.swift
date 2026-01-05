//
//  ROOKDayToMiyaAdapterTests.swift
//  Miya HealthTests
//
//  Unit tests for ROOKDayToMiyaAdapter using real ROOK sample files.
//

import XCTest
import Foundation
@testable import Miya_Health

final class ROOKDayToMiyaAdapterTests: XCTestCase {
    
    // MARK: - Helpers
    
    func loadROOKDataset(_ filename: String) throws -> ROOKDataset {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent("Rook Samples/\(filename)")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ROOKDataset.self, from: data)
    }
    
    private func assertEqualOptionalDouble(
        _ lhs: Double?,
        _ rhs: Double?,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (lhs, rhs) {
        case let (l?, r?):
            XCTAssertEqual(l, r, accuracy: accuracy, file: file, line: line)
        case (nil, nil):
            XCTAssertNil(lhs, file: file, line: line)
            XCTAssertNil(rhs, file: file, line: line)
        default:
            XCTFail("Expected both values to be nil or both non-nil, got lhs=\(String(describing: lhs)) rhs=\(String(describing: rhs))", file: file, line: line)
        }
    }
    
    private func normalizeUTCYYYYMMDD(from raw: String) -> String? {
        // Fast path: "YYYY-MM-DD" prefix
        if raw.count >= 10 {
            let prefix10 = String(raw.prefix(10))
            let chars = Array(prefix10)
            if chars.count == 10, chars[4] == "-", chars[7] == "-" {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd"
                if df.date(from: prefix10) != nil {
                    return prefix10
                }
            }
        }
        
        // ISO8601 parsing (with and without fractional seconds)
        let isoFrac = ISO8601DateFormatter()
        isoFrac.timeZone = TimeZone(secondsFromGMT: 0)
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: raw) {
            return formatUTCYYYYMMDD(d)
        }
        
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) {
            return formatUTCYYYYMMDD(d)
        }
        
        // Fallback: replace space with "T"
        let normalized = raw.replacingOccurrences(of: " ", with: "T")
        if let d = isoFrac.date(from: normalized) ?? iso.date(from: normalized) {
            return formatUTCYYYYMMDD(d)
        }
        
        return nil
    }
    
    private func formatUTCYYYYMMDD(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    private func findSleepSummary(forDayKey dayKey: String, in dataset: ROOKDataset) -> ROOKSleepSummaryWrapper? {
        guard let arr = dataset.sleep_health?.sleep_summaries else { return nil }
        for item in arr {
            guard let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string,
                  let k = normalizeUTCYYYYMMDD(from: raw) else { continue }
            if k == dayKey { return item }
        }
        return nil
    }
    
    private func findPhysicalSummary(forDayKey dayKey: String, in dataset: ROOKDataset) -> ROOKPhysicalSummaryWrapper? {
        guard let arr = dataset.physical_health?.physical_summaries else { return nil }
        for item in arr {
            guard let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string,
                  let k = normalizeUTCYYYYMMDD(from: raw) else { continue }
            if k == dayKey { return item }
        }
        return nil
    }
    
    private func mostRecentMatchedDayKey(in dataset: ROOKDataset) -> String? {
        let sleepKeys: Set<String> = {
            guard let arr = dataset.sleep_health?.sleep_summaries else { return [] }
            var s: Set<String> = []
            for item in arr {
                guard let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string,
                      let k = normalizeUTCYYYYMMDD(from: raw) else { continue }
                s.insert(k)
            }
            return s
        }()
        let physicalKeys: Set<String> = {
            guard let arr = dataset.physical_health?.physical_summaries else { return [] }
            var s: Set<String> = []
            for item in arr {
                guard let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string,
                      let k = normalizeUTCYYYYMMDD(from: raw) else { continue }
                s.insert(k)
            }
            return s
        }()
        let intersection = sleepKeys.intersection(physicalKeys)
        return intersection.sorted().last
    }
    
    // MARK: - Whoop Tests
    
    func testWhoopDayMapping() throws {
        let dataset = try loadROOKDataset("ROOKConnect-Whoop-dataset-v2.json")
        
        guard let dayKey = mostRecentMatchedDayKey(in: dataset) else {
            XCTFail("No matched day key found in Whoop dataset")
            return
        }
        guard let sleepWrapper = findSleepSummary(forDayKey: dayKey, in: dataset),
              let physicalWrapper = findPhysicalSummary(forDayKey: dayKey, in: dataset) else {
            XCTFail("Could not find matched sleep+physical summaries for Whoop dayKey=\(dayKey)")
            return
        }

        // Assert raw source fields exist before asserting computed values
        let sleep = sleepWrapper.sleep_health?.summary?.sleep_summary
        let physical = physicalWrapper.physical_health?.summary?.physical_summary
        let dur = sleep?.duration
        let scores = sleep?.scores
        let sleepHR = sleep?.heart_rate
        let breathing = sleep?.breathing
        let dist = physical?.distance
        let cals = physical?.calories
        let physHR = physical?.heart_rate
        
        XCTAssertNotNil(dur?.sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.rem_sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.deep_sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.time_awake_during_sleep_seconds_int)
        XCTAssertNotNil(dur?.time_in_bed_seconds_int)
        XCTAssertNotNil(scores?.sleep_efficiency_1_100_score_int)
        XCTAssertNotNil(breathing?.breaths_avg_per_min_int)
        XCTAssertNotNil(cals?.calories_net_active_kcal_float)
        XCTAssertTrue((sleepHR?.hr_resting_bpm_int != nil) || (physHR?.hr_resting_bpm_int != nil))
        
        let raw = ROOKDayToMiyaAdapter.mapOneDay(
            age: 35,
            sleepSummary: sleepWrapper,
            physicalSummary: physicalWrapper
        )
        
        // Verify age passed through
        XCTAssertEqual(raw.age, 35)
        
        // Sleep Duration: sleep_duration_seconds_int / 3600
        let sleepSeconds = dur!.sleep_duration_seconds_int!
        XCTAssertNotNil(raw.sleepDurationHours)
        XCTAssertEqual(raw.sleepDurationHours!, Double(sleepSeconds) / 3600.0, accuracy: 0.0001)
        
        // Restorative %: (REM + Deep) / Total * 100
        let rem = dur!.rem_sleep_duration_seconds_int!
        let deep = dur!.deep_sleep_duration_seconds_int!
        XCTAssertNotNil(raw.restorativeSleepPercent)
        XCTAssertEqual(raw.restorativeSleepPercent!, (Double(rem + deep) / Double(sleepSeconds)) * 100.0, accuracy: 0.0001)
        
        // Sleep Efficiency: score-only mapping
        let eff = scores!.sleep_efficiency_1_100_score_int
        XCTAssertNotNil(eff)
        assertEqualOptionalDouble(raw.sleepEfficiencyPercent, Double(eff!), accuracy: 0.0001)
        
        // Awake % uses time_in_bed if present and >0, else uses sleep_duration
        let awakeSeconds = dur!.time_awake_during_sleep_seconds_int!
        let timeInBed = dur!.time_in_bed_seconds_int
        XCTAssertNotNil(raw.awakePercent)
        if let tib = timeInBed, tib > 0 {
            XCTAssertEqual(raw.awakePercent!, (Double(awakeSeconds) / Double(tib)) * 100.0, accuracy: 0.0001)
        } else {
            XCTAssertEqual(raw.awakePercent!, (Double(awakeSeconds) / Double(sleepSeconds)) * 100.0, accuracy: 0.0001)
        }
        
        // Steps: if the source distance.steps_int is nil for that day, then raw.steps is nil
        if dist?.steps_int == nil {
            XCTAssertNil(raw.steps)
        } else {
            XCTAssertEqual(raw.steps, dist?.steps_int)
        }
        
        // Active Calories: calories_net_active_kcal_float (never total)
        let activeKcal = cals!.calories_net_active_kcal_float!
        XCTAssertNotNil(raw.activeCalories)
        XCTAssertEqual(raw.activeCalories!, activeKcal, accuracy: 0.0001)
        
        // Movement Minutes: nil (not in file)
        XCTAssertNil(raw.movementMinutes)
        
        // HRV: prefer SDNN if present, else RMSSD; prefer sleep, else physical; track type
        let expectedHRV: (Double?, String?) = {
            if let sdnn = sleepHR?.hrv_avg_sdnn_float { return (sdnn, "sdnn") }
            if let rmssd = sleepHR?.hrv_avg_rmssd_float { return (rmssd, "rmssd") }
            if let sdnn = physHR?.hrv_avg_sdnn_float { return (sdnn, "sdnn") }
            if let rmssd = physHR?.hrv_avg_rmssd_float { return (rmssd, "rmssd") }
            return (nil, nil)
        }()
        XCTAssertEqual(raw.hrvType, expectedHRV.1)
        if let expectedValue = expectedHRV.0 {
            XCTAssertNotNil(raw.hrvMs)
            XCTAssertEqual(raw.hrvMs!, expectedValue, accuracy: 0.0001)
        } else {
            XCTAssertNil(raw.hrvMs)
        }
        
        // Resting HR: prefer sleep, else physical
        let expectedRHR: Double? = {
            if let hr = sleepHR?.hr_resting_bpm_int { return Double(hr) }
            if let hr = physHR?.hr_resting_bpm_int { return Double(hr) }
            return nil
        }()
        assertEqualOptionalDouble(raw.restingHeartRate, expectedRHR, accuracy: 0.0001)
        
        // Breathing Rate: breaths_avg_per_min_int
        let breaths = breathing!.breaths_avg_per_min_int!
        XCTAssertNotNil(raw.breathingRate)
        XCTAssertEqual(raw.breathingRate!, Double(breaths), accuracy: 0.0001)
    }
    
    // MARK: - Apple Health Tests
    
    func testAppleHealthDayMapping() throws {
        let dataset = try loadROOKDataset("ROOKConnect-Apple Health-dataset-v2.json")
        
        guard let dayKey = mostRecentMatchedDayKey(in: dataset) else {
            XCTFail("No matched day key found in Apple Health dataset")
            return
        }
        guard let sleepWrapper = findSleepSummary(forDayKey: dayKey, in: dataset),
              let physicalWrapper = findPhysicalSummary(forDayKey: dayKey, in: dataset) else {
            XCTFail("Could not find matched sleep+physical summaries for Apple dayKey=\(dayKey)")
            return
        }

        // Assert raw source fields exist before asserting computed values
        let sleep = sleepWrapper.sleep_health?.summary?.sleep_summary
        let physical = physicalWrapper.physical_health?.summary?.physical_summary
        let dur = sleep?.duration
        let scores = sleep?.scores
        let sleepHR = sleep?.heart_rate
        let breathing = sleep?.breathing
        let dist = physical?.distance
        let cals = physical?.calories
        let physHR = physical?.heart_rate
        
        XCTAssertNotNil(dur?.sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.rem_sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.deep_sleep_duration_seconds_int)
        XCTAssertNotNil(dur?.time_awake_during_sleep_seconds_int)
        // time_in_bed may be 0 or missing; we assert branch below.
        XCTAssertNotNil(dist?.steps_int) // Apple export contains steps on at least the chosen matched day
        XCTAssertNotNil(cals?.calories_net_active_kcal_float)
        // breathing can be nil on some days; we will only assert if present in source.
        
        let raw = ROOKDayToMiyaAdapter.mapOneDay(
            age: 45,
            sleepSummary: sleepWrapper,
            physicalSummary: physicalWrapper
        )
        
        // Verify age passed through
        XCTAssertEqual(raw.age, 45)
        
        // Sleep Duration: sleep_duration_seconds_int / 3600
        let sleepSeconds = dur!.sleep_duration_seconds_int!
        XCTAssertNotNil(raw.sleepDurationHours)
        XCTAssertEqual(raw.sleepDurationHours!, Double(sleepSeconds) / 3600.0, accuracy: 0.0001)
        
        // Restorative %: (REM + Deep) / Total * 100
        let rem = dur!.rem_sleep_duration_seconds_int!
        let deep = dur!.deep_sleep_duration_seconds_int!
        XCTAssertNotNil(raw.restorativeSleepPercent)
        XCTAssertEqual(raw.restorativeSleepPercent!, (Double(rem + deep) / Double(sleepSeconds)) * 100.0, accuracy: 0.0001)
        
        // Sleep Efficiency: score-only mapping (if missing in source, result must be nil)
        if let eff = scores?.sleep_efficiency_1_100_score_int {
            assertEqualOptionalDouble(raw.sleepEfficiencyPercent, Double(eff), accuracy: 0.0001)
        } else {
            XCTAssertNil(raw.sleepEfficiencyPercent)
        }
        
        // Awake % branch: if time_in_bed_seconds_int present and >0 use it, else use sleep_duration_seconds_int
        let awakeSeconds = dur!.time_awake_during_sleep_seconds_int!
        let timeInBed = dur!.time_in_bed_seconds_int
        XCTAssertNotNil(raw.awakePercent)
        if let tib = timeInBed, tib > 0 {
            // Explicitly assert branch taken
            XCTAssertTrue(tib > 0)
            XCTAssertEqual(raw.awakePercent!, (Double(awakeSeconds) / Double(tib)) * 100.0, accuracy: 0.0001)
        } else {
            // Explicitly assert branch taken
            XCTAssertTrue(timeInBed == nil || timeInBed == 0)
            XCTAssertEqual(raw.awakePercent!, (Double(awakeSeconds) / Double(sleepSeconds)) * 100.0, accuracy: 0.0001)
        }
        
        // Steps: distance.steps_int (optional)
        XCTAssertEqual(raw.steps, dist?.steps_int)
        
        // Active Calories: calories_net_active_kcal_float (optional)
        let activeKcal = cals!.calories_net_active_kcal_float!
        assertEqualOptionalDouble(raw.activeCalories, activeKcal, accuracy: 0.0001)
        
        // Movement Minutes: nil (not in file)
        XCTAssertNil(raw.movementMinutes)
        
        // HRV: prefer SDNN if present, else RMSSD; prefer sleep, else physical
        let expectedHRV: (Double?, String?) = {
            if let sdnn = sleepHR?.hrv_avg_sdnn_float { return (sdnn, "sdnn") }
            if let rmssd = sleepHR?.hrv_avg_rmssd_float { return (rmssd, "rmssd") }
            if let sdnn = physHR?.hrv_avg_sdnn_float { return (sdnn, "sdnn") }
            if let rmssd = physHR?.hrv_avg_rmssd_float { return (rmssd, "rmssd") }
            return (nil, nil)
        }()
        XCTAssertEqual(raw.hrvType, expectedHRV.1)
        if let expectedValue = expectedHRV.0 {
            XCTAssertNotNil(raw.hrvMs)
            XCTAssertEqual(raw.hrvMs!, expectedValue, accuracy: 0.0001)
        } else {
            XCTAssertNil(raw.hrvMs)
        }
        
        // Resting HR: prefer sleep, else physical (optional)
        let expectedRHR: Double? = {
            if let hr = sleepHR?.hr_resting_bpm_int { return Double(hr) }
            if let hr = physHR?.hr_resting_bpm_int { return Double(hr) }
            return nil
        }()
        assertEqualOptionalDouble(raw.restingHeartRate, expectedRHR, accuracy: 0.0001)
        
        // Breathing Rate: breaths_avg_per_min_int (optional)
        if let breaths = breathing?.breaths_avg_per_min_int {
            XCTAssertNotNil(raw.breathingRate)
            XCTAssertEqual(raw.breathingRate!, Double(breaths), accuracy: 0.0001)
        } else {
            XCTAssertNil(raw.breathingRate)
        }
    }
    
    // MARK: - Nil Preservation Tests
    
    func testNilSummariesProduceNilMetrics() {
        let raw = ROOKDayToMiyaAdapter.mapOneDay(
            age: 30,
            sleepSummary: nil,
            physicalSummary: nil
        )
        
        XCTAssertEqual(raw.age, 30)
        XCTAssertNil(raw.sleepDurationHours)
        XCTAssertNil(raw.restorativeSleepPercent)
        XCTAssertNil(raw.sleepEfficiencyPercent)
        XCTAssertNil(raw.awakePercent)
        XCTAssertNil(raw.movementMinutes)
        XCTAssertNil(raw.steps)
        XCTAssertNil(raw.activeCalories)
        XCTAssertNil(raw.hrvMs)
        XCTAssertNil(raw.hrvType)
        XCTAssertNil(raw.restingHeartRate)
        XCTAssertNil(raw.breathingRate)
    }
}

