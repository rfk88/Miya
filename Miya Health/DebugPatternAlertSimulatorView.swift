#if DEBUG
import SwiftUI
import Supabase

/// DEBUG-only tool to simulate ROOK webhook events so server-side scoring + pattern alerts run.
///
/// This avoids needing real users or curl. It POSTs to:
///   <supabaseURL>/functions/v1/rook
///
/// Note: This will write rows into `wearable_daily_metrics` for the selected user and may affect their scores.
/// Use a dedicated test account whenever possible.
struct DebugPatternAlertSimulatorView: View {
    let members: [FamilyMemberScore]
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    enum Scenario: String, CaseIterable, Identifiable {
        case stepsDrop = "Steps drop"
        case sleepDrop = "Sleep drop"
        case hrvDrop = "HRV drop"
        case restingHrRise = "Resting HR rise"

        var id: String { rawValue }
    }

    @State private var selectedMemberId: String = ""
    @State private var scenario: Scenario = .stepsDrop
    @State private var baselineDays: Int = 7
    @State private var declineDays: Int = 7
    @State private var recoveryDays: Int = 3
    @State private var startOffsetDays: Int = 5
    @State private var addNoise: Bool = true
    @State private var noisePercent: Double = 0.05  // ±5%
    @State private var addGaps: Bool = false
    @State private var gapEveryNDays: Int = 7
    @State private var useAutoWindow: Bool = true  // auto-generate 10 contiguous days ending today
    @State private var isRunning: Bool = false
    @State private var progressText: String = ""
    @State private var lastError: String? = nil
    @State private var verifyText: String = ""
    @State private var dobWarning: String? = nil

    private var eligibleMembers: [FamilyMemberScore] {
        members.filter { $0.userId != nil }
    }

    private var selectedUserId: String? {
        if let hit = eligibleMembers.first(where: { $0.userId == selectedMemberId }) {
            return hit.userId
        }
        return nil
    }

    private var rookEndpointURL: URL? {
        guard let base = URL(string: SupabaseConfig.supabaseURL) else { return nil }
        return base.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent("rook")
    }

    var body: some View {
        Form {
            Section("Test account") {
                if eligibleMembers.isEmpty {
                    Text("No members with userId available.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Member", selection: $selectedMemberId) {
                        ForEach(eligibleMembers) { m in
                            Text("\(m.name) (\(m.userId?.prefix(6) ?? ""))").tag(m.userId ?? "")
                        }
                    }
                }

                Text("Tip: use a dedicated test account with no real wearable data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Scenario") {
                Picker("Type", selection: $scenario) {
                    ForEach(Scenario.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                Stepper("Baseline days: \(baselineDays)", value: $baselineDays, in: 7...21)
                Stepper("Decline days: \(declineDays)", value: $declineDays, in: 3...21)
                Stepper("Recovery days: \(recoveryDays)", value: $recoveryDays, in: 0...7)
                Stepper("Write days in the past: \(startOffsetDays)", value: $startOffsetDays, in: 0...3650, step: 30)
                Text("Set this to 365+ if the member already has real wearable data. It avoids collisions because our merge logic takes the daily MAX across sources.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Toggle("Add small noise (±\(Int(noisePercent * 100))%)", isOn: $addNoise)
                if addNoise {
                    Slider(value: $noisePercent, in: 0...0.15, step: 0.01) {
                        Text("Noise %")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("15%")
                    }
                }
                
                Toggle("Skip some days (gaps)", isOn: $addGaps)
                if addGaps {
                    Stepper("Skip every \(gapEveryNDays)th day", value: $gapEveryNDays, in: 4...14)
                }

                Toggle("Auto window (10 days end today)", isOn: $useAutoWindow)
                    .onChange(of: useAutoWindow) { enabled in
                        if enabled {
                            baselineDays = 7
                            declineDays = 3
                            recoveryDays = 0
                            startOffsetDays = 0
                            addGaps = false
                            addNoise = true
                        }
                    }
            }

            Section("Run") {
                if let url = rookEndpointURL {
                    Text("Endpoint: \(url.absoluteString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Endpoint: (invalid Supabase URL)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await runSimulation() }
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Simulating…")
                        }
                    } else {
                        Text("Run simulation")
                    }
                }
                .disabled(isRunning || selectedUserId == nil || rookEndpointURL == nil)

                if !progressText.isEmpty {
                    Text(progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let dobWarning {
                    Text(dobWarning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("What to check") {
                Text("This writes: 1) wearable_daily_metrics (raw), 2) vitality_scores (computed), 3) triggers pattern_alert_state evaluation. After it completes, refresh the dashboard to see notifications appear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                if !verifyText.isEmpty {
                    Text(verifyText)
                        .font(.caption)
                        .foregroundStyle(verifyText.contains("found") ? .green : .orange)
                }
            }
        }
        .navigationTitle("Simulate pattern alerts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            if selectedMemberId.isEmpty {
                selectedMemberId = eligibleMembers.first?.userId ?? ""
            }
        }
    }

    private func runSimulation() async {
        guard let userId = selectedUserId else { return }
        guard let url = rookEndpointURL else { return }

        lastError = nil
        verifyText = ""
        dobWarning = nil
        isRunning = true
        defer { isRunning = false }

        // Auto window: force a contiguous 10-day window ending today
        if useAutoWindow {
            baselineDays = 7
            declineDays = 3
            recoveryDays = 0
            startOffsetDays = 0
            addGaps = false
        }

        // Optional: check DOB presence (scoring needs age)
        await checkDobForUser(userId: userId)

        let total = baselineDays + declineDays
        let recoveryStartIndex = total
        let fullTotal = total + recoveryDays
        let end = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let shiftedEnd = Calendar(identifier: .gregorian).date(byAdding: .day, value: -startOffsetDays, to: end) ?? end
        guard let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -(fullTotal - 1), to: shiftedEnd) else { return }

        func dayKey(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }

        for i in 0..<fullTotal {
            guard let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: start) else { continue }
            let key = dayKey(d)

            if addGaps, gapEveryNDays > 0, (i + 1) % gapEveryNDays == 0 {
                continue
            }

            let phase: Phase
            if i < baselineDays {
                phase = .baseline
            } else if i < total {
                phase = .decline
            } else {
                phase = .recovery
            }

            let payload: [String: Any] = buildPayload(userId: userId, metricDate: key, phase: phase)

            progressText = "Sending day \(i + 1)/\(fullTotal) (\(key))…"
            do {
                try await postJSON(url: url, payload: payload)
            } catch {
                lastError = "Failed on \(key): \(error.localizedDescription)"
                break
            }
        }

        progressText = "Writing vitality scores..."
        
        // Write vitality_scores directly so dashboard can read them (bypasses scoring pipeline)
        await writeVitalityScores(userId: userId, start: start, fullTotal: fullTotal, dayKey: dayKey)
        
        progressText = "Triggering pattern evaluation..."
        
        // Trigger pattern evaluation by posting one more webhook call
        let evalDate = dayKey(shiftedEnd)
        do {
            try await postJSON(url: url, payload: ["user_id": userId, "metric_date": evalDate, "source": "debug", "steps": 1])
        } catch {
            lastError = "Pattern eval trigger failed: \(error.localizedDescription)"
        }
        
        progressText = "Done. Refresh the dashboard, then check Supabase table `pattern_alert_state`."

        // Quick verification: count rows we just wrote into wearable_daily_metrics
        await verifyInserts(userId: userId, startDate: dayKey(start), endDate: dayKey(shiftedEnd))
    }
    
    private func writeVitalityScores(userId: String, start: Date, fullTotal: Int, dayKey: (Date) -> String) async {
        let supabase = SupabaseConfig.client
        
        for i in 0..<fullTotal {
            guard let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: start) else { continue }
            let key = dayKey(d)
            
            if addGaps, gapEveryNDays > 0, (i + 1) % gapEveryNDays == 0 {
                continue
            }
            
            let phase: Phase
            if i < baselineDays {
                phase = .baseline
            } else if i < (baselineDays + declineDays) {
                phase = .decline
            } else {
                phase = .recovery
            }
            
            // Mock pillar scores based on scenario + phase
            let (sleep, movement, stress) = mockPillarScores(for: scenario, phase: phase)
            let total = Int((Double(sleep) + Double(movement) + Double(stress)) / 3.0)
            
            do {
                try await supabase
                    .from("vitality_scores")
                    .upsert([
                        "user_id": AnyJSON.string(userId),
                        "score_date": AnyJSON.string(key),
                        "total_score": AnyJSON.integer(total),
                        "vitality_sleep_pillar_score": AnyJSON.integer(sleep),
                        "vitality_movement_pillar_score": AnyJSON.integer(movement),
                        "vitality_stress_pillar_score": AnyJSON.integer(stress),
                        // Must satisfy DB constraint vitality_scores_source_check.
                        // Keep this aligned with server scoring pipeline values.
                        "source": AnyJSON.string("wearable"),
                        "schema_version": AnyJSON.string("v1"),
                        "computed_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
                    ], onConflict: "user_id,score_date")
                    .execute()
            } catch {
                #if DEBUG
                print("⚠️ Simulator: failed to write vitality_scores for \(key): \(error)")
                #endif
            }
        }
    }

    // Check if user_profiles has DOB; if missing, scoring will be skipped server-side.
    private func checkDobForUser(userId: String) async {
        do {
            let supabase = SupabaseConfig.client
            struct Row: Decodable { let date_of_birth: String? }
            let rows: [Row] = try await supabase
                .from("user_profiles")
                .select("date_of_birth")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            if rows.first?.date_of_birth == nil || rows.first?.date_of_birth?.isEmpty == true {
                await MainActor.run {
                    dobWarning = "Warning: user has no date_of_birth; server scoring may skip age-based scoring. Add DOB or rely on direct vitality_scores writes."
                }
            }
        } catch {
            await MainActor.run {
                dobWarning = "Warning: could not check DOB (\(error.localizedDescription))."
            }
        }
    }
    
    private func mockPillarScores(for scenario: Scenario, phase: Phase) -> (sleep: Int, movement: Int, stress: Int) {
        // Return pillar scores (0-100) based on scenario
        // Affected pillar drops in decline phase, others stay high
        switch scenario {
        case .stepsDrop, .sleepDrop:
            let sleepScore = (scenario == .sleepDrop) ?
                (phase == .baseline ? 85 : (phase == .decline ? 55 : 87)) : 85
            let movementScore = (scenario == .stepsDrop) ?
                (phase == .baseline ? 85 : (phase == .decline ? 55 : 87)) : 85
            return (sleepScore, movementScore, 85)
        case .hrvDrop, .restingHrRise:
            let stressScore = phase == .baseline ? 85 : (phase == .decline ? 55 : 87)
            return (85, 85, stressScore)
        }
    }

    private enum Phase {
        case baseline, decline, recovery
    }

    private func buildPayload(userId: String, metricDate: String, phase: Phase) -> [String: Any] {
        // IMPORTANT:
        // - The webhook reads both user_id and userId; we send user_id.
        // - Date is parsed from metric_date.
        // - We set a stable debug source so re-running overwrites per day (no mergeMax masking).
        var payload: [String: Any] = [
            "user_id": userId,
            "metric_date": metricDate,
            "source": "debug"
        ]

        func withNoise(_ value: Double) -> Double {
            guard addNoise else { return value }
            let factor = 1.0 + Double.random(in: -noisePercent...noisePercent)
            return max(0, value * factor)
        }

        switch scenario {
        case .stepsDrop:
            let base = 8000.0
            let low = 5000.0
            let rec = 8200.0
            payload["steps"] = withNoise(phase == .baseline ? base : (phase == .decline ? low : rec))
        case .sleepDrop:
            // Webhook expects seconds, then converts to minutes.
            let base = 8.0 * 3600.0
            let low = 6.0 * 3600.0
            let rec = 8.2 * 3600.0
            payload["sleep_duration_seconds_int"] = Int(withNoise(phase == .baseline ? base : (phase == .decline ? low : rec)))
        case .hrvDrop:
            let base = 60.0
            let low = 45.0
            let rec = 62.0
            payload["hrv_ms"] = withNoise(phase == .baseline ? base : (phase == .decline ? low : rec))
        case .restingHrRise:
            let base = 55.0
            let high = 62.0
            let rec = 54.0
            payload["resting_hr"] = withNoise(phase == .baseline ? base : (phase == .decline ? high : rec))
        }

        return payload
    }

    private func postJSON(url: URL, payload: [String: Any]) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Provide anon key headers in case the function is locked down.
        req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "DebugPatternAlertSimulatorView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        if http.statusCode < 200 || http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DebugPatternAlertSimulatorView", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
    }

    // Verify rows landed in wearable_daily_metrics for the user/date window
    private func verifyInserts(userId: String, startDate: String, endDate: String) async {
        do {
            let supabase = SupabaseConfig.client
            struct Row: Decodable { let metric_date: String? }
            let rows: [Row] = try await supabase
                .from("wearable_daily_metrics")
                .select("metric_date")
                .eq("user_id", value: userId)
                .gte("metric_date", value: startDate)
                .lte("metric_date", value: endDate)
                .execute()
                .value

            let dates = rows.compactMap { $0.metric_date }
            if dates.isEmpty {
                await MainActor.run {
                    verifyText = "No wearable_daily_metrics rows found for user in \(startDate)...\(endDate). Check function/RLS/userId/startOffset."
                }
            } else {
                await MainActor.run {
                    verifyText = "Inserted \(dates.count) wearable_daily_metrics rows (\(dates.first ?? "") … \(dates.last ?? ""))."
                }
            }
        } catch {
            await MainActor.run {
                verifyText = "Verification failed: \(error.localizedDescription)"
            }
        }
    }
}

#endif

