//
//  VitalityCalculator.swift
//  Miya Health
//
//  Calculates Vitality Score from wearable data (sleep, movement, stress)
//

import Foundation

struct VitalityData {
    let date: Date
    let sleepHours: Double?
    let restorativeSleepPercent: Double?      // (REM + Deep) / Total × 100
    let sleepEfficiencyPercent: Double?       // Sleep Duration / Time in Bed × 100
    let awakePercent: Double?                 // Awake Time / Time in Bed × 100
    let steps: Int?
    let hrvMs: Double?
    let restingHr: Double?
}

struct VitalityScore {
    let date: Date
    let totalScore: Int
    let sleepPoints: Int
    let movementPoints: Int
    let stressPoints: Int
}

class VitalityCalculator {
    
    // MARK: - Component Scoring (per methodology)
    
    /// Sleep Component (0-35 points)
    /// 7-9h = 35, 6-7 or 9-10 = 25, 5-6 or 10-11 = 15, <5 or >11 = 5
    static func sleepPoints(hours: Double) -> Int {
        switch hours {
        case 7.0...9.0:
            return 35
        case 6.0..<7.0, 9.0..<10.0:
            return 25
        case 5.0..<6.0, 10.0..<11.0:
            return 15
        default:
            return 5
        }
    }
    
    /// Movement Component (0-35 points)
    /// 10k+ = 35, 7.5-10k = 25, 5-7.5k = 15, <5k = 5
    static func movementPoints(steps: Int) -> Int {
        switch steps {
        case 10000...:
            return 35
        case 7500..<10000:
            return 25
        case 5000..<7500:
            return 15
        default:
            return 5
        }
    }
    
    /// Stress Component - HRV-based (0-30 points)
    /// High HRV (>65) = 30, Moderate (50-65) = 20, Low (<50) = 10
    static func stressPointsFromHRV(hrv: Double) -> Int {
        if hrv >= 65 {
            return 30
        } else if hrv >= 50 {
            return 20
        } else {
            return 10
        }
    }
    
    /// Stress Component - Resting HR fallback (0-30 points)
    /// 50-60 = 30, 61-70 = 25, 71-80 = 20, 81-90 = 15, >90 = 10
    static func stressPointsFromRestingHR(hr: Double) -> Int {
        switch hr {
        case 50...60:
            return 30
        case 61...70:
            return 25
        case 71...80:
            return 20
        case 81...90:
            return 15
        default:
            return 10
        }
    }
    
    // MARK: - Daily Score Calculation
    
    static func calculateDailyScore(data: VitalityData) -> VitalityScore? {
        var sleep = 0
        var movement = 0
        var stress = 0
        
        // Sleep
        if let hours = data.sleepHours {
            sleep = sleepPoints(hours: hours)
        }
        
        // Movement
        if let steps = data.steps {
            movement = movementPoints(steps: steps)
        }
        
        // Stress (prefer HRV, fallback to resting HR)
        if let hrv = data.hrvMs {
            stress = stressPointsFromHRV(hrv: hrv)
        } else if let hr = data.restingHr {
            stress = stressPointsFromRestingHR(hr: hr)
        }
        
        let total = min(sleep + movement + stress, 100)
        
        return VitalityScore(
            date: data.date,
            totalScore: total,
            sleepPoints: sleep,
            movementPoints: movement,
            stressPoints: stress
        )
    }
    
    // MARK: - 7-Day Rolling Average
    
    static func calculate7DayAverage(from data: [VitalityData]) -> VitalityScore? {
        guard data.count >= 7 else { return nil }
        
        // Take last 7 days
        let last7 = Array(data.suffix(7))
        
        // Calculate averages
        let avgSleep = last7.compactMap { $0.sleepHours }.reduce(0, +) / Double(max(last7.compactMap { $0.sleepHours }.count, 1))
        let avgSteps = last7.compactMap { $0.steps }.reduce(0, +) / max(last7.compactMap { $0.steps }.count, 1)
        
        var avgHrv: Double? = nil
        let hrvValues = last7.compactMap { $0.hrvMs }
        if !hrvValues.isEmpty {
            avgHrv = hrvValues.reduce(0, +) / Double(hrvValues.count)
        }
        
        var avgHr: Double? = nil
        let hrValues = last7.compactMap { $0.restingHr }
        if !hrValues.isEmpty {
            avgHr = hrValues.reduce(0, +) / Double(hrValues.count)
        }
        
        // Calculate points from averages
        let sleep = sleepPoints(hours: avgSleep)
        let movement = movementPoints(steps: avgSteps)
        let stress: Int
        if let hrv = avgHrv {
            stress = stressPointsFromHRV(hrv: hrv)
        } else if let hr = avgHr {
            stress = stressPointsFromRestingHR(hr: hr)
        } else {
            stress = 0
        }
        
        let total = min(sleep + movement + stress, 100)
        
        return VitalityScore(
            date: last7.last!.date,
            totalScore: total,
            sleepPoints: sleep,
            movementPoints: movement,
            stressPoints: stress
        )
    }
    
    // MARK: - CSV Import
    
    static func parseCSV(content: String) -> [VitalityData] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var results: [VitalityData] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Skip header
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 5 else { continue }
            
            guard let date = dateFormatter.date(from: parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let sleepStr = parts[1].trimmingCharacters(in: .whitespaces)
            let stepsStr = parts[2].trimmingCharacters(in: .whitespaces)
            let hrvStr = parts[3].trimmingCharacters(in: .whitespaces)
            let hrStr = parts[4].trimmingCharacters(in: .whitespaces)
            
            let data = VitalityData(
                date: date,
                sleepHours: sleepStr.isEmpty ? nil : Double(sleepStr),
                restorativeSleepPercent: nil,  // CSV doesn't contain this
                sleepEfficiencyPercent: nil,   // CSV doesn't contain this
                awakePercent: nil,             // CSV doesn't contain this
                steps: stepsStr.isEmpty ? nil : Int(stepsStr),
                hrvMs: hrvStr.isEmpty ? nil : Double(hrvStr),
                restingHr: hrStr.isEmpty ? nil : Double(hrStr)
            )
            
            results.append(data)
        }
        
        return results
    }
    
    /// Compute rolling vitality scores (default 7-day window) for all dates
    /// Returns one score per day once the window is available (sorted by date ascending)
    static func computeRollingScores(from data: [VitalityData], window: Int = 7) -> [VitalityScore] {
        guard data.count >= window else { return [] }
        
        let sorted = data.sorted { $0.date < $1.date }
        var scores: [VitalityScore] = []
        
        for idx in (window - 1)..<sorted.count {
            let slice = Array(sorted[(idx - window + 1)...idx])
            
            let avgSleep = slice.compactMap { $0.sleepHours }.reduce(0, +) / Double(max(slice.compactMap { $0.sleepHours }.count, 1))
            let avgSteps = slice.compactMap { $0.steps }.reduce(0, +) / max(slice.compactMap { $0.steps }.count, 1)
            
            var avgHrv: Double? = nil
            let hrvValues = slice.compactMap { $0.hrvMs }
            if !hrvValues.isEmpty {
                avgHrv = hrvValues.reduce(0, +) / Double(hrvValues.count)
            }
            
            var avgHr: Double? = nil
            let hrValues = slice.compactMap { $0.restingHr }
            if !hrValues.isEmpty {
                avgHr = hrValues.reduce(0, +) / Double(hrValues.count)
            }
            
            let sleep = sleepPoints(hours: avgSleep)
            let movement = movementPoints(steps: avgSteps)
            let stress: Int
            if let hrv = avgHrv {
                stress = stressPointsFromHRV(hrv: hrv)
            } else if let hr = avgHr {
                stress = stressPointsFromRestingHR(hr: hr)
            } else {
                stress = 0
            }
            
            let total = min(sleep + movement + stress, 100)
            
            let score = VitalityScore(
                date: slice.last!.date,
                totalScore: total,
                sleepPoints: sleep,
                movementPoints: movement,
                stressPoints: stress
            )
            scores.append(score)
        }
        
        return scores
    }
    
    // MARK: - Apple Health XML Import
    
    static func parseAppleHealthXML(content: String) -> [VitalityData] {
        var dailyData: [String: (sleep: Double, steps: Int, hrv: [Double], rhr: [Double])] = [:]
        
        // Apple Health uses format like "2024-01-15 08:30:00 -0500"
        let appleHealthDateFormatter = DateFormatter()
        appleHealthDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        
        // Parse XML - look for Record elements
        // Apple Health XML format: <Record type="..." startDate="2024-01-15 08:30:00 -0500" value="123"/>
        
        let lines = content.components(separatedBy: .newlines)
        var recordCount = 0
        
        for line in lines {
            // Must be a Record line
            guard line.contains("<Record") || line.contains("type=") else { continue }
            
            // Sleep analysis - multiple possible values for "asleep"
            if line.contains("SleepAnalysis") && 
               (line.contains("Asleep") || line.contains("InBed") || line.contains("asleep")) {
                if let startStr = extractAttribute(from: line, attribute: "startDate"),
                   let endStr = extractAttribute(from: line, attribute: "endDate"),
                   let start = appleHealthDateFormatter.date(from: startStr),
                   let end = appleHealthDateFormatter.date(from: endStr) {
                    let dayKey = dayFormatter.string(from: start)
                    let hours = end.timeIntervalSince(start) / 3600.0
                    if hours > 0 && hours < 24 { // Sanity check
                        dailyData[dayKey, default: (0, 0, [], [])].sleep += hours
                        recordCount += 1
                    }
                }
            }
            
            // Steps
            if line.contains("StepCount") {
                if let startStr = extractAttribute(from: line, attribute: "startDate"),
                   let value = extractAttribute(from: line, attribute: "value"),
                   let date = appleHealthDateFormatter.date(from: startStr),
                   let stepsValue: Int = {
                       if let i = Int(value) {
                           return i
                       } else if let d = Double(value) {
                           return Int(d)
                       } else {
                           return nil
                       }
                   }() {
                    let dayKey = dayFormatter.string(from: date)
                    dailyData[dayKey, default: (0, 0, [], [])].steps += stepsValue
                    recordCount += 1
                }
            }
            
            // HRV
            if line.contains("HeartRateVariabilitySDNN") {
                if let startStr = extractAttribute(from: line, attribute: "startDate"),
                   let value = extractAttribute(from: line, attribute: "value"),
                   let date = appleHealthDateFormatter.date(from: startStr),
                   let hrv = Double(value) {
                    let dayKey = dayFormatter.string(from: date)
                    dailyData[dayKey, default: (0, 0, [], [])].hrv.append(hrv)
                    recordCount += 1
                }
            }
            
            // Resting HR
            if line.contains("RestingHeartRate") {
                if let startStr = extractAttribute(from: line, attribute: "startDate"),
                   let value = extractAttribute(from: line, attribute: "value"),
                   let date = appleHealthDateFormatter.date(from: startStr),
                   let rhr = Double(value) {
                    let dayKey = dayFormatter.string(from: date)
                    dailyData[dayKey, default: (0, 0, [], [])].rhr.append(rhr)
                    recordCount += 1
                }
            }
        }
        
        print("📊 VitalityCalculator: Parsed \(recordCount) records into \(dailyData.count) days")
        
        // Convert to VitalityData array
        var results: [VitalityData] = []
        for (dateStr, data) in dailyData.sorted(by: { $0.key < $1.key }) {
            guard let date = dayFormatter.date(from: dateStr) else { continue }
            
            let avgHrv = data.hrv.isEmpty ? nil : data.hrv.reduce(0, +) / Double(data.hrv.count)
            let avgRhr = data.rhr.isEmpty ? nil : data.rhr.reduce(0, +) / Double(data.rhr.count)
            
            // Only add if we have at least steps or sleep data
            if data.steps > 0 || data.sleep > 0 {
                results.append(VitalityData(
                    date: date,
                    sleepHours: data.sleep > 0 ? data.sleep : nil,
                    restorativeSleepPercent: nil,  // Apple Health XML doesn't contain sleep stages
                    sleepEfficiencyPercent: nil,   // Apple Health XML doesn't contain this
                    awakePercent: nil,             // Apple Health XML doesn't contain this
                    steps: data.steps > 0 ? data.steps : nil,
                    hrvMs: avgHrv,
                    restingHr: avgRhr
                ))
            }
        }
        
        print("📊 VitalityCalculator: Returning \(results.count) days of vitality data")
        return results
    }
    
    private static func extractAttribute(from line: String, attribute: String) -> String? {
        guard let range = line.range(of: "\(attribute)=\"") else { return nil }
        let start = range.upperBound
        guard let endRange = line[start...].range(of: "\"") else { return nil }
        return String(line[start..<endRange.lowerBound])
    }
}
