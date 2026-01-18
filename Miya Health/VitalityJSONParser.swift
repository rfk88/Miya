//
//  VitalityJSONParser.swift
//  Miya Health
//
//  Parser for Miya JSON test format for vitality data
//

import Foundation

/// Simple JSON parser for vitality test data
struct VitalityJSONParser {
    
    /// Parse JSON content into VitalityData array
    /// Expected format:
    /// ```json
    /// [
    ///   {
    ///     "date": "2025-01-01",
    ///     "sleep_hours": 6.5,
    ///     "steps": 8500,
    ///     "hrv_ms": 52.0,
    ///     "resting_hr": 63
    ///   }
    /// ]
    /// ```
    static func parse(content: String) -> [VitalityData] {
        guard let jsonData = content.data(using: .utf8) else {
            print("❌ VitalityJSONParser: Failed to convert string to data")
            return []
        }
        
        do {
            // Decode as array of dictionaries
            let decoder = JSONDecoder()
            let records = try decoder.decode([VitalityRecord].self, from: jsonData)
            
            // Convert to VitalityData
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            var results: [VitalityData] = []
            for record in records {
                guard let date = dateFormatter.date(from: record.date) else {
                    print("⚠️ VitalityJSONParser: Invalid date format '\(record.date)', skipping")
                    continue
                }
                
                results.append(VitalityData(
                    date: date,
                    sleepHours: record.sleep_hours,
                    restorativeSleepPercent: record.restorative_sleep_percent,
                    sleepEfficiencyPercent: record.sleep_efficiency_percent,
                    awakePercent: record.awake_percent,
                    steps: record.steps,
                    hrvMs: record.hrv_ms,
                    restingHr: record.resting_hr.map { Double($0) }
                ))
            }
            
            print("✅ VitalityJSONParser: Parsed \(results.count) records from JSON")
            return results
            
        } catch {
            print("❌ VitalityJSONParser: Failed to parse JSON: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Codable Model

private struct VitalityRecord: Codable {
    let date: String
    let sleep_hours: Double?
    let restorative_sleep_percent: Double?
    let sleep_efficiency_percent: Double?
    let awake_percent: Double?
    let steps: Int?
    let hrv_ms: Double?
    let resting_hr: Int?
}

