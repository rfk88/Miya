//
//  SettingsView.swift
//  Miya Health
//
//  Settings menu with CSV import for testing vitality scores
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var onboardingManager: OnboardingManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImporter = false
    @State private var importStatus: String = ""
    @State private var showingAlert = false
    @State private var currentVitalityScore: VitalityScore?
    @State private var showingVitalityUpload = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test Vitality Scoring")
                            .font(.headline)
                        Text("Import CSV data to test vitality score calculations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Developer Tools")
                }
                
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.miyaPrimary)
                            Text("Import Vitality Data CSV")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.caption)
                            .foregroundColor(importStatus.contains("✅") ? .green : .secondary)
                    }
                } header: {
                    Text("Import Test Data")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSV format:")
                        Text("date,sleep_hours,steps,hrv_ms,resting_hr")
                            .font(.system(.caption, design: .monospaced))
                        Text("Example scenarios included:")
                        Text("• scenario_healthy_young.csv")
                        Text("• scenario_stressed_executive.csv")
                        Text("• scenario_decline_alert.csv")
                    }
                    .font(.caption)
                }
                
                #if DEBUG
                Section {
                    Button {
                        showingVitalityUpload = true
                    } label: {
                        HStack {
                            Image(systemName: "tray.and.arrow.up.fill")
                                .foregroundColor(.miyaPrimary)
                            Text("Upload vitality data (debug)")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Manual Upload (Debug)")
                } footer: {
                    Text("Temporary tool for testing trends/patterns before ROOK webhooks. Saves snapshots and daily scores for the current user.")
                        .font(.caption)
                }
                #endif
                
                if let score = currentVitalityScore {
                    Section {
                        VStack(spacing: 16) {
                            // Total Score
                            HStack {
                                Text("Current Vitality Score")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(score.totalScore)/100")
                                    .font(.title2.bold())
                                    .foregroundColor(.miyaPrimary)
                            }
                            
                            Divider()
                            
                            // Component breakdown
                            VStack(spacing: 12) {
                                ScoreRow(label: "Sleep", points: score.sleepPoints, max: 35)
                                ScoreRow(label: "Movement", points: score.movementPoints, max: 35)
                                ScoreRow(label: "Stress/Recovery", points: score.stressPoints, max: 30)
                            }
                            
                            Text("Based on 7-day rolling average")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Last Calculated Score")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        currentVitalityScore = nil
                        importStatus = ""
                    } label: {
                        Text("Clear Test Data")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result: result)
            }
            .alert("Import Complete", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importStatus)
            }
            .sheet(isPresented: $showingVitalityUpload) {
                NavigationStack {
                    VitalityImportView()
                        .environmentObject(onboardingManager)
                        .environmentObject(dataManager)
                }
            }
        }
    }
    
    private func handleCSVImport(result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            
            // Access the file
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = "❌ Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Read CSV
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Parse data
            let vitalityData = VitalityCalculator.parseCSV(content: content)
            
            guard !vitalityData.isEmpty else {
                importStatus = "❌ No valid data found in CSV"
                showingAlert = true
                return
            }
            
            // Calculate 7-day rolling average
            if let score = VitalityCalculator.calculate7DayAverage(from: vitalityData) {
                currentVitalityScore = score
                importStatus = "✅ Imported \(vitalityData.count) days of data"
                showingAlert = true
            } else {
                importStatus = "❌ Need at least 7 days of data for calculation"
                showingAlert = true
            }
            
        } catch {
            importStatus = "❌ Error: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager())
}
