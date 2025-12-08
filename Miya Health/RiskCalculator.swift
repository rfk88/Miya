//
//  RiskCalculator.swift
//  Miya Health
//
//  WHO-Based Risk Band Calculator
//  Calculates cardiovascular risk based on WHO guidelines
//

import Foundation

/// WHO-Based Risk Calculator
/// Calculates risk points based on modifiable and non-modifiable risk factors
struct RiskCalculator {
    
    // MARK: - Risk Band Thresholds
    
    /// Risk bands based on total points
    enum RiskBand: String {
        case low = "low"                // 0-14 points
        case moderate = "moderate"      // 15-29 points
        case high = "high"              // 30-44 points
        case veryHigh = "very_high"     // 45-59 points
        case critical = "critical"      // 60+ points
        
        var displayName: String {
            switch self {
            case .low: return "Low Risk"
            case .moderate: return "Moderate Risk"
            case .high: return "High Risk"
            case .veryHigh: return "Very High Risk"
            case .critical: return "Critical Risk"
            }
        }
        
        var description: String {
            switch self {
            case .low:
                return "Your cardiovascular risk is low. Keep up your healthy habits!"
            case .moderate:
                return "You have some risk factors to be mindful of. Small changes can make a big difference."
            case .high:
                return "Your risk level warrants attention. Consider discussing lifestyle changes with your doctor."
            case .veryHigh:
                return "Your risk is elevated. We recommend consulting with a healthcare provider soon."
            case .critical:
                return "Your risk level is significant. Please speak with a healthcare provider as soon as possible."
            }
        }
    }
    
    // MARK: - Age Points (0-20)
    
    /// Calculate points based on age
    /// - Parameter dateOfBirth: User's date of birth
    /// - Returns: Risk points (0-20)
    static func agePoints(from dateOfBirth: Date) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: now)
        let age = ageComponents.year ?? 0
        
        switch age {
        case 0..<30: return 0
        case 30..<40: return 2
        case 40..<50: return 5
        case 50..<60: return 10
        case 60..<70: return 15
        default: return 20  // 70+
        }
    }
    
    // MARK: - Smoking Points (0-10)
    
    /// Calculate points based on smoking status
    /// - Parameter status: Never, Former, or Current
    /// - Returns: Risk points (0-10)
    static func smokingPoints(_ status: String) -> Int {
        switch status {
        case "Never": return 0
        case "Former": return 3
        case "Current": return 10
        default: return 0
        }
    }
    
    // MARK: - Blood Pressure Points (0-12)
    
    /// Calculate points based on blood pressure status
    /// - Parameter status: normal, elevated_untreated, elevated_treated, unknown
    /// - Returns: Risk points (0-12)
    static func bloodPressurePoints(_ status: String) -> Int {
        switch status {
        case "normal": return 0
        case "elevated_treated": return 6      // Treated = somewhat controlled
        case "elevated_untreated": return 12   // Untreated = highest risk
        case "unknown": return 3               // Unknown = small risk assigned
        default: return 0
        }
    }
    
    // MARK: - Diabetes Points (0-15)
    
    /// Calculate points based on diabetes status
    /// - Parameter status: none, pre_diabetic, type_1, type_2, unknown
    /// - Returns: Risk points (0-15)
    static func diabetesPoints(_ status: String) -> Int {
        switch status {
        case "none": return 0
        case "pre_diabetic": return 5
        case "type_2": return 10
        case "type_1": return 15               // Type 1 = highest cardiovascular risk
        case "unknown": return 2               // Unknown = small risk assigned
        default: return 0
        }
    }
    
    // MARK: - Prior Events Points (0-20)
    
    /// Calculate points based on prior cardiovascular events
    /// - Parameters:
    ///   - heartAttack: Has had a heart attack
    ///   - stroke: Has had a stroke
    /// - Returns: Risk points (0-20)
    static func priorEventsPoints(heartAttack: Bool, stroke: Bool) -> Int {
        var points = 0
        if heartAttack { points += 10 }
        if stroke { points += 10 }
        return points
    }
    
    // MARK: - Family History Points (0-8, capped)
    
    /// Calculate points based on family history
    /// - Parameters:
    ///   - heartDiseaseEarly: Family heart disease before age 60
    ///   - strokeEarly: Family stroke before age 60
    ///   - diabetes: Family Type 2 diabetes
    /// - Returns: Risk points (0-8, capped)
    static func familyHistoryPoints(heartDiseaseEarly: Bool, strokeEarly: Bool, diabetes: Bool) -> Int {
        var points = 0
        if heartDiseaseEarly { points += 4 }
        if strokeEarly { points += 3 }
        if diabetes { points += 2 }
        return min(points, 8)  // Cap at 8 points
    }
    
    // MARK: - BMI Points (0-10)
    
    /// Calculate points based on BMI
    /// - Parameters:
    ///   - heightCm: Height in centimeters
    ///   - weightKg: Weight in kilograms
    /// - Returns: Risk points (0-10)
    static func bmiPoints(heightCm: Double, weightKg: Double) -> Int {
        guard heightCm > 0 && weightKg > 0 else { return 0 }
        
        let heightM = heightCm / 100.0
        let bmi = weightKg / (heightM * heightM)
        
        switch bmi {
        case 0..<18.5: return 2      // Underweight - slight risk
        case 18.5..<25: return 0     // Normal
        case 25..<30: return 3       // Overweight
        case 30..<35: return 6       // Obese Class I
        case 35..<40: return 8       // Obese Class II
        default: return 10           // Obese Class III (40+)
        }
    }
    
    // MARK: - Main Calculation
    
    /// Calculate total risk score and determine risk band
    /// - Parameters:
    ///   - dateOfBirth: User's date of birth
    ///   - smokingStatus: Never, Former, Current
    ///   - bloodPressureStatus: normal, elevated_untreated, elevated_treated, unknown
    ///   - diabetesStatus: none, pre_diabetic, type_1, type_2, unknown
    ///   - hasPriorHeartAttack: Has had a heart attack
    ///   - hasPriorStroke: Has had a stroke
    ///   - familyHeartDiseaseEarly: Family heart disease before 60
    ///   - familyStrokeEarly: Family stroke before 60
    ///   - familyType2Diabetes: Family Type 2 diabetes
    ///   - heightCm: Height in centimeters
    ///   - weightKg: Weight in kilograms
    /// - Returns: Tuple of (total points, risk band, optimal vitality target)
    static func calculateRisk(
        dateOfBirth: Date,
        smokingStatus: String,
        bloodPressureStatus: String,
        diabetesStatus: String,
        hasPriorHeartAttack: Bool,
        hasPriorStroke: Bool,
        familyHeartDiseaseEarly: Bool,
        familyStrokeEarly: Bool,
        familyType2Diabetes: Bool,
        heightCm: Double,
        weightKg: Double
    ) -> (points: Int, band: RiskBand, optimalTarget: Int) {
        
        // Calculate individual component points
        let age = agePoints(from: dateOfBirth)
        let smoking = smokingPoints(smokingStatus)
        let bp = bloodPressurePoints(bloodPressureStatus)
        let diabetes = diabetesPoints(diabetesStatus)
        let priorEvents = priorEventsPoints(heartAttack: hasPriorHeartAttack, stroke: hasPriorStroke)
        let family = familyHistoryPoints(heartDiseaseEarly: familyHeartDiseaseEarly, strokeEarly: familyStrokeEarly, diabetes: familyType2Diabetes)
        let bmi = bmiPoints(heightCm: heightCm, weightKg: weightKg)
        
        let totalPoints = age + smoking + bp + diabetes + priorEvents + family + bmi
        
        // Determine risk band
        let band: RiskBand
        switch totalPoints {
        case 0..<15: band = .low
        case 15..<30: band = .moderate
        case 30..<45: band = .high
        case 45..<60: band = .veryHigh
        default: band = .critical
        }
        
        // Calculate optimal vitality target based on age and risk band
        let optimalTarget = calculateOptimalTarget(dateOfBirth: dateOfBirth, riskBand: band)
        
        print("📊 RiskCalculator: Points breakdown")
        print("   Age: \(age), Smoking: \(smoking), BP: \(bp), Diabetes: \(diabetes)")
        print("   Prior Events: \(priorEvents), Family: \(family), BMI: \(bmi)")
        print("   Total: \(totalPoints) -> \(band.rawValue)")
        
        return (totalPoints, band, optimalTarget)
    }
    
    // MARK: - Optimal Vitality Target
    
    /// Calculate optimal vitality target based on age group and risk band
    /// - Parameters:
    ///   - dateOfBirth: User's date of birth
    ///   - riskBand: Calculated risk band
    /// - Returns: Optimal vitality target score (0-100)
    static func calculateOptimalTarget(dateOfBirth: Date, riskBand: RiskBand) -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        let age = ageComponents.year ?? 50
        
        // Age group determines base target
        let ageGroup: String
        switch age {
        case 0..<40: ageGroup = "young"
        case 40..<60: ageGroup = "middle"
        case 60..<75: ageGroup = "senior"
        default: ageGroup = "elderly"
        }
        
        // Target matrix: higher risk = lower baseline target (more achievable goals)
        // But we still want to push toward improvement
        let targetMatrix: [String: [RiskBand: Int]] = [
            "young": [
                .low: 85,
                .moderate: 80,
                .high: 75,
                .veryHigh: 70,
                .critical: 65
            ],
            "middle": [
                .low: 80,
                .moderate: 75,
                .high: 70,
                .veryHigh: 65,
                .critical: 60
            ],
            "senior": [
                .low: 75,
                .moderate: 70,
                .high: 65,
                .veryHigh: 60,
                .critical: 55
            ],
            "elderly": [
                .low: 70,
                .moderate: 65,
                .high: 60,
                .veryHigh: 55,
                .critical: 50
            ]
        ]
        
        return targetMatrix[ageGroup]?[riskBand] ?? 70
    }
}


