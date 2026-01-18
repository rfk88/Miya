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
    
    // ROOK export import (used for DEBUG and for guided invitees awaiting admin profile completion)
    @State private var showingROOKExportPicker = false
    @State private var lastROOKExportFilename: String?
    @State private var rookSnapshot: VitalitySnapshot?
    @State private var rookWindowRaw: VitalityRawMetrics?
    @State private var rookBreakdown: VitalityBreakdown?
    @State private var rookExplanation: VitalityExplanation?
    @State private var rookImportError: String?
    
    private var isGuidedInviteeAwaitingAdmin: Bool {
        onboardingManager.isInvitedUser && onboardingManager.guidedSetupStatus == .acceptedAwaitingData
    }
    
    // New engine state (testing)
    @State private var newEngineSnapshot: VitalitySnapshot?
    @State private var newEngineErrorMessage: String?
    @State private var vitalityBreakdown: VitalityBreakdown?
    @State private var vitalityExplanation: VitalityExplanation?

    // Wearable vitality (ROOK -> webhooks -> wearable_daily_metrics)
    @State private var wearableSnapshot: VitalitySnapshot?
    @State private var wearableSyncStatus: String?
    @State private var isWearableSyncing: Bool = false
    @State private var wearableDaysUsed: Int? = nil
    
    // Expandable breakdown
    @State private var showBreakdown = false
    @State private var showOptimalInfo = false
    
    // Product UI state for vitality breakdown display
    @State private var expandedPillars: Set<String> = []
    
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
                
                // Guided Setup (waiting): do NOT show "Calculating…" + 0.0 BMI placeholders.
                if isGuidedInviteeAwaitingAdmin {
                    guidedWaitingForAdminPanel
                } else {
                    // Wearable vitality card (shows after ROOK sync + webhook ingestion)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.miyaPrimary)
                            Text("Current Vitality")
                                .font(.headline)
                                .foregroundColor(.miyaTextPrimary)
                            Spacer()
                            if isWearableSyncing {
                                ProgressView()
                                    .scaleEffect(0.9)
                            }
                        }

                        if let snap = wearableSnapshot {
                            let sleepPillar = snap.pillarScores.first(where: { $0.pillar == .sleep })?.score
                            let movementPillar = snap.pillarScores.first(where: { $0.pillar == .movement })?.score
                            let stressPillar = snap.pillarScores.first(where: { $0.pillar == .stress })?.score

                            Text("\(snap.totalScore)/100")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(.miyaTextPrimary)

                            HStack(spacing: 12) {
                                PillarMini(label: "Sleep", score: sleepPillar)
                                PillarMini(label: "Movement", score: movementPillar)
                                PillarMini(label: "Recovery", score: stressPillar)
                            }

                            if let days = wearableDaysUsed, days > 0 {
                                Text(days < 7
                                     ? "Early estimate based on your last \(days) day\(days == 1 ? "" : "s") of data. We’ll refine it as more days sync."
                                     : "Based on your last 7 days of wearable data.")
                                    .font(.subheadline)
                                    .foregroundColor(.miyaTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("We’ll refine this score as more days sync in.")
                                    .font(.subheadline)
                                    .foregroundColor(.miyaTextSecondary)
                            }
                        } else if isWearableSyncing {
                            // STATE 2: Still syncing (0-60 seconds)
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressView()
                                
                                Text("Building your baseline...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextSecondary)
                                
                                // Show what we have so far
                                if let status = wearableSyncStatus, !status.isEmpty {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Text("This usually takes 1-2 minutes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 20)
                        } else {
                            // STATE 3: Not ready yet (after attempts exhausted)
                            VStack(spacing: 16) {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 40))
                                    .foregroundColor(.miyaPrimary.opacity(0.5))
                                
                                VStack(spacing: 8) {
                                    Text("Your Score is Computing")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Text("We're collecting data from your wearable. Your vitality score will appear on your dashboard in a few minutes.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.miyaTextSecondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Text("Continue to dashboard to see progress →")
                                    .font(.caption)
                                    .foregroundColor(.miyaPrimary)
                            }
                            .padding(.vertical, 20)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

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
                }
                
                // Vitality Target Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.miyaPrimary)
                        Text(isGuidedInviteeAwaitingAdmin ? "Your Vitality" : "Your Vitality Goal")
                            .font(.headline)
                            .foregroundColor(.miyaTextPrimary)
                    }
                    
                    if isGuidedInviteeAwaitingAdmin {
                        Text("Connect your wearable to start tracking a daily vitality score and how it trends over time. Once your admin finishes your health profile and you approve it, you’ll also see your cardiovascular risk and your recommended vitality goal.")
                            .font(.subheadline)
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            Text("\(onboardingManager.optimalVitalityTarget)")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.miyaPrimary)
                            
                            Text("/100")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                        }
                        
                        Text("This is your recommended vitality goal based on your cardiovascular risk. You can work toward 100/100 as your health improves.")
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
                    }
                
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
                                
                                if isGuidedInviteeAwaitingAdmin {
                                    Text("/100")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 6)
                                } else {
                                    Text("/\(onboardingManager.optimalVitalityTarget)")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 6)
                                }
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
                        
                        if let breakdown = vitalityBreakdown {
                            Divider()
                                .padding(.vertical, 8)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("How your vitality was calculated")
                                    .font(.headline)
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("\(Int(breakdown.totalScore.rounded())) / \(Int(breakdown.totalMaxScore.rounded()))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                if let explanation = vitalityExplanation {
                                    Text(explanation.totalText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                ForEach(breakdown.pillars, id: \.id) { pillar in
                                    VitalityPillarCard(
                                        pillar: pillar,
                                        isExpanded: expandedPillars.contains(pillar.id),
                                        onToggle: {
                                            if expandedPillars.contains(pillar.id) {
                                                expandedPillars.remove(pillar.id)
                                            } else {
                                                expandedPillars.insert(pillar.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // New engine results (internal testing)
                        if let snapshot = newEngineSnapshot {
                            Divider()
                                .padding(.vertical, 8)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("New Vitality Engine")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.miyaTextPrimary)
                                    
                                    Text("(Testing)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                
                                HStack(alignment: .bottom, spacing: 8) {
                                    Text("\(snapshot.totalScore)")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.miyaPrimary)
                                    
                                    Text("/100")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 4)
                                    
                                    Spacer()
                                    
                                    Text(snapshot.ageGroup.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 4)
                                }
                                
                                // Pillar breakdown
                                VStack(spacing: 8) {
                                    ForEach(snapshot.pillarScores, id: \.pillar) { pillar in
                                        HStack {
                                            Image(systemName: pillarIcon(for: pillar.pillar))
                                                .foregroundColor(.miyaPrimary)
                                                .frame(width: 20)
                                            Text("\(pillar.pillar.displayName):")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            if pillar.isAvailable {
                                                Text("\(pillar.score)/100")
                                                    .font(.caption.bold())
                                            } else {
                                                Text("Missing")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                
                                Text("Age-specific scoring with schema-based ranges.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(.top, 4)
                        }
                        
                        if let error = newEngineErrorMessage {
                            Text("New engine error: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                    } else {
                        // Import button
                        VStack(alignment: .leading, spacing: 10) {
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

                            // Guided invitees: show a short explanation above the import controls.
                            if isGuidedInviteeAwaitingAdmin {
                                Text("Vitality works independently of your admin-completed health profile.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            if isGuidedInviteeAwaitingAdmin || isDebugBuild {
                                Button {
                                    showingROOKExportPicker = true
                                } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.badge.plus")
                                        .foregroundColor(.miyaSecondary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(isGuidedInviteeAwaitingAdmin ? "Upload ROOK Export" : "Upload ROOK Export (Debug)")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.miyaTextPrimary)
                                        
                                        Text(isGuidedInviteeAwaitingAdmin
                                             ? "Select a ROOK export v2 JSON file to calculate vitality"
                                             : "Select a ROOK export v2 JSON file (console logs only)")
                                            .font(.caption)
                                            .foregroundColor(.miyaTextSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                            .disabled(isImporting)
                            }
                            
                            if let name = lastROOKExportFilename {
                                Text("Last ROOK export: \(name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let err = rookImportError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if let snapshot = rookSnapshot, let raw = rookWindowRaw {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ROOK vitality")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(snapshot.totalScore)/100")
                                            .font(.caption.bold())
                                            .foregroundColor(.miyaPrimary)
                                    }
                                    
                                    if let breakdown = rookBreakdown {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Total: \(String(format: "%.1f", breakdown.totalScore)) / \(String(format: "%.1f", breakdown.totalMaxScore))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            ForEach(breakdown.pillars, id: \.id) { pillar in
                                                let pillarAvailable = pillar.submetrics.contains(where: { $0.status != .missing })
                                                DisclosureGroup {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        ForEach(pillar.submetrics) { sub in
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                HStack(alignment: .top) {
                                                                    Text(sub.label)
                                                                        .font(.caption)
                                                                        .foregroundColor(.miyaTextPrimary)
                                                                    Spacer()
                                                                    Text("\(String(format: "%.1f", sub.points)) / \(String(format: "%.1f", sub.maxPoints))")
                                                                        .font(.caption2.monospacedDigit())
                                                                        .foregroundColor(.secondary)
                                                                }
                                                                
                                                                HStack(alignment: .top) {
                                                                    Text(sub.valueText)
                                                                        .font(.caption2)
                                                                        .foregroundColor(.secondary)
                                                                    Spacer()
                                                                    Text(sub.status.rawValue)
                                                                        .font(.caption2)
                                                                        .foregroundColor(sub.status == .missing ? .red : .secondary)
                                                                }
                                                                
                                                                Text(sub.targetText.isEmpty ? "—" : sub.targetText)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.secondary)
                                                                
                                                                if let notes = sub.notes, !notes.isEmpty {
                                                                    Text(notes)
                                                                        .font(.caption2)
                                                                        .foregroundColor(.secondary)
                                                                }
                                                            }
                                                            .padding(.vertical, 4)
                                                        }
                                                    }
                                                    .padding(.top, 6)
                                                } label: {
                                                    HStack {
                                                        if pillarAvailable {
                                                            Text("\(pillar.label): \(String(format: "%.1f", pillar.score)) / \(String(format: "%.1f", pillar.maxScore))")
                                                                .font(.caption.bold())
                                                                .foregroundColor(.secondary)
                                                        } else {
                                                            Text("\(pillar.label): Missing")
                                                                .font(.caption.bold())
                                                                .foregroundColor(.secondary)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                                .tint(.miyaPrimary)
                                            }
                                        }
                                    }
                                    
                                    VStack(spacing: 6) {
                                        rookMetricRow("sleepDurationHours", raw.sleepDurationHours)
                                        rookMetricRow("restorativeSleepPercent", raw.restorativeSleepPercent)
                                        rookMetricRow("sleepEfficiencyPercent", raw.sleepEfficiencyPercent)
                                        rookMetricRow("awakePercent", raw.awakePercent)
                                        rookMetricRow("movementMinutes", raw.movementMinutes)
                                        rookMetricRow("steps", raw.steps.map { Double($0) })
                                        rookMetricRow("activeCalories", raw.activeCalories)
                                        rookMetricRow("hrvMs", raw.hrvMs)
                                        rookMetricRow("restingHeartRate", raw.restingHeartRate)
                                        rookMetricRow("breathingRate", raw.breathingRate)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
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
                NavigationLink {
                    if isGuidedInviteeAwaitingAdmin {
                        OnboardingCompleteView(membersCount: 0)
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    } else if onboardingManager.isInvitedUser {
                        AlertsChampionView()
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    } else {
                        FamilyMembersInviteView()
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    }
                } label: {
                    Text(isGuidedInviteeAwaitingAdmin ? "Go to Dashboard" : "Continue")
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
            // Refresh guided status before choosing which UI to show (prevents "Calculating…/0.0" defaults on first paint).
            Task {
                if onboardingManager.isInvitedUser {
                    await onboardingManager.refreshGuidedContextFromDB(dataManager: dataManager)
                }
                calculateRisk()
                await computeWearableVitalityIfAvailable()
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .fileImporter(
            isPresented: $showingROOKExportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleROOKExportImport(result: result)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiWearableConnected)) { notification in
            // AUTO_API_SCORING_TRIGGERED: When API-based wearable connects, automatically compute vitality
            if let userInfo = notification.userInfo,
               let wearableName = userInfo["wearableName"] as? String,
               let userId = userInfo["userId"] as? String {
                print("🟢 RiskResultsView: Received API wearable connected notification - wearable=\(wearableName) userId=\(userId)")
                Task {
                    await computeWearableVitalityIfAvailable()
                }
            }
        }
    }

    private func calculateRisk() {
        Task {
            do {
                // Guided invitees awaiting admin don't have their health profile filled yet.
                // They can still compute vitality; risk band/optimal target will come after admin completion.
                if isGuidedInviteeAwaitingAdmin {
                    await MainActor.run {
                        isCalculating = false
                    }
                    return
                }
                
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

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Guided waiting UI
    
    private var guidedWaitingForAdminPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.clock")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.miyaPrimary)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("We’re setting things up")
                        .font(.headline)
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Your admin is completing your health profile. Once it’s ready, you’ll be able to review and approve it here.")
                        .font(.subheadline)
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("What you can do now")
                    .font(.subheadline.bold())
                    .foregroundColor(.miyaTextPrimary)
                
                Text("Connect your wearable to start tracking vitality right away. You’ll see a daily vitality score and how it changes over time.")
                    .font(.subheadline)
                    .foregroundColor(.miyaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("What happens next")
                    .font(.subheadline.bold())
                    .foregroundColor(.miyaTextPrimary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1) Your admin finishes your health profile.")
                    Text("2) You review it and make any changes you want.")
                    Text("3) Once approved, we’ll show your cardiovascular risk and your recommended vitality goal.")
                    Text("4) Then you can set up your champion and notification preferences.")
                }
                .font(.subheadline)
                .foregroundColor(.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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
        case 0...34: ageGroup = "under 40"
        case 35...59: ageGroup = "40-59"
        case 60...74: ageGroup = "60-74"
        default: ageGroup = "75+"
        }
        
        return "For you, 100/100 represents hitting or slightly exceeding the optimal health ranges for your age group (\(ageGroup)). Based on your cardiovascular risk band (\(band)), we recommend starting with a goal of \(target)/100. This is a safe, realistic target—not a ceiling. As your habits and health improve, you can work toward 100/100, which is your personal maximum."
    }
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "bed.double.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
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
                let fileExtension = url.pathExtension.lowercased()
                
                if fileExtension == "xml" {
                    // Parse XML
                    vitalityData = VitalityCalculator.parseAppleHealthXML(content: content)
                } else if fileExtension == "csv" || fileExtension == "txt" {
                    // Parse CSV
                    vitalityData = VitalityCalculator.parseCSV(content: content)
                } else if fileExtension == "json" {
                    // Parse JSON
                    vitalityData = VitalityJSONParser.parse(content: content)
                } else {
                    await MainActor.run {
                        errorMessage = "Unsupported file type: .\(fileExtension)"
                        showError = true
                        isImporting = false
                    }
                    return
                }
                
                guard !vitalityData.isEmpty else {
                    await MainActor.run {
                        errorMessage = "No valid data found in file"
                        showError = true
                        isImporting = false
                    }
                    return
                }
                
                // TEST: Call new VitalityScoringEngine alongside old engine
                // Use scoreIfPossible so we can cleanly handle insufficient data without penalizing missing pillars.
                
                // Calculate user age
                let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
                
                // Build VitalityRawMetrics from flexible window (7-30 days)
                let rawMetrics = VitalityMetricsBuilder.fromWindow(age: age, records: vitalityData)
                
                let engine = VitalityScoringEngine()
                var snapshotForWrite: VitalitySnapshot? = nil
                if let scored = engine.scoreIfPossible(raw: rawMetrics) {
                    let snapshot = scored.snapshot
                    snapshotForWrite = snapshot
                    let breakdown = scored.breakdown
                    let explanation = VitalityExplanation.derive(from: breakdown)
                    
                    await MainActor.run {
                        newEngineSnapshot = snapshot
                        vitalityBreakdown = breakdown
                        vitalityExplanation = explanation
                        newEngineErrorMessage = nil
                    }
                } else {
                    await MainActor.run {
                        newEngineSnapshot = nil
                        vitalityBreakdown = nil
                        vitalityExplanation = nil
                        newEngineErrorMessage = "Insufficient data to compute vitality (need at least 2 pillars)."
                    }
                }
                
                // Continue with old engine (unchanged behavior)
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
                    try await dataManager.saveVitalityScores(tuples, snapshot: snapshotForWrite)
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
    
    private func rookMetricRow(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(value.map { String(format: "%.2f", $0) } ?? "nil")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.miyaTextPrimary)
        }
    }
    
    private struct ROOKWindowDebugInfo {
        let matchedDays: Int
        let selectedWindowSize: Int
        let firstDayKey: String?
        let lastDayKey: String?
        let windowMaxDays: Int
        let windowMinDays: Int
    }
    
    /// Mirror the day-key matching + window selection logic used by `ROOKWindowAggregator`
    /// so we can print diagnostics if a window is empty or metrics are unexpectedly nil.
    private func computeROOKWindowDebugInfo(
        dataset: ROOKDataset,
        windowMaxDays: Int = 30,
        windowMinDays: Int = 7
    ) -> ROOKWindowDebugInfo {
        func formatUTCYYYYMMDD(_ date: Date) -> String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: date)
        }
        
        func normalizeUTCYYYYMMDD(from raw: String) -> String? {
            // Fast path for plain date
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
            
            // ISO8601 parsing
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
            
            // Fallback: some timestamps use spaces
            let normalized = raw.replacingOccurrences(of: " ", with: "T")
            if let d = iso.date(from: normalized) ?? isoNoFrac.date(from: normalized) {
                return formatUTCYYYYMMDD(d)
            }
            
            return nil
        }
        
        let sleepKeys: [String] = {
            guard let arr = dataset.sleep_health?.sleep_summaries else { return [] }
            return arr.compactMap { item in
                guard let raw = item.sleep_health?.summary?.sleep_summary?.duration?.sleep_date_string else { return nil }
                return normalizeUTCYYYYMMDD(from: raw)
            }
        }()
        
        let physicalKeys: [String] = {
            guard let arr = dataset.physical_health?.physical_summaries else { return [] }
            return arr.compactMap { item in
                guard let raw = item.physical_health?.summary?.physical_summary?.metadata?.datetime_string else { return nil }
                return normalizeUTCYYYYMMDD(from: raw)
            }
        }()
        
        let allKeys = Set(sleepKeys).union(Set(physicalKeys))
        let sortedKeys = allKeys.sorted()
        let windowKeys: [String] = {
            if sortedKeys.count >= windowMaxDays {
                return Array(sortedKeys.suffix(windowMaxDays))
            }
            return sortedKeys
        }()
        
        return ROOKWindowDebugInfo(
            matchedDays: sortedKeys.count,
            selectedWindowSize: windowKeys.count,
            firstDayKey: windowKeys.first,
            lastDayKey: windowKeys.last,
            windowMaxDays: windowMaxDays,
            windowMinDays: windowMinDays
        )
    }
    
    private func handleROOKExportImport(result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                
                await MainActor.run {
                    lastROOKExportFilename = url.lastPathComponent
                    rookImportError = nil
                    rookSnapshot = nil
                    rookWindowRaw = nil
                    rookBreakdown = nil
                    rookExplanation = nil
                }
                
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run {
                        rookImportError = "Cannot access file: \(url.lastPathComponent)"
                    }
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url)
                let dataset = try JSONDecoder().decode(ROOKDataset.self, from: data)
                
                let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
                let windowRaw = ROOKWindowAggregator.buildWindowRawMetrics(age: age, dataset: dataset)
                
                // Backfill last 7 UTC days of pillar scores into vitality_scores for day-over-day trends (manual testing).
                do {
                    let dailyRaw = ROOKWindowAggregator.buildDailyRawMetricsByUTCKey(age: age, dataset: dataset)
                    let last7Raw = Array(dailyRaw.suffix(7))
                    
                    let engine = VitalityScoringEngine()
                    let dailySnapshots: [(dayKey: String, snapshot: VitalitySnapshot)] = last7Raw.compactMap { dayKey, raw in
                        guard let scored = engine.scoreIfPossible(raw: raw) else { return nil }
                        return (dayKey, scored.snapshot)
                    }
                    
                    if !dailySnapshots.isEmpty {
                        try await dataManager.saveDailyVitalityPillarScores(dailySnapshots, source: "manual")
                        print("✅ ROOK Export: backfilled daily pillar scores (days=\(dailySnapshots.count))")
                    }
                } catch {
                    print("❌ ROOK Export: failed to backfill daily pillar scores: \(error.localizedDescription)")
                }
                
                // Score only if data is sufficiently complete (>= 2 pillars available).
                guard let scored = VitalityScoringEngine().scoreIfPossible(raw: windowRaw) else {
                    await MainActor.run {
                        rookImportError = "Insufficient data to compute vitality (need at least 2 pillars)."
                    }
                    return
                }
                
                let snapshot = scored.snapshot
                let breakdown = scored.breakdown
                let explanation = VitalityExplanation.derive(from: breakdown)
                
                // Persist a "current vitality snapshot" for temporary testing so Family Vitality can be computed.
                // Tag as 'manual' so we can exclude/remove this path later when ROOK is live.
                do {
                    try await dataManager.saveVitalitySnapshot(snapshot: snapshot, source: "manual")
                    print("✅ ROOK Export: persisted vitality snapshot to user_profiles (total=\(snapshot.totalScore), source=manual)")
                } catch {
                    print("❌ ROOK Export: failed to persist vitality snapshot: \(error.localizedDescription)")
                    await MainActor.run {
                        rookImportError = "Error saving vitality snapshot: \(error.localizedDescription)"
                    }
                }
                
                await MainActor.run {
                    rookWindowRaw = windowRaw
                    rookSnapshot = snapshot
                    rookBreakdown = breakdown
                    rookExplanation = explanation
                    
                    newEngineSnapshot = snapshot
                    vitalityBreakdown = breakdown
                    vitalityExplanation = explanation
                }
                
                let nonNil: [(String, Bool)] = [
                    ("sleepDurationHours", windowRaw.sleepDurationHours != nil),
                    ("restorativeSleepPercent", windowRaw.restorativeSleepPercent != nil),
                    ("sleepEfficiencyPercent", windowRaw.sleepEfficiencyPercent != nil),
                    ("awakePercent", windowRaw.awakePercent != nil),
                    ("movementMinutes", windowRaw.movementMinutes != nil),
                    ("steps", windowRaw.steps != nil),
                    ("activeCalories", windowRaw.activeCalories != nil),
                    ("hrvMs", windowRaw.hrvMs != nil),
                    ("restingHeartRate", windowRaw.restingHeartRate != nil),
                    ("breathingRate", windowRaw.breathingRate != nil)
                ]
                let anyMetricPresent = nonNil.contains(where: { $0.1 })
                let info = computeROOKWindowDebugInfo(dataset: dataset)
                
                print("=== ROOK Export Debug Import ===")
                print("File:", url.lastPathComponent)
                print("Age:", age)
                print("rookWindowRaw non-nil:", true)
                print("rookSnapshot non-nil:", true)
                print("Vitality snapshot total:", snapshot.totalScore, "/100")
                
                print("Raw metrics (non-nil vs nil):")
                for (label, isPresent) in nonNil {
                    print(" -", label, "=>", isPresent ? "non-nil" : "nil")
                }
                
                print("Window diagnostics:")
                print("Matched days:", info.matchedDays)
                print("Selected window size:", info.selectedWindowSize, "(max:", info.windowMaxDays, "min:", info.windowMinDays, ")")
                print("First day key:", info.firstDayKey ?? "nil")
                print("Last day key:", info.lastDayKey ?? "nil")
                
                if !anyMetricPresent {
                    print("⚠️ Window appears empty (all 10 metrics nil).")
                }
                
                print("Aggregated raw metrics:", windowRaw)
                for pillar in snapshot.pillarScores {
                    print("Pillar:", pillar.pillar.displayName, "score:", pillar.score, "/100")
                }
                print("=== End ROOK Export Debug Import ===")
            } catch {
                await MainActor.run {
                    rookImportError = error.localizedDescription
                }
            }
        }
    }

    private func computeWearableVitalityIfAvailable() async {

        await MainActor.run {
            isWearableSyncing = true
            wearableSyncStatus = "Building your baseline from Apple Health… This can take a moment the first time."
        }

        let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
        let engine = VitalityScoringEngine()

        func avgDouble(_ xs: [Double?]) -> Double? {
            let v = xs.compactMap { $0 }
            guard !v.isEmpty else { return nil }
            return v.reduce(0, +) / Double(v.count)
        }
        func avgIntRounded(_ xs: [Int?]) -> Int? {
            let v = xs.compactMap { $0 }
            guard !v.isEmpty else { return nil }
            return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
        }

        // Poll a few times because webhooks may arrive a bit after the in-app ROOK sync completes.
        for attempt in 1...12 {  // 12 × 5s = 60 seconds total
            do {
                let rows = try await dataManager.fetchWearableDailyMetrics(days: 21)

                // Merge multiple rows per day (and partial rows) into a single "best" row for that day.
                // This avoids missing sleep/steps when they come from different webhook deliveries.
                let byDay: [String: [DataManager.WearableDailyMetricRow]] = Dictionary(grouping: rows, by: { $0.metricDate })
                let mergedDays: [(dayKey: String, steps: Int?, sleepMinutes: Int?, movementMinutes: Int?, deepSleepMinutes: Int?, remSleepMinutes: Int?, sleepEfficiencyPct: Double?, hrvMs: Double?, restingHr: Double?)] =
                    byDay.keys.sorted().map { dayKey in
                        let dayRows = byDay[dayKey] ?? []
                        let steps = dayRows.compactMap(\.steps).max()
                        let sleepMinutes = dayRows.compactMap(\.sleepMinutes).max()
                        let movementMinutes = dayRows.compactMap(\.movementMinutes).max()
                        let deepSleepMinutes = dayRows.compactMap(\.deepSleepMinutes).max()
                        let remSleepMinutes = dayRows.compactMap(\.remSleepMinutes).max()
                        let sleepEfficiencyPct = dayRows.compactMap(\.sleepEfficiencyPct).max()
                        let hrvMs = dayRows.compactMap(\.hrvMs).max()
                        let restingHr = dayRows.compactMap(\.restingHr).max()
                        return (dayKey, steps, sleepMinutes, movementMinutes, deepSleepMinutes, remSleepMinutes, sleepEfficiencyPct, hrvMs, restingHr)
                    }

                // Take last up to 7 unique days.
                let last = Array(mergedDays.suffix(7))
                let daysUsed = last.count

                let sleepDays = last.filter { $0.sleepMinutes != nil }.count
                let stepDays = last.filter { $0.steps != nil }.count
                let movementDays = last.filter { $0.movementMinutes != nil }.count
                let stressSignalDays = last.filter { $0.hrvMs != nil || $0.restingHr != nil }.count

                let dailyRaw: [(dayKey: String, raw: VitalityRawMetrics)] = last.map { r in
                    let sleepHours = r.sleepMinutes.map { Double($0) / 60.0 }
                    let movementMins = r.movementMinutes.map { Double($0) }
                    
                    // Calculate restorative sleep % (deep + REM / total sleep)
                    let restorativeSleepPct: Double? = {
                        guard let total = r.sleepMinutes, total > 0 else { return nil }
                        let restorative = (r.deepSleepMinutes ?? 0) + (r.remSleepMinutes ?? 0)
                        return (Double(restorative) / Double(total)) * 100.0
                    }()
                    
                    // Calculate awake % (100 - efficiency)
                    let awakePct: Double? = r.sleepEfficiencyPct != nil ? (100.0 - r.sleepEfficiencyPct!) : nil
                    
                    return (
                        dayKey: r.dayKey,
                        raw: VitalityRawMetrics(
                            age: age,
                            sleepDurationHours: sleepHours,
                            restorativeSleepPercent: restorativeSleepPct,
                            sleepEfficiencyPercent: r.sleepEfficiencyPct,
                            awakePercent: awakePct,
                            movementMinutes: movementMins,
                            steps: r.steps,
                            activeCalories: nil,
                            hrvMs: r.hrvMs,
                            hrvType: nil,
                            restingHeartRate: r.restingHr,
                            breathingRate: nil
                        )
                    )
                }

                // Build a 7-day window raw metrics (average non-nils).
                let windowRaw = VitalityRawMetrics(
                    age: age,
                    sleepDurationHours: avgDouble(dailyRaw.map { $0.raw.sleepDurationHours }),
                    restorativeSleepPercent: avgDouble(dailyRaw.map { $0.raw.restorativeSleepPercent }),
                    sleepEfficiencyPercent: avgDouble(dailyRaw.map { $0.raw.sleepEfficiencyPercent }),
                    awakePercent: avgDouble(dailyRaw.map { $0.raw.awakePercent }),
                    movementMinutes: avgDouble(dailyRaw.map { $0.raw.movementMinutes }),
                    steps: avgIntRounded(dailyRaw.map { $0.raw.steps }),
                    activeCalories: nil,
                    hrvMs: avgDouble(dailyRaw.map { $0.raw.hrvMs }),
                    hrvType: nil,
                    restingHeartRate: avgDouble(dailyRaw.map { $0.raw.restingHeartRate }),
                    breathingRate: nil
                )

                guard let scored = engine.scoreIfPossible(raw: windowRaw) else {
                    await MainActor.run {
                        // Friendly, user-facing explanation of what we need and why.
                        if rows.isEmpty {
                            wearableSyncStatus =
                                "We're setting up your Vitality baseline. Apple Health shares summaries in batches, then we calculate your score. Keep your phone/watch with you today and check back soon. (\(attempt)/12)"
                        } else {
                            wearableSyncStatus =
                                "We're almost ready. To calculate Vitality we need a bit of sleep + movement + a heart signal (HRV or resting heart rate). Right now we have \(daysUsed)/7 days, sleep on \(sleepDays), steps on \(stepDays), and a heart signal on \(stressSignalDays). (\(attempt)/12)"
                        }
                    }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }

                let snapshot = scored.snapshot

                // Save snapshot + per-day pillar scores (for trends) exactly like the JSON import flow.
                do {
                    try await dataManager.saveVitalitySnapshot(snapshot: snapshot, source: "wearable")
                    let dailySnapshots: [(dayKey: String, snapshot: VitalitySnapshot)] = dailyRaw.compactMap { dayKey, raw in
                        guard let dayScored = engine.scoreIfPossible(raw: raw) else { return nil }
                        return (dayKey, dayScored.snapshot)
                    }
                    if !dailySnapshots.isEmpty {
                        try await dataManager.saveDailyVitalityPillarScores(dailySnapshots, source: "wearable")
                    }
                } catch {
                    print("❌ Wearable vitality persist failed:", error.localizedDescription)
                }

                await MainActor.run {
                    wearableSnapshot = snapshot
                    wearableSyncStatus = nil
                    wearableDaysUsed = daysUsed
                    isWearableSyncing = false
                }
                return
            } catch {
                await MainActor.run {
                    wearableSyncStatus = "Wearable sync error: \(error.localizedDescription)"
                }
                break
            }
        }

        await MainActor.run {
            isWearableSyncing = false
            if wearableSnapshot == nil {
                wearableSyncStatus = wearableSyncStatus ??
                    "We haven’t received enough Apple Health data yet to calculate a meaningful Vitality score. This first baseline usually appears after at least one sleep + some daily movement has synced. Try again soon, or check back tomorrow morning."
            }
        }
    }
}

// MARK: - Product vitality breakdown UI (read-only)

private struct VitalityPillarCard: View {
    let pillar: PillarBreakdown
    let isExpanded: Bool
    let onToggle: () -> Void
    
    private var isAvailable: Bool {
        pillar.submetrics.contains(where: { $0.status != .missing })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: pillar.id))
                    .foregroundColor(.miyaPrimary)
                    .frame(width: 22)
                
                Text(pillar.label)
                    .font(.subheadline.bold())
                    .foregroundColor(.miyaTextPrimary)
                
                Spacer()
                
                if isAvailable {
                    Text("\(Int(pillar.score.rounded())) / \(Int(pillar.maxScore.rounded()))")
                        .font(.subheadline.bold())
                        .foregroundColor(.miyaTextPrimary)
                } else {
                    Text("Missing")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                }
            }
            
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { _ in onToggle() }
                )
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pillar.submetrics) { sub in
                        VitalitySubmetricRow(sub: sub)
                        
                        if sub.id != pillar.submetrics.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("See details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .tint(.miyaPrimary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    private func iconName(for pillarId: String) -> String {
        switch pillarId {
        case "sleep": return "bed.double.fill"
        case "movement": return "figure.walk"
        case "stress": return "heart.fill"
        default: return "chart.bar.fill"
        }
    }
}

private struct VitalitySubmetricRow: View {
    let sub: SubmetricBreakdown
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.label)
                        .font(.caption.bold())
                        .foregroundColor(.miyaTextPrimary)
                    Text(sub.valueText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(String(format: "%.1f", sub.points)) / \(String(format: "%.1f", sub.maxPoints))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    
                    VitalityStatusBadge(status: sub.status)
                }
            }
            
            Text("Target: \(sub.targetText.isEmpty ? "—" : sub.targetText)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let notes = sub.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct VitalityStatusBadge: View {
    let status: VitalityStatus
    
    var body: some View {
        Text(statusText)
            .font(.caption2.bold())
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
    
    private var statusText: String {
        switch status {
        case .optimal: return "Optimal"
        case .ok: return "OK"
        case .low: return "Low"
        case .missing: return "Missing"
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .optimal: return Color.green.opacity(0.15)
        case .ok: return Color.yellow.opacity(0.18)
        case .low: return Color.orange.opacity(0.18)
        case .missing: return Color.gray.opacity(0.18)
        }
    }
    
    private var textColor: Color {
        switch status {
        case .optimal: return .green
        case .ok: return .yellow
        case .low: return .orange
        case .missing: return .gray
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

