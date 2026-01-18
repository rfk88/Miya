//
//  VitalityImportView.swift
//  Miya Health
//
//  Upload vitality CSV during onboarding, compute scores, and save to Supabase
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct VitalityImportView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImporter = false
    @State private var importStatus: String = ""
    @State private var latestScore: VitalityScore?
    @State private var isSaving = false
    @State private var showAlert = false
    
    /// Optional override for saving on behalf of another user (debug tooling).
    /// If nil, saves for the authenticated user (normal behavior).
    let overrideUserId: String?
    
    private let currentStep: Int = 7  // insert after RiskResults (adjust if needed)
    private let totalSteps: Int = 9
    
    init(overrideUserId: String? = nil) {
        self.overrideUserId = overrideUserId
    }
    
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
            allowedContentTypes: [.commaSeparatedText, .plainText, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importStatus)
        }
        #if DEBUG
        .onAppear {
            // Debug-only: compute vitality from a bundled ROOK export (no persistence, no UI changes).
            Task {
                await debugLogRookVitalitySnapshotIfAvailable()
            }
        }
        #endif
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
            
            let ext = url.pathExtension.lowercased()
            
            if ext == "json" {
                // ROOK export JSON simulation (persist snapshot for temporary testing)
                let data = try Data(contentsOf: url)
                let dataset = try JSONDecoder().decode(ROOKDataset.self, from: data)
                
                let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
                let windowRaw = ROOKWindowAggregator.buildWindowRawMetrics(age: age, dataset: dataset)
                let snapshot = VitalityScoringEngine().score(raw: windowRaw)
                
                func pillarScore(_ pillar: VitalityPillar) -> Int {
                    snapshot.pillarScores.first(where: { $0.pillar == pillar })?.score ?? 0
                }
                
                // Map new engine (0–100 pillar scores) into legacy VitalityScore component scales (35/35/30)
                let sleepPoints = Int((Double(pillarScore(.sleep)) * 35.0 / 100.0).rounded())
                let movementPoints = Int((Double(pillarScore(.movement)) * 35.0 / 100.0).rounded())
                let stressPoints = Int((Double(pillarScore(.stress)) * 30.0 / 100.0).rounded())
                
                let legacy = VitalityScore(
                    date: Date(),
                    totalScore: snapshot.totalScore,
                    sleepPoints: sleepPoints,
                    movementPoints: movementPoints,
                    stressPoints: stressPoints
                )

                Task {
                    do {
                        isSaving = true
                        // Save only the "current vitality snapshot" for now.
                        // We tag it as 'manual' so we can exclude it later when ROOK is live.
                        if let target = overrideUserId {
                            try await dataManager.saveVitalitySnapshot(snapshot: snapshot, source: "manual", forUserId: target)
                        } else {
                            try await dataManager.saveVitalitySnapshot(snapshot: snapshot, source: "manual")
                        }

                        // NEW: persist up to last 21 days of daily vitality scores.
                        // IMPORTANT: We allow partial days (e.g., stress-only) so the trend engine can detect
                        // up/down patterns per pillar. The trend engine already handles missing pillars.
                        var dailyRaw = ROOKWindowAggregator.buildDailyRawMetricsByUTCKey(age: age, dataset: dataset)
                        print("ROOK_IMPORT: Built \(dailyRaw.count) daily raw metric entries from JSON")
                        
                        // DEBUG: Shift all dates to last 14 days (latest = today, earliest = 14 days ago)
                        #if DEBUG
                        if !dailyRaw.isEmpty {
                            let dateFormatter = DateFormatter()
                            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            
                            // Find latest date in dataset
                            if let latestDayKey = dailyRaw.map({ $0.dayKey }).sorted().last,
                               let latestDate = dateFormatter.date(from: latestDayKey) {
                                // Calculate offset: shift so latest date becomes today
                                let today = Calendar.current.startOfDay(for: Date())
                                let offsetDays = Calendar.current.dateComponents([.day], from: latestDate, to: today).day ?? 0
                                
                                if offsetDays != 0 {
                                    // Shift all dayKeys by the offset
                                    dailyRaw = dailyRaw.map { item in
                                        guard let originalDate = dateFormatter.date(from: item.dayKey),
                                              let shiftedDate = Calendar.current.date(byAdding: .day, value: offsetDays, to: originalDate) else {
                                            return item
                                        }
                                        let shiftedDayKey = dateFormatter.string(from: shiftedDate)
                                        return (dayKey: shiftedDayKey, raw: item.raw)
                                    }
                                    
                                    // Filter to only keep last 14 days (ending today)
                                    let todayKey = dateFormatter.string(from: today)
                                    let cutoffDate = Calendar.current.date(byAdding: .day, value: -14, to: today)!
                                    let cutoffKey = dateFormatter.string(from: cutoffDate)
                                    dailyRaw = dailyRaw.filter { $0.dayKey >= cutoffKey && $0.dayKey <= todayKey }
                                    
                                    print("ROOK_IMPORT: 🔄 Shifted all dates by \(offsetDays) days, filtered to last 14 days (range: \(cutoffKey) to \(todayKey))")
                                }
                            } else {
                                print("ROOK_IMPORT: ⚠️ Could not parse latest date, skipping date shift")
                            }
                        }
                        #endif
                        
                        let engine = VitalityScoringEngine()
                        // Map per-day raw metrics to per-day snapshots, require:
                        // - total score valid
                        // - at least one pillar present (sleep OR movement OR stress)
                        let dailyTuples: [(dayKey: String, snapshot: VitalitySnapshot)] = dailyRaw.compactMap { day in
                            let snap = engine.score(raw: day.raw)
                            let pillars = snap.pillarScores.filter { (0...100).contains($0.score) }
                            let hasAnyPillar = !pillars.isEmpty
                            guard hasAnyPillar, (0...100).contains(snap.totalScore) else {
                                #if DEBUG
                                if !hasAnyPillar {
                                    print("  ⚠️ Skipped day \(day.dayKey): no valid pillars")
                                } else if !(0...100).contains(snap.totalScore) {
                                    print("  ⚠️ Skipped day \(day.dayKey): invalid total score \(snap.totalScore)")
                                }
                                #endif
                                return nil
                            }
                            return (dayKey: day.dayKey, snapshot: snap)
                        }
                        print("ROOK_IMPORT: Scored \(dailyTuples.count) valid daily snapshots (from \(dailyRaw.count) raw entries)")
                        // Deduplicate by dayKey, keep most recent 21 days
                        let uniqueByDay: [String: VitalitySnapshot] = {
                            var dict: [String: VitalitySnapshot] = [:]
                            for item in dailyTuples {
                                dict[item.dayKey] = item.snapshot
                            }
                            return dict
                        }()
                        let sortedKeys = uniqueByDay.keys.sorted().suffix(21)
                        let finalDaily = sortedKeys.compactMap { key in
                            uniqueByDay[key].map { (dayKey: key, snapshot: $0) }
                        }
                        if !finalDaily.isEmpty {
                            // For debug uploads, clear existing daily rows first to avoid overlapping data
                            let clearFirst = overrideUserId != nil
                            if let target = overrideUserId {
                                try await dataManager.saveDailyVitalityPillarScores(finalDaily, source: "manual", forUserId: target, clearExisting: clearFirst)
                            } else {
                                try await dataManager.saveDailyVitalityPillarScores(finalDaily, source: "manual", clearExisting: clearFirst)
                            }
                            print("ROOK_IMPORT: ✅ saved \(finalDaily.count) daily vitality rows (manual, clearedExisting=\(clearFirst))")
                        } else {
                            print("ROOK_IMPORT: ❌ no_valid_daily_rows (filtered from \(dailyRaw.count) raw entries)")
                        }

                        await MainActor.run {
                            latestScore = legacy
                            importStatus = "✅ Imported ROOK export JSON; vitality \(legacy.totalScore)/100"
                            showAlert = false
                            isSaving = false
                        }
                    } catch {
                        await MainActor.run {
                            importStatus = "Error saving vitality snapshot: \(error.localizedDescription)"
                            showAlert = true
                            isSaving = false
                        }
                    }
                }
                return
            }
            
            // Default: CSV flow (unchanged)
            let content = try String(contentsOf: url, encoding: .utf8)
            var parsed = VitalityCalculator.parseCSV(content: content)
            guard !parsed.isEmpty else {
                importStatus = "No data rows found in CSV."
                showAlert = true
                return
            }
            
            // DEBUG: Shift all dates to last 14 days (latest = today, earliest = 14 days ago)
            #if DEBUG
            if !parsed.isEmpty {
                // Find latest date in dataset
                if let latestDate = parsed.map({ $0.date }).max() {
                    // Calculate offset: shift so latest date becomes today
                    let today = Calendar.current.startOfDay(for: Date())
                    let offsetDays = Calendar.current.dateComponents([.day], from: latestDate, to: today).day ?? 0
                    
                    if offsetDays != 0 {
                        // Shift all dates by the offset
                        parsed = parsed.map { data in
                            guard let shiftedDate = Calendar.current.date(byAdding: .day, value: offsetDays, to: data.date) else {
                                return data
                            }
                            // Create new VitalityData with shifted date
                            return VitalityData(
                                date: shiftedDate,
                                sleepHours: data.sleepHours,
                                restorativeSleepPercent: data.restorativeSleepPercent,
                                sleepEfficiencyPercent: data.sleepEfficiencyPercent,
                                awakePercent: data.awakePercent,
                                steps: data.steps,
                                hrvMs: data.hrvMs,
                                restingHr: data.restingHr
                            )
                        }
                        
                        // Filter to only keep last 14 days (ending today)
                        let cutoffDate = Calendar.current.date(byAdding: .day, value: -14, to: today)!
                        parsed = parsed.filter { $0.date >= cutoffDate && $0.date <= today }
                        
                        print("CSV_IMPORT: 🔄 Shifted all dates by \(offsetDays) days, filtered to last 14 days")
                    }
                } else {
                    print("CSV_IMPORT: ⚠️ Could not find latest date, skipping date shift")
                }
            }
            #endif
            
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

    #if DEBUG
    private func debugLogRookVitalitySnapshotIfAvailable() async {
        // Try to load a ROOK export JSON from the app bundle.
        // Expected resource paths (if added to Copy Bundle Resources):
        // - "Rook Samples/ROOKConnect-Whoop-dataset-v2.json"
        // - "Rook Samples/ROOKConnect-Apple Health-dataset-v2.json"
        let candidates: [(displayName: String, resourceName: String)] = [
            ("WHOOP", "ROOKConnect-Whoop-dataset-v2"),
            ("APPLE", "ROOKConnect-Apple Health-dataset-v2")
        ]
        
        guard let (label, url) = candidates.compactMap({ candidate in
            let u = Bundle.main.url(forResource: candidate.resourceName, withExtension: "json", subdirectory: "Rook Samples")
            return u.map { (candidate.displayName, $0) }
        }).first else {
            print("⚠️ ROOK onboarding debug: No ROOK sample export found in app bundle under 'Rook Samples/'.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let dataset = try JSONDecoder().decode(ROOKDataset.self, from: data)
            
            let age = Calendar.current.dateComponents([.year], from: onboardingManager.dateOfBirth, to: Date()).year ?? 0
            let windowRaw = ROOKWindowAggregator.buildWindowRawMetrics(age: age, dataset: dataset)
            let snapshot = VitalityScoringEngine().score(raw: windowRaw)
            
            print("=== ROOK onboarding vitality (debug) ===")
            print("Source:", label, "| Age:", snapshot.age, "| AgeGroup:", snapshot.ageGroup)
            print("Total:", snapshot.totalScore, "/100")
            for pillar in snapshot.pillarScores {
                print("Pillar:", pillar.pillar, "score:", pillar.score, "/100")
            }
            print("=== End ROOK onboarding vitality (debug) ===")
        } catch {
            print("❌ ROOK onboarding debug: Failed to decode/score ROOK export:", error.localizedDescription)
        }
    }
    #endif
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

