#if DEBUG
import SwiftUI
import SwiftUIX
import Supabase

// MARK: - DEBUG: Add single-day (or range) vitality_scores rows by computing via VitalityScoringEngine

struct DebugAddRecordView: View {
    let members: [FamilyMemberScore]
    let dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedUserId: String = ""
    @State private var selectedName: String = ""
    
    @State private var day: Date = Date()
    @State private var daysToCreate: Int = 1
    
    // Raw inputs (keep minimal; computed through the real engine)
    @State private var sleepHoursText: String = ""
    @State private var stepsText: String = ""
    @State private var movementMinutesText: String = ""
    @State private var hrvMsText: String = ""
    @State private var restingHrText: String = ""
    
    // Age (derived from profile if possible; allow override)
    @State private var derivedAge: Int? = nil
    @State private var isOverridingAge: Bool = false
    @State private var overrideAge: Int = 30
    
    @State private var isSaving: Bool = false
    @State private var statusText: String? = nil
    
    private func utcDayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    private func parseDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Locale-safe parsing: accept both "." and "," decimals.
        let nf = NumberFormatter()
        nf.locale = Locale.current
        nf.numberStyle = .decimal
        if let n = nf.number(from: trimmed) {
            return n.doubleValue
        }
        // Fallback: swap comma->dot
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func parseInt(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
    
    private var ageUsed: Int? {
        if isOverridingAge { return overrideAge }
        return derivedAge
    }
    
    private func computeSnapshot() -> (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown)? {
        guard let age = ageUsed else { return nil }
        
        let raw = VitalityRawMetrics(
            age: age,
            sleepDurationHours: parseDouble(sleepHoursText),
            restorativeSleepPercent: nil,
            sleepEfficiencyPercent: nil,
            awakePercent: nil,
            movementMinutes: parseDouble(movementMinutesText),
            steps: parseInt(stepsText),
            activeCalories: nil,
            hrvMs: parseDouble(hrvMsText),
            hrvType: (parseDouble(hrvMsText) != nil) ? "rmssd" : nil,
            restingHeartRate: parseDouble(restingHrText),
            breathingRate: nil
        )
        
        let engine = VitalityScoringEngine()
        return engine.scoreIfPossible(raw: raw)
    }
    
    private func pill(_ snapshot: VitalitySnapshot, _ pillar: VitalityPillar) -> Int? {
        snapshot.pillarScores.first(where: { $0.pillar == pillar })?.score
    }
    
    private func computeDerivedAgeIfPossible(userId: String) async {
        struct DOBRow: Decodable { let date_of_birth: String? }
        do {
            let supabase = SupabaseConfig.client
            let rows: [DOBRow] = try await supabase
                .from("user_profiles")
                .select("date_of_birth")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            guard let s = rows.first?.date_of_birth, !s.isEmpty else {
                await MainActor.run { derivedAge = nil }
                return
            }
            
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            guard let dob = df.date(from: s) else {
                await MainActor.run { derivedAge = nil }
                return
            }
            
            let cal = Calendar(identifier: .gregorian)
            let now = Date()
            let years = cal.dateComponents([.year], from: dob, to: now).year ?? 30
            await MainActor.run {
                derivedAge = max(0, years)
                // keep overrideAge reasonable if user toggles override on
                if overrideAge <= 0 { overrideAge = max(0, years) }
            }
        } catch {
            await MainActor.run { derivedAge = nil }
        }
    }
    
    private func seedDefaultMemberIfNeeded() {
        guard selectedUserId.isEmpty else { return }
        if let me = members.first(where: { $0.isMe }), let uid = me.userId {
            selectedUserId = uid
            selectedName = me.name
        } else if let first = members.first(where: { !$0.isPending && $0.userId != nil }), let uid = first.userId {
            selectedUserId = uid
            selectedName = first.name
        }
    }
    
    var body: some View {
        Form {
            Section {
                Picker("Member", selection: $selectedUserId) {
                    ForEach(members.filter { !$0.isPending && $0.userId != nil }, id: \.userId) { m in
                        Text(m.name).tag(m.userId ?? "")
                    }
                }
                .onChange(of: selectedUserId) { _, newId in
                    if let m = members.first(where: { $0.userId == newId }) {
                        selectedName = m.name
                    }
                    Task { await computeDerivedAgeIfPossible(userId: newId) }
                }
            } header: {
                Text("Target")
            }
            
            Section {
                DatePicker("Start day", selection: $day, displayedComponents: [.date])
                Stepper("Days to create: \(daysToCreate)", value: $daysToCreate, in: 1...14)
                Button("Quick: 7 days") { daysToCreate = 7 }
                    .foregroundColor(.miyaPrimary)
            } header: {
                Text("Dates (UTC day keys)")
            } footer: {
                Text("This writes rows to vitality_scores using UTC day keys (YYYY-MM-DD). Weekly badges use the last 7 completed UTC days (ending yesterday).")
            }
            
            Section {
                Toggle("Override age", isOn: $isOverridingAge)
                if isOverridingAge {
                    Stepper("Age: \(overrideAge)", value: $overrideAge, in: 0...110)
                } else {
                    HStack {
                        Text("Age used")
                Spacer()
                        Text(derivedAge.map(String.init) ?? "Missing in profile")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Age (must match scoring)")
            } footer: {
                Text("We compute scores using the same age-specific schema as production. If date of birth is missing, enable override.")
            }
            
            Section {
                TextField("Sleep duration (hours)", text: $sleepHoursText)
                    .keyboardType(.decimalPad)
                TextField("Steps (count)", text: $stepsText)
                    .keyboardType(.numberPad)
                TextField("Movement minutes (optional)", text: $movementMinutesText)
                    .keyboardType(.decimalPad)
                TextField("HRV ms (optional)", text: $hrvMsText)
                    .keyboardType(.decimalPad)
                TextField("Resting HR (optional)", text: $restingHrText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Raw inputs (we compute pillars from these)")
            } footer: {
                Text("Do not type pillar scores here. Pillars/total are computed via VitalityScoringEngine to match production.")
            }
            
            Section {
                if let scored = computeSnapshot() {
                    let snap = scored.snapshot
                    HStack {
                        Text("Total")
                        Spacer()
                        Text("\(snap.totalScore)/100")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    HStack {
                        Text("Sleep")
                        Spacer()
                        Text("\(pill(snap, .sleep) ?? 0)/100")
                    }
                    HStack {
                        Text("Movement")
                        Spacer()
                        Text("\(pill(snap, .movement) ?? 0)/100")
                    }
                    HStack {
                        Text("Recovery")
                        Spacer()
                        Text("\(pill(snap, .stress) ?? 0)/100")
                    }
                } else {
                    Text("Enter enough data for at least 2 pillars (e.g., sleep + steps/movement or sleep + HRV/resting HR).")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Preview (computed)")
            }
            
            Section {
                if let statusText {
                    Text(statusText)
                        .foregroundColor(.secondary)
                }
                
                        Button {
                    guard !selectedUserId.isEmpty else { return }
                    guard let scored = computeSnapshot() else {
                        statusText = "Not enough data to compute a valid vitality snapshot (need 2 pillars)."
                        return
                    }
                    
                    isSaving = true
                    statusText = nil
                    
                    Task {
                        let start = day
                        let cal = Calendar(identifier: .gregorian)
                        
                        var rows: [(dayKey: String, snapshot: VitalitySnapshot)] = []
                        for i in 0..<daysToCreate {
                            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
                            rows.append((dayKey: utcDayKey(for: d), snapshot: scored.snapshot))
                        }
                        
                        #if DEBUG
                        let firstKey = rows.first?.dayKey ?? "nil"
                        let lastKey = rows.last?.dayKey ?? "nil"
                        print("DEBUG_ADD_RECORD_SAVE: userId=\(selectedUserId) days=\(rows.count) range=\(firstKey)→\(lastKey)")
                        #endif
                        
                        do {
                            try await dataManager.saveDailyVitalityPillarScores(
                                rows,
                                source: "manual",
                                forUserId: selectedUserId,
                                clearExisting: false
                            )
                            await MainActor.run {
                                isSaving = false
                                statusText = "Saved \(daysToCreate) day(s) for \(selectedName.isEmpty ? "member" : selectedName)."
                            }
                            // Dismiss after a short beat so the user sees success
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            await MainActor.run { dismiss() }
                        } catch {
                            await MainActor.run {
                                isSaving = false
                                statusText = "Save failed: \(error.localizedDescription)"
                            }
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ActivityIndicator()
                                .animated(true)
                                .style(.regular)
                        } else {
                            Text("Save record(s)")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Add record (debug)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedDefaultMemberIfNeeded()
            if !selectedUserId.isEmpty {
                Task { await computeDerivedAgeIfPossible(userId: selectedUserId) }
            }
        }
    }
}

// MARK: - Debug Upload Picker (choose which family member to apply the dataset to)

struct DebugUploadPickerView: View {
    let members: [FamilyMemberScore]
    let onboardingManager: OnboardingManager
    let dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Text("Choose who this dataset belongs to. This will write vitality history for that user_id so trends/notifications can be tested without logging in/out.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            
            Section("Family members") {
                ForEach(members.filter { $0.userId != nil }) { m in
                    NavigationLink {
                        VitalityImportView(overrideUserId: m.userId)
                            .environmentObject(onboardingManager)
                            .environmentObject(dataManager)
                    } label: {
                        HStack {
                            Text(m.isMe ? "\(m.name) (Me)" : m.name)
                            Spacer()
                            Text(m.initials)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Upload dataset (debug)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}
#endif
