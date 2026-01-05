//
//  GuidedHealthDataEditView.swift
//  Miya Health
//
//  BUG 5 FIX: Edit view for guided health data (prefilled from admin-provided data)
//

import SwiftUI

struct GuidedHealthDataEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    let memberId: String
    let initialData: GuidedHealthData
    let onSave: () -> Void
    
    // Prefilled state (Step 1: About You)
    @State private var selectedGender: Gender?
    @State private var dateOfBirth: Date = Date()
    @State private var heightCm: String = ""
    @State private var weightKg: String = ""
    @State private var selectedEthnicity: Ethnicity?
    @State private var smokingStatus: SmokingStatus?
    
    // Step 2: Heart Health
    @State private var bloodPressureStatus: String = "normal"
    @State private var diabetesStatus: String = "none"
    @State private var hasPriorHeartAttack: Bool = false
    @State private var hasPriorStroke: Bool = false
    @State private var hasChronicKidneyDisease: Bool = false
    @State private var hasAtrialFibrillation: Bool = false
    @State private var hasHighCholesterol: Bool = false
    
    // Step 3: Family History
    @State private var familyHeartDiseaseEarly: Bool = false
    @State private var familyStrokeEarly: Bool = false
    @State private var familyType2Diabetes: Bool = false
    
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Edit Your Health Information")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                        .padding(.top, 16)
                    
                    // About You Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About You")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        // Gender
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gender")
                                .font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 12) {
                                ForEach(Gender.allCases) { gender in
                                    Button {
                                        selectedGender = gender
                                    } label: {
                                        Text(gender.rawValue)
                                            .font(.system(size: 14, weight: .medium))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(selectedGender == gender ? Color.miyaPrimary : Color.white)
                                            .foregroundColor(selectedGender == gender ? .white : .miyaTextPrimary)
                                            .cornerRadius(20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Date of Birth
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date of Birth")
                                .font(.system(size: 14, weight: .semibold))
                            DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                        
                        // Height
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Height (cm)")
                                .font(.system(size: 14, weight: .semibold))
                            TextField("170", text: $heightCm)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(MiyaTextFieldStyle())
                        }
                        
                        // Weight
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight (kg)")
                                .font(.system(size: 14, weight: .semibold))
                            TextField("70", text: $weightKg)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(MiyaTextFieldStyle())
                        }
                        
                        // Ethnicity
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ethnicity")
                                .font(.system(size: 14, weight: .semibold))
                            Menu {
                                ForEach(Ethnicity.allCases) { ethnicity in
                                    Button(ethnicity.rawValue) {
                                        selectedEthnicity = ethnicity
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedEthnicity?.rawValue ?? "Select ethnicity")
                                        .foregroundColor(selectedEthnicity == nil ? .miyaTextSecondary : .miyaTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                            }
                        }
                        
                        // Smoking
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Smoking Status")
                                .font(.system(size: 14, weight: .semibold))
                            VStack(spacing: 8) {
                                ForEach(SmokingStatus.allCases) { status in
                                    Button {
                                        smokingStatus = status
                                    } label: {
                                        HStack {
                                            Text(status.displayText)
                                            Spacer()
                                            Image(systemName: smokingStatus == status ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(smokingStatus == status ? .miyaPrimary : .secondary)
                                        }
                                        .padding(12)
                                        .background(Color.white)
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Heart Health Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Heart Health")
                            .font(.system(size: 18, weight: .semibold))
                        
                        // Blood Pressure
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Blood Pressure Status")
                                .font(.system(size: 14, weight: .semibold))
                            VStack(spacing: 8) {
                                bpRow("Normal", "normal")
                                bpRow("High, not on medication", "elevated_untreated")
                                bpRow("High, taking medication", "elevated_treated")
                                bpRow("Never checked / Not sure", "unknown")
                            }
                        }
                        
                        // Diabetes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diabetes Status")
                                .font(.system(size: 14, weight: .semibold))
                            VStack(spacing: 8) {
                                diabetesRow("No diabetes", "none")
                                diabetesRow("Pre-diabetes", "pre_diabetic")
                                diabetesRow("Type 1 diabetes", "type_1")
                                diabetesRow("Type 2 diabetes", "type_2")
                                diabetesRow("Not sure", "unknown")
                            }
                        }
                        
                        // Conditions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prior Events & Conditions")
                                .font(.system(size: 14, weight: .semibold))
                            
                            // Guided setup must not show Toggle switches.
                            SelectableConditionRow(title: "Heart attack", isSelected: $hasPriorHeartAttack)
                            SelectableConditionRow(title: "Stroke", isSelected: $hasPriorStroke)
                            SelectableConditionRow(title: "Chronic kidney disease", isSelected: $hasChronicKidneyDisease)
                            SelectableConditionRow(title: "Atrial fibrillation (irregular heartbeat)", isSelected: $hasAtrialFibrillation)
                            SelectableConditionRow(title: "High cholesterol (diagnosed by doctor)", isSelected: $hasHighCholesterol)
                        }
                    }
                    
                    // Family History Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Family History")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("Do any parents or siblings have a history of the following?")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        // Guided setup must not show Toggle switches.
                        SelectableConditionRow(title: "Heart disease (heart attack, bypass surgery) before age 60", isSelected: $familyHeartDiseaseEarly)
                        SelectableConditionRow(title: "Stroke before age 60", isSelected: $familyStrokeEarly)
                        SelectableConditionRow(title: "Type 2 diabetes (at any age)", isSelected: $familyType2Diabetes)
                    }
                    
                    // Save button
                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text("Save Changes")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isLoading)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadInitialData()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func bpRow(_ label: String, _ value: String) -> some View {
        Button {
            bloodPressureStatus = value
        } label: {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: bloodPressureStatus == value ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(bloodPressureStatus == value ? .miyaPrimary : .secondary)
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func diabetesRow(_ label: String, _ value: String) -> some View {
        Button {
            diabetesStatus = value
        } label: {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: diabetesStatus == value ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(diabetesStatus == value ? .miyaPrimary : .secondary)
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func loadInitialData() {
        // Prefill from initialData
        selectedGender = Gender.allCases.first { $0.rawValue == initialData.aboutYou.gender }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let dob = formatter.date(from: initialData.aboutYou.dateOfBirth) {
            dateOfBirth = dob
        }
        
        heightCm = String(Int(initialData.aboutYou.heightCm))
        weightKg = String(Int(initialData.aboutYou.weightKg))
        selectedEthnicity = Ethnicity.allCases.first { $0.rawValue == initialData.aboutYou.ethnicity }
        smokingStatus = SmokingStatus.allCases.first { $0.rawValue == initialData.aboutYou.smokingStatus }
        
        bloodPressureStatus = initialData.heartHealth.bloodPressureStatus
        diabetesStatus = initialData.heartHealth.diabetesStatus
        hasPriorHeartAttack = initialData.heartHealth.hasPriorHeartAttack
        hasPriorStroke = initialData.heartHealth.hasPriorStroke
        hasChronicKidneyDisease = initialData.heartHealth.hasChronicKidneyDisease
        hasAtrialFibrillation = initialData.heartHealth.hasAtrialFibrillation
        hasHighCholesterol = initialData.heartHealth.hasHighCholesterol
        
        familyHeartDiseaseEarly = initialData.medicalHistory.familyHeartDiseaseEarly
        familyStrokeEarly = initialData.medicalHistory.familyStrokeEarly
        familyType2Diabetes = initialData.medicalHistory.familyType2Diabetes
    }
    
    private func saveChanges() async {
        isLoading = true
        
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            
            let updatedData = GuidedHealthData(
                aboutYou: GuidedHealthData.AboutYouData(
                    gender: selectedGender?.rawValue ?? "",
                    dateOfBirth: formatter.string(from: dateOfBirth),
                    heightCm: Double(heightCm) ?? 0,
                    weightKg: Double(weightKg) ?? 0,
                    ethnicity: selectedEthnicity?.rawValue ?? "",
                    smokingStatus: smokingStatus?.rawValue ?? ""
                ),
                heartHealth: GuidedHealthData.HeartHealthData(
                    bloodPressureStatus: bloodPressureStatus,
                    diabetesStatus: diabetesStatus,
                    hasPriorHeartAttack: hasPriorHeartAttack,
                    hasPriorStroke: hasPriorStroke,
                    hasChronicKidneyDisease: hasChronicKidneyDisease,
                    hasAtrialFibrillation: hasAtrialFibrillation,
                    hasHighCholesterol: hasHighCholesterol
                ),
                medicalHistory: GuidedHealthData.MedicalHistoryData(
                    familyHeartDiseaseEarly: familyHeartDiseaseEarly,
                    familyStrokeEarly: familyStrokeEarly,
                    familyType2Diabetes: familyType2Diabetes
                )
            )
            
            // Save back to guided health data store (NOT user_profiles)
            try await dataManager.saveGuidedHealthData(memberId: memberId, healthData: updatedData)
            
            await MainActor.run {
                isLoading = false
                onSave()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

