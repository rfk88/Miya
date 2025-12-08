//
//  RiskResultsView.swift
//  Miya Health
//
//  Displays WHO-based risk assessment results after data collection
//

import SwiftUI
import UniformTypeIdentifiers

struct RiskResultsView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var isCalculating = true
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Vitality import state
    @State private var showingFilePicker = false
    @State private var importedVitalityScore: VitalityScore?
    @State private var isImporting = false
    
    // Expandable breakdown
    @State private var showBreakdown = false
    @State private var showOptimalInfo = false
    
    var bmi: Double {
        guard onboardingManager.heightCm > 0, onboardingManager.weightKg > 0 else { return 0 }
        let heightM = onboardingManager.heightCm / 100.0
        return onboardingManager.weightKg / (heightM * heightM)
    }
    
    var bmiCategory: String {
        switch bmi {
        case 0..<18.5: return "Underweight"
        case 18.5..<25.0: return "Normal"
        case 25.0..<30.0: return "Overweight"
        case 30.0..<35.0: return "Obese (Class I)"
        case 35.0...: return "Obese (Class II-III)"
        default: return "Unknown"
        }
    }
    
    var riskBandColor: Color {
        switch onboardingManager.riskBand {
        case "low": return .green
        case "moderate": return .yellow
        case "high": return .orange
        case "very_high": return .red
        case "critical": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.miyaPrimary)
                    
                    Text("Your Health Assessment")
                        .font(.title2.bold())
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Based on WHO cardiovascular risk guidelines")
                        .font(.subheadline)
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Risk Band Card
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Risk Band")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(getRiskBandDisplayName())
                                .font(.title.bold())
                                .foregroundColor(riskBandColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 8) {
                            Text("Risk Points")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("\(onboardingManager.riskPoints)")
                                .font(.title.bold())
                                .foregroundColor(.miyaTextPrimary)
                        }
                    }
                    
                    Divider()
                    
                    Text(getRiskBandDescription())
                        .font(.body)
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Expandable breakdown
                    DisclosureGroup(isExpanded: $showBreakdown) {
                        VStack(alignment: .leading, spacing: 12) {
                            ScoreBreakdownRow(
                                label: "Age",
                                value: "\(getAge()) years old",
                                points: RiskCalculator.agePoints(from: onboardingManager.dateOfBirth),
                                maxPoints: 20
                            )
                            
                            ScoreBreakdownRow(
                                label: "Smoking",
                                value: onboardingManager.smokingStatus.isEmpty ? "Not specified" : onboardingManager.smokingStatus,
                                points: RiskCalculator.smokingPoints(onboardingManager.smokingStatus),
                                maxPoints: 10
                            )
                            
                            ScoreBreakdownRow(
                                label: "Blood Pressure",
                                value: formatBPStatus(onboardingManager.bloodPressureStatus),
                                points: RiskCalculator.bloodPressurePoints(onboardingManager.bloodPressureStatus),
                                maxPoints: 12
                            )
                            
                            ScoreBreakdownRow(
                                label: "Diabetes",
                                value: formatDiabetesStatus(onboardingManager.diabetesStatus),
                                points: RiskCalculator.diabetesPoints(onboardingManager.diabetesStatus),
                                maxPoints: 15
                            )
                            
                            ScoreBreakdownRow(
                                label: "Prior Events",
                                value: formatPriorEvents(),
                                points: RiskCalculator.priorEventsPoints(
                                    heartAttack: onboardingManager.hasPriorHeartAttack,
                                    stroke: onboardingManager.hasPriorStroke
                                ),
                                maxPoints: 20
                            )
                            
                            ScoreBreakdownRow(
                                label: "Family History",
                                value: formatFamilyHistory(),
                                points: RiskCalculator.familyHistoryPoints(
                                    heartDiseaseEarly: onboardingManager.familyHeartDiseaseEarly,
                                    strokeEarly: onboardingManager.familyStrokeEarly,
                                    diabetes: onboardingManager.familyType2Diabetes
                                ),
                                maxPoints: 8
                            )
                            
                            ScoreBreakdownRow(
                                label: "BMI",
                                value: String(format: "%.1f (%@)", bmi, bmiCategory),
                                points: RiskCalculator.bmiPoints(
                                    heightCm: onboardingManager.heightCm,
                                    weightKg: onboardingManager.weightKg
                                ),
                                maxPoints: 10
                            )
                            
                            Divider()
                            
                            HStack {
                                Text("Total")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(onboardingManager.riskPoints) points")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.miyaPrimary)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(.miyaSecondary)
                            Text("See Score Breakdown")
                                .font(.subheadline.bold())
                                .foregroundColor(.miyaTextPrimary)
                        }
                    }
                    .tint(.miyaPrimary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // BMI Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Body Mass Index")
                        .font(.headline)
                        .foregroundColor(.miyaTextPrimary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f", bmi))
                                .font(.title.bold())
                                .foregroundColor(.miyaPrimary)
                            
                            Text(bmiCategory)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "figure.walk")
                            .font(.system(size: 40))
                            .foregroundColor(.miyaPrimary.opacity(0.3))
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Vitality Target Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.miyaPrimary)
                        Text("Your Vitality Goal")
                            .font(.headline)
                            .foregroundColor(.miyaTextPrimary)
                    }
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(onboardingManager.optimalVitalityTarget)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.miyaPrimary)
                        
                        Text("/100")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                    }
                    
                    Text("This is your personalized optimal vitality score based on your age and risk profile.")
                        .font(.subheadline)
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                DisclosureGroup(isExpanded: $showOptimalInfo) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How this was calculated:")
                            .font(.caption.bold())
                        Text(getOptimalVitalityExplanation())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.miyaSecondary)
                        Text("See how this target was set")
                            .font(.subheadline.bold())
                            .foregroundColor(.miyaTextPrimary)
                    }
                }
                .tint(.miyaPrimary)
                
                    Divider()
                    
                    if let vitality = importedVitalityScore {
                        // Show imported vitality
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current Vitality Score")
                                .font(.subheadline.bold())
                                .foregroundColor(.miyaTextPrimary)
                            
                            HStack(alignment: .bottom, spacing: 8) {
                                Text("\(vitality.totalScore)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.miyaSecondary)
                                
                                Text("/\(onboardingManager.optimalVitalityTarget)")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 6)
                            }
                            
                            // Component breakdown
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "bed.double.fill")
                                        .foregroundColor(.miyaSecondary)
                                        .frame(width: 20)
                                    Text("Sleep:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(vitality.sleepPoints)/35")
                                        .font(.caption.bold())
                                }
                                
                                HStack {
                                    Image(systemName: "figure.walk")
                                        .foregroundColor(.miyaSecondary)
                                        .frame(width: 20)
                                    Text("Movement:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(vitality.movementPoints)/35")
                                        .font(.caption.bold())
                                }
                                
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.miyaSecondary)
                                        .frame(width: 20)
                                    Text("Recovery:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(vitality.stressPoints)/30")
                                        .font(.caption.bold())
                                }
                            }
                            .padding(.top, 4)
                            
                            Text("Based on 7-day rolling average from imported data.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.top, 4)
                    } else {
                        // Import button
                        Button {
                            showingFilePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isImporting ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                                    .foregroundColor(.miyaSecondary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isImporting ? "Importing..." : "Import Health Data")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Text("Upload CSV or Apple Health XML to see your vitality score")
                                        .font(.caption)
                                        .foregroundColor(.miyaTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                                
                                if !isImporting {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(isImporting)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Next Steps
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundColor(.miyaSecondary)
                        Text("Next Steps")
                            .font(.headline)
                            .foregroundColor(.miyaTextPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        NextStepRow(icon: "person.2.fill", text: "Invite family members to join")
                        NextStepRow(icon: "bell.badge.fill", text: "Set up health champions and alerts")
                        NextStepRow(icon: "chart.line.uptrend.xyaxis", text: "Start tracking your vitality score")
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Continue button
                // Invited users skip family member invite step
                NavigationLink {
                    if onboardingManager.isInvitedUser {
                        // Invited users go directly to Alerts & Champion
                        AlertsChampionView()
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    } else {
                        // Superadmin can invite family members
                        FamilyMembersInviteView()
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.miyaPrimary)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(Color.miyaBackground.ignoresSafeArea())
        .navigationTitle("Health Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Step 6: Risk Results
            onboardingManager.setCurrentStep(6)
            calculateRisk()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func calculateRisk() {
        Task {
            do {
                // Calculate risk using RiskCalculator
                let result = RiskCalculator.calculateRisk(
                    dateOfBirth: onboardingManager.dateOfBirth,
                    smokingStatus: onboardingManager.smokingStatus,
                    bloodPressureStatus: onboardingManager.bloodPressureStatus,
                    diabetesStatus: onboardingManager.diabetesStatus,
                    hasPriorHeartAttack: onboardingManager.hasPriorHeartAttack,
                    hasPriorStroke: onboardingManager.hasPriorStroke,
                    familyHeartDiseaseEarly: onboardingManager.familyHeartDiseaseEarly,
                    familyStrokeEarly: onboardingManager.familyStrokeEarly,
                    familyType2Diabetes: onboardingManager.familyType2Diabetes,
                    heightCm: onboardingManager.heightCm,
                    weightKg: onboardingManager.weightKg
                )
                
                // Update OnboardingManager
                await MainActor.run {
                    onboardingManager.riskBand = result.band.rawValue
                    onboardingManager.riskPoints = result.points
                    onboardingManager.optimalVitalityTarget = result.optimalTarget
                    isCalculating = false
                }
                
                // Save to database
                try await dataManager.saveRiskAssessment(
                    riskBand: result.band.rawValue,
                    riskPoints: result.points,
                    optimalTarget: result.optimalTarget
                )
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to calculate risk: \(error.localizedDescription)"
                    showError = true
                    isCalculating = false
                }
            }
        }
    }
    
    private func getRiskBandDisplayName() -> String {
        switch onboardingManager.riskBand {
        case "low": return "Low Risk"
        case "moderate": return "Moderate Risk"
        case "high": return "High Risk"
        case "very_high": return "Very High Risk"
        case "critical": return "Critical Risk"
        default: return "Calculating..."
        }
    }
    
    private func getRiskBandDescription() -> String {
        switch onboardingManager.riskBand {
        case "low":
            return "Your cardiovascular risk is low. Keep up your healthy habits!"
        case "moderate":
            return "You have some risk factors to be mindful of. Small changes can make a big difference."
        case "high":
            return "Your risk level warrants attention. Consider discussing lifestyle changes with your doctor."
        case "very_high":
            return "Your risk is elevated. We recommend consulting with a healthcare provider soon."
        case "critical":
            return "Your risk level is significant. Please speak with a healthcare provider as soon as possible."
        default:
            return "Calculating your risk assessment..."
        }
    }
    
    private func getAge() -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date())
        return ageComponents.year ?? 0
    }
    
    private func formatBPStatus(_ status: String) -> String {
        switch status {
        case "normal": return "Normal"
        case "elevated_untreated": return "High, not on medication"
        case "elevated_treated": return "High, on medication"
        case "unknown": return "Not sure / Never checked"
        default: return "Not specified"
        }
    }
    
    private func formatDiabetesStatus(_ status: String) -> String {
        switch status {
        case "none": return "No diabetes"
        case "pre_diabetic": return "Pre-diabetic"
        case "type_1": return "Type 1 diabetes"
        case "type_2": return "Type 2 diabetes"
        case "unknown": return "Not sure"
        default: return "Not specified"
        }
    }
    
    private func formatPriorEvents() -> String {
        var events: [String] = []
        if onboardingManager.hasPriorHeartAttack { events.append("Heart attack") }
        if onboardingManager.hasPriorStroke { events.append("Stroke") }
        return events.isEmpty ? "None" : events.joined(separator: ", ")
    }
    
    private func formatFamilyHistory() -> String {
        var history: [String] = []
        if onboardingManager.familyHeartDiseaseEarly { history.append("Heart disease <60") }
        if onboardingManager.familyStrokeEarly { history.append("Stroke <60") }
        if onboardingManager.familyType2Diabetes { history.append("Type 2 diabetes") }
        return history.isEmpty ? "None reported" : history.joined(separator: ", ")
    }
    
    private func getOptimalVitalityExplanation() -> String {
        let age = getAge()
        let band = onboardingManager.riskBand.isEmpty ? "not set" : onboardingManager.riskBand.replacingOccurrences(of: "_", with: " ")
        let target = onboardingManager.optimalVitalityTarget
        
        let ageGroup: String
        switch age {
        case 0...34: ageGroup = "18-34"
        case 35...44: ageGroup = "35-44"
        case 45...54: ageGroup = "45-54"
        case 55...64: ageGroup = "55-64"
        default: ageGroup = "65+"
        }
        
        return "We use your age group (\(ageGroup)) and risk band (\(band)) to set a realistic target. Higher risk or older age lowers the target slightly to keep goals safe and achievable. Your optimal vitality target is \(target)/100."
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        isImporting = true
        
        Task {
            do {
                guard let url = try result.get().first else { return }
                
                // Access the file
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run {
                        errorMessage = "Cannot access file"
                        showError = true
                        isImporting = false
                    }
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                // Read file content
                let content = try String(contentsOf: url, encoding: .utf8)
                
                // Determine file type and parse
                let vitalityData: [VitalityData]
                if url.pathExtension.lowercased() == "xml" {
                    // Parse XML
                    vitalityData = VitalityCalculator.parseAppleHealthXML(content: content)
                } else {
                    // Parse CSV
                    vitalityData = VitalityCalculator.parseCSV(content: content)
                }
                
                guard !vitalityData.isEmpty else {
                    await MainActor.run {
                        errorMessage = "No valid data found in file"
                        showError = true
                        isImporting = false
                    }
                    return
                }
                
                // Calculate 7-day rolling average
                guard let vitalityScore = VitalityCalculator.calculate7DayAverage(from: vitalityData) else {
                    await MainActor.run {
                        errorMessage = "Need at least 7 days of data to calculate vitality score"
                        showError = true
                        isImporting = false
                    }
                    return
                }
                
                // Save to Supabase - convert to rolling scores first
                let rollingScores = VitalityCalculator.computeRollingScores(from: vitalityData)
                let tuples = rollingScores.map { score in
                    (date: score.date, total: score.totalScore, sleep: score.sleepPoints, movement: score.movementPoints, stress: score.stressPoints, source: "csv")
                }
                if !tuples.isEmpty {
                    try await dataManager.saveVitalityScores(tuples)
                }
                
                // Update UI
                await MainActor.run {
                    importedVitalityScore = vitalityScore
                    isImporting = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to import: \(error.localizedDescription)"
                    showError = true
                    isImporting = false
                }
            }
        }
    }
}

struct NextStepRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.miyaPrimary)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.miyaTextSecondary)
        }
    }
}

struct ScoreBreakdownRow: View {
    let label: String
    let value: String
    let points: Int
    let maxPoints: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Text("+\(points) pts")
                    .font(.caption.bold())
                    .foregroundColor(points > 0 ? .orange : .green)
            }
            
            HStack {
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                // Progress indicator
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(points > 0 ? Color.orange : Color.green)
                            .frame(width: geo.size.width * CGFloat(points) / CGFloat(maxPoints), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(width: 60, height: 4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        RiskResultsView()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

