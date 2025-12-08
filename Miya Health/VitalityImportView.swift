//
//  VitalityImportView.swift
//  Miya Health
//
//  Upload vitality CSV during onboarding, compute scores, and save to Supabase
//

import SwiftUI
import UniformTypeIdentifiers

struct VitalityImportView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImporter = false
    @State private var importStatus: String = ""
    @State private var latestScore: VitalityScore?
    @State private var isSaving = false
    @State private var showAlert = false
    
    private let currentStep: Int = 7  // insert after RiskResults (adjust if needed)
    private let totalSteps: Int = 9
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            VStack(spacing: 24) {
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import Vitality Data")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Upload a CSV with your sleep, steps, and HRV/resting HR. We’ll calculate your vitality score for this user.")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 12) {
                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "tray.and.arrow.down.fill")
                            Text("Import Vitality CSV")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    
                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.system(size: 13))
                            .foregroundColor(importStatus.contains("✅") ? .green : .miyaTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    if let score = latestScore {
                        VStack(spacing: 10) {
                            Text("Latest Vitality Score")
                                .font(.headline)
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("\(score.totalScore)/100")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.miyaPrimary)
                            
                            HStack {
                                ScoreRow(label: "Sleep", points: score.sleepPoints, max: 35)
                                ScoreRow(label: "Move", points: score.movementPoints, max: 35)
                                ScoreRow(label: "Stress", points: score.stressPoints, max: 30)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    }
                }
                
                Spacer()
                
                NavigationLink {
                    FamilyMembersInviteView()
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager)
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.bottom, 16)
                .disabled(latestScore == nil) // require upload
            }
            .padding(.horizontal, 24)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importStatus)
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = "Cannot access the selected file."
                showAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = VitalityCalculator.parseCSV(content: content)
            guard !parsed.isEmpty else {
                importStatus = "No data rows found in CSV."
                showAlert = true
                return
            }
            
            let rollingScores = VitalityCalculator.computeRollingScores(from: parsed, window: 7)
            guard let latest = rollingScores.last else {
                importStatus = "Need at least 7 days of data to compute a score."
                showAlert = true
                return
            }
            
            Task {
                do {
                    isSaving = true
                    // Save all rolling scores to Supabase
                    let rows = rollingScores.map { score in
                        (date: score.date,
                         total: score.totalScore,
                         sleep: score.sleepPoints,
                         movement: score.movementPoints,
                         stress: score.stressPoints,
                         source: "csv")
                    }
                    try await dataManager.saveVitalityScores(rows)
                    await MainActor.run {
                        latestScore = latest
                        importStatus = "✅ Imported \(parsed.count) days; latest score \(latest.totalScore)/100"
                        showAlert = false
                        isSaving = false
                    }
                } catch {
                    await MainActor.run {
                        importStatus = "Error saving vitality scores: \(error.localizedDescription)"
                        showAlert = true
                        isSaving = false
                    }
                }
            }
            
        } catch {
            importStatus = "Error reading file: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        VitalityImportView()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

// Simple score row for component display
struct ScoreRow: View {
    let label: String
    let points: Int
    let max: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.miyaTextSecondary)
            HStack {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 6)
                            .cornerRadius(3)
                        Rectangle()
                            .fill(Color.miyaPrimary)
                            .frame(width: geo.size.width * CGFloat(points) / CGFloat(max), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(width: 80, height: 6)
                
                Text("\(points)/\(max)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.miyaTextSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        VitalityImportView()
            .environmentObject(OnboardingManager())
            .environmentObject(DataManager())
    }
}

