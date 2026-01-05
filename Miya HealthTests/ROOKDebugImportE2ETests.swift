//
//  ROOKDebugImportE2ETests.swift
//  Miya HealthTests
//
//  End-to-end verification of ROOK export decode → window aggregation → vitality scoring.
//  Uses the same core code as the RiskResultsView DEBUG import, but runs headlessly in tests.
//

import XCTest
@testable import Miya_Health

final class ROOKDebugImportE2ETests: XCTestCase {
    
    private struct WindowInfo {
        let matchedDays: Int
        let selectedWindowSize: Int
        let firstDayKey: String?
        let lastDayKey: String?
    }
    
    private func computeWindowInfo(dataset: ROOKDataset, windowMaxDays: Int = 30, windowMinDays: Int = 7) -> WindowInfo {
        func formatUTCYYYYMMDD(_ date: Date) -> String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: date)
        }
        
        func normalizeUTCYYYYMMDD(from raw: String) -> String? {
            if raw.count >= 10 {
                let prefix10 = String(raw.prefix(10))
                if prefix10.count == 10, prefix10.split(separator: "-").count == 3 {
                    let df = DateFormatter()
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(secondsFromGMT: 0)
                    df.dateFormat = "yyyy-MM-dd"
                    if df.date(from: prefix10) != nil {
                        return prefix10
                    }
                }
            }
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            if let d = iso.date(from: raw) {
                return formatUTCYYYYMMDD(d)
            }
            
            let isoNoFrac = ISO8601DateFormatter()
            isoNoFrac.formatOptions = [.withInternetDateTime]
            isoNoFrac.timeZone = TimeZone(secondsFromGMT: 0)
            if let d = isoNoFrac.date(from: raw) {
                return formatUTCYYYYMMDD(d)
            }
            
            let normalized = raw.replacingOccurrences(of: " ", with: "T")
            if let d = iso.date(from: normalized) ?? isoNoFrac.date(from: normalized) {
                return formatUTCYYYYMMDD(d)
            }
            
            return nil
        }
        
        let sleepKeys: [String] = (dataset.sleep_health?.sleep_summaries ?? []).compactMap { item in
            guard let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string else { return nil }
            return normalizeUTCYYYYMMDD(from: raw)
        }
        
        let physicalKeys: [String] = (dataset.physical_health?.physical_summaries ?? []).compactMap { item in
            guard let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string else { return nil }
            return normalizeUTCYYYYMMDD(from: raw)
        }
        
        let allKeys = Set(sleepKeys).union(Set(physicalKeys))
        let sortedKeys = allKeys.sorted()
        
        let windowKeys: [String] = {
            if sortedKeys.count >= windowMaxDays {
                return Array(sortedKeys.suffix(windowMaxDays))
            }
            return sortedKeys
        }()
        
        if sortedKeys.count < windowMinDays {
            print("ROOKDebugImportE2E: only \(sortedKeys.count) days available (<\(windowMinDays)); using all available days")
        }
        
        return WindowInfo(
            matchedDays: sortedKeys.count,
            selectedWindowSize: windowKeys.count,
            firstDayKey: windowKeys.first,
            lastDayKey: windowKeys.last
        )
    }
    
    private func report(fileName: String, age: Int, raw: VitalityRawMetrics, snapshot: VitalitySnapshot, windowInfo: WindowInfo) {
        let fields: [(String, Bool)] = [
            ("sleepDurationHours", raw.sleepDurationHours != nil),
            ("restorativeSleepPercent", raw.restorativeSleepPercent != nil),
            ("sleepEfficiencyPercent", raw.sleepEfficiencyPercent != nil),
            ("awakePercent", raw.awakePercent != nil),
            ("movementMinutes", raw.movementMinutes != nil),
            ("steps", raw.steps != nil),
            ("activeCalories", raw.activeCalories != nil),
            ("hrvMs", raw.hrvMs != nil),
            ("restingHeartRate", raw.restingHeartRate != nil),
            ("breathingRate", raw.breathingRate != nil)
        ]
        
        print("=== ROOK Debug Import E2E ===")
        print("File:", fileName)
        print("Age:", age)
        print("rookWindowRaw non-nil:", true)
        print("rookSnapshot non-nil:", true)
        print("Vitality snapshot total:", snapshot.totalScore, "/100")
        print("Raw metrics (non-nil vs nil):")
        for (label, present) in fields {
            print(" -", label, "=>", present ? "non-nil" : "nil")
        }
        print("Window diagnostics:")
        print("Matched days:", windowInfo.matchedDays)
        print("Selected window size:", windowInfo.selectedWindowSize)
        print("First day key:", windowInfo.firstDayKey ?? "nil")
        print("Last day key:", windowInfo.lastDayKey ?? "nil")
        print("=== End ROOK Debug Import E2E ===")
    }
    
    private func loadSampleURL(_ filename: String) -> URL {
        // Derive repo root from this test file location:
        // .../Miya HealthTests/ROOKDebugImportE2ETests.swift -> repo root is one directory up.
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Rook Samples").appendingPathComponent(filename)
    }
    
    func testWhoopROOKExportV2_DecodeAggregateScore_NoEmptyWindow() throws {
        let url = loadSampleURL("ROOKConnect-Whoop-dataset-v2.json")
        let data = try Data(contentsOf: url)
        let dataset = try JSONDecoder().decode(ROOKDataset.self, from: data)
        
        let age = 30
        let raw = ROOKWindowAggregator.buildWindowRawMetrics(age: age, dataset: dataset)
        let snapshot = VitalityScoringEngine().score(raw: raw)
        let info = computeWindowInfo(dataset: dataset)
        
        report(fileName: url.lastPathComponent, age: age, raw: raw, snapshot: snapshot, windowInfo: info)
        
        XCTAssertGreaterThan(info.matchedDays, 0, "Expected at least one matched day key")
        // "No crash or empty window": treat "empty" as having zero day keys.
        XCTAssertGreaterThan(info.selectedWindowSize, 0, "Expected a non-empty selected window")
    }
    
    func testAppleHealthROOKExportV2_DecodeAggregateScore_NoEmptyWindow() throws {
        let url = loadSampleURL("ROOKConnect-Apple Health-dataset-v2.json")
        let data = try Data(contentsOf: url)
        let dataset = try JSONDecoder().decode(ROOKDataset.self, from: data)
        
        let age = 30
        let raw = ROOKWindowAggregator.buildWindowRawMetrics(age: age, dataset: dataset)
        let snapshot = VitalityScoringEngine().score(raw: raw)
        let info = computeWindowInfo(dataset: dataset)
        
        report(fileName: url.lastPathComponent, age: age, raw: raw, snapshot: snapshot, windowInfo: info)
        
        XCTAssertGreaterThan(info.matchedDays, 0, "Expected at least one matched day key")
        XCTAssertGreaterThan(info.selectedWindowSize, 0, "Expected a non-empty selected window")
    }
}


