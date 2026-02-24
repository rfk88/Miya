import SwiftUI
import Foundation

struct ArloChatView: View {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }

        let id = UUID()
        let role: Role
        let text: String
        let date: Date = Date()
        var isError: Bool = false
    }

    // ✅ NEW: required for get_arlo_facts
    let familyId: UUID

    let firstName: String
    let openingLine: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    @State private var isSending: Bool = false
    @State private var showInlineError: Bool = false

    // ✅ NEW: facts state
    @State private var facts: ArloChatAPI.Facts?
    @State private var isLoadingFacts: Bool = true
    @State private var factsLoadError: String?
    
    // ✅ NEW: Control pill visibility
    @State private var showPills: Bool = false
    
    private enum OpenerBucket: String {
        case up
        case steady
        case down
        case lowData
    }
    
    private struct OpenerTemplate {
        let id: String
        let text: String
    }
    
    private static let openerHistoryLimit = 2
    private static let openerTemplates: [OpenerBucket: [OpenerTemplate]] = [
        .up: [
            OpenerTemplate(
                id: "up_1",
                text: """
                Hey {{firstName}} — great momentum this week.
                
                Your family vitality is {{trendSummary}}, led by {{mainDriver}}.
                Want me to help you lock this in for next week?
                """
            ),
            OpenerTemplate(
                id: "up_2",
                text: """
                Hi {{firstName}} — quick check-in.
                
                Your family is {{trendSummary}}, and {{mainDriver}} is the biggest reason.
                I can show you the easiest next win from here.
                """
            ),
            OpenerTemplate(
                id: "up_3",
                text: """
                Hey {{firstName}} — nice to see progress.
                
                Right now things are {{trendSummary}}, mostly because {{mainDriver}}.
                Want a quick “keep doing this” plan?
                """
            )
        ],
        .steady: [
            OpenerTemplate(
                id: "steady_1",
                text: """
                Hey {{firstName}} — your family looks {{trendSummary}}.
                
                The main signal is {{mainDriver}}.
                I can help turn this steady week into an even better one.
                """
            ),
            OpenerTemplate(
                id: "steady_2",
                text: """
                Hi {{firstName}} — your family is {{trendSummary}} this week.
                
                Biggest driver right now: {{mainDriver}}.
                Want me to point out where one small change could make the biggest difference?
                """
            ),
            OpenerTemplate(
                id: "steady_3",
                text: """
                Hey {{firstName}} — quick update.
                
                Overall things are {{trendSummary}}, with {{mainDriver}} standing out.
                I can break this into what’s working and what to improve first.
                """
            )
        ],
        .down: [
            OpenerTemplate(
                id: "down_1",
                text: """
                Hi {{firstName}} — quick check-in.
                
                Your family vitality is {{trendSummary}}, and {{mainDriver}} is the main reason.
                No stress — I can help with a simple reset plan.
                """
            ),
            OpenerTemplate(
                id: "down_2",
                text: """
                Hey {{firstName}} — this week has been a bit tougher.
                
                Right now your trend is {{trendSummary}}, mainly linked to {{mainDriver}}.
                Want the easiest first step to turn this around?
                """
            )
        ],
        .lowData: [
            OpenerTemplate(
                id: "low_data_1",
                text: """
                Hey {{firstName}} — I’m still building your full family picture.
                
                So far, {{positiveHighlight}}.
                I can still help you with simple next steps while more data comes in.
                """
            ),
            OpenerTemplate(
                id: "low_data_2",
                text: """
                Hi {{firstName}} — we have partial data right now.
                
                Early signal: {{positiveHighlight}}.
                Want me to guide you with a low-risk plan for this week?
                """
            )
        ]
    ]

    var body: some View {
        ZStack {
            // ✅ Make the *actual chat background* the Miya gradient (full screen)
            LinearGradient(
                colors: [
                    Color.miyaPrimary.opacity(0.65),
                    Color.miyaPrimary.opacity(0.22),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft glow layer
            RadialGradient(
                colors: [
                    Color.miyaPrimary.opacity(0.26),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                // ✅ Optional lightweight loading row (facts only)
                if isLoadingFacts && messages.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading family insights…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(messages) { msg in
                                VStack(alignment: msg.role == .assistant ? .leading : .trailing, spacing: 8) {
                                    ChatBubble(role: msg.role, text: msg.text)
                                    
                                    // Pills anchored to LAST assistant message only
                                    if msg.role == .assistant,
                                       msg.id == messages.last?.id,
                                       showPills,
                                       let facts,
                                       !facts.suggestedPills.isEmpty {
                                        SuggestedPillsRow(pills: facts.suggestedPills) { pill in
                                            handlePillTap(pill)
                                        }
                                        .padding(.leading, 44)  // Indent to align with bubble
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .id(msg.id)
                            }

                            if let err = factsLoadError, messages.isEmpty {
                                InlineErrorBanner(title: err, actionTitle: "Try again?") {
                                    factsLoadError = nil
                                    Task { await loadFactsAndSeedOpening() }
                                }
                                .id("facts_error")
                            }

                            if showInlineError {
                                InlineErrorBanner(title: "Failed to get response.", actionTitle: "Try again?") {
                                    showInlineError = false
                                    messages.append(.init(role: .assistant, text: "No worries—try again. What do you want to look at first: sleep, movement, or recovery?"))
                                }
                                .id("inline_error")
                            }

                            if isSending {
                                HStack {
                                    Spacer(minLength: 40)
                                    TypingBubble()
                                    Spacer()
                                }
                                .id("typing")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages) { _, _ in
                        guard let last = messages.last else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: showInlineError) { _, newVal in
                        if newVal {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("inline_error", anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .task {
            // ✅ Load facts + seed deterministic opening message once
            if messages.isEmpty {
                await loadFactsAndSeedOpening()
            }
        }
    }

    // MARK: - Facts loading + seed opening

    @MainActor
    private func seedFallbackOpening() {
        let greetingName = firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "there" : firstName
        let opening = "Hey \(greetingName) — \(openingLine). What would you like help with today?"
        messages = [.init(role: .assistant, text: opening)]
    }

    private func loadFactsAndSeedOpening() async {
        await MainActor.run {
            isLoadingFacts = true
            factsLoadError = nil
        }

        do {
            let loaded = try await ArloChatAPI.fetchFacts(familyId: familyId)

            await MainActor.run {
                facts = loaded
                isLoadingFacts = false

                let opener = buildRotatingOpener(from: loaded)
                messages = [.init(role: .assistant, text: opener)]
                showPills = true  // Show pills after opening message
            }
        } catch {
            await MainActor.run {
                isLoadingFacts = false
                factsLoadError = "Couldn’t load family insights."
                // fallback to current behaviour so the UI isn’t blocked
                seedFallbackOpening()
            }
        }
    }
    
    // MARK: - Rotating opener selection (local device memory)
    
    private func buildRotatingOpener(from facts: ArloChatAPI.Facts) -> String {
        let bucket = openerBucket(from: facts)
        let templates = Self.openerTemplates[bucket] ?? []
        guard !templates.isEmpty else {
            return [facts.openerHeadline, facts.openerWhy, facts.openerHook]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        }
        
        let recentIds = Set(loadRecentTemplateIDs(for: bucket))
        let eligible = templates.filter { !recentIds.contains($0.id) }
        let chosen = (eligible.isEmpty ? templates : eligible).randomElement() ?? templates[0]
        saveRecentTemplateID(chosen.id, for: bucket)
        
        let filled = chosen.text
            .replacingOccurrences(of: "{{firstName}}", with: resolvedGreetingName())
            .replacingOccurrences(of: "{{trendSummary}}", with: trendSummary(from: facts))
            .replacingOccurrences(of: "{{mainDriver}}", with: mainDriverSummary(from: facts))
            .replacingOccurrences(of: "{{positiveHighlight}}", with: positiveHighlight(from: facts))
        
        return filled.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func openerBucket(from facts: ArloChatAPI.Facts) -> OpenerBucket {
        if facts.membersWithData == 0 || facts.dataCoverageDays < 3 {
            return .lowData
        }
        let delta = facts.familyVitalityDelta ?? 0
        if delta >= 2 { return .up }
        if delta <= -2 { return .down }
        return .steady
    }
    
    private func trendSummary(from facts: ArloChatAPI.Facts) -> String {
        let delta = facts.familyVitalityDelta ?? 0
        if delta >= 2 { return "up this week" }
        if delta <= -2 { return "down this week" }
        return "fairly steady this week"
    }
    
    private func mainDriverSummary(from facts: ArloChatAPI.Facts) -> String {
        let candidates: [(name: String, value: Int)] = [
            ("recovery", facts.recoveryContribution),
            ("activity", facts.movementContribution),
            ("sleep", facts.sleepContribution)
        ]
        guard let top = candidates.max(by: { abs($0.value) < abs($1.value) }) else {
            return "mixed signals across sleep, activity, and recovery"
        }
        if top.value > 0 {
            return "\(top.name) improving"
        }
        if top.value < 0 {
            return "\(top.name) drifting"
        }
        return "\(top.name) staying stable"
    }
    
    private func positiveHighlight(from facts: ArloChatAPI.Facts) -> String {
        if let improved = facts.memberHighlights.mostImprovedMemberName, !improved.isEmpty {
            return "\(improved) showed the strongest improvement"
        }
        if let sleepLeader = facts.memberHighlights.bestSleepMemberName, !sleepLeader.isEmpty {
            return "\(sleepLeader) led sleep this week"
        }
        if let recoveryLeader = facts.memberHighlights.bestRecoveryMemberName, !recoveryLeader.isEmpty {
            return "\(recoveryLeader) led recovery this week"
        }
        return "there are positive signs we can build on"
    }
    
    private func resolvedGreetingName() -> String {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
    }
    
    private func openerHistoryKey(for bucket: OpenerBucket) -> String {
        "arlo.opener.history.\(familyId.uuidString.lowercased()).\(bucket.rawValue)"
    }
    
    private func loadRecentTemplateIDs(for bucket: OpenerBucket) -> [String] {
        UserDefaults.standard.stringArray(forKey: openerHistoryKey(for: bucket)) ?? []
    }
    
    private func saveRecentTemplateID(_ id: String, for bucket: OpenerBucket) {
        var history = loadRecentTemplateIDs(for: bucket)
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        if history.count > Self.openerHistoryLimit {
            history = Array(history.prefix(Self.openerHistoryLimit))
        }
        UserDefaults.standard.set(history, forKey: openerHistoryKey(for: bucket))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.black.opacity(0.14))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.miyaPrimary.opacity(0.95), Color.miyaPrimary.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Text("M")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Miya")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            Divider().opacity(0.9)
        }
        .background(
            Color(.systemBackground).opacity(0.72)
                .background(.ultraThinMaterial)
        )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        let disabled = isSendDisabled

        return HStack(spacing: 12) {
            inputField
            sendButton(disabled: disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(inputTrayBackground)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var isSendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            TextField("Ask Miya anything…", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(inputFieldBackground)
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 10)
        .shadow(color: Color.miyaPrimary.opacity(0.10), radius: 26, x: 0, y: 14)
    }

    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
    }

    private func apiRole(for role: ChatMessage.Role) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }

    private func sendButton(disabled: Bool) -> some View {
        Button { send() } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(sendButtonBackground)
                .clipShape(Circle())
                .overlay(sendButtonStroke)
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
                .shadow(color: Color.miyaPrimary.opacity(0.18), radius: 24, x: 0, y: 14)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var sendButtonBackground: some View {
        LinearGradient(
            colors: [Color.miyaPrimary.opacity(0.98), Color.miyaPrimary.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sendButtonStroke: some View {
        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
    }

    private var inputTrayBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(.systemBackground).opacity(0.62))
            .background(.ultraThinMaterial)
            .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 14)
    }

    // MARK: - Send (uses current messages)
    
    private func handlePillTap(_ pill: String) {
        showPills = false  // Hide pills immediately
        messages.append(.init(role: .user, text: pill))
        showInlineError = false
        isSending = true
        
        Task {
            await sendWithCurrentMessages()
        }
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        showPills = false  // Hide pills when user sends message
        messages.append(.init(role: .user, text: trimmed))
        inputText = ""
        isInputFocused = false

        isSending = true
        showInlineError = false

        Task {
            await sendWithCurrentMessages()
        }
    }

    private func sendWithCurrentMessages() async {
        do {
            let payloadMessages: [ArloChatAPI.APIMessage] = messages
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { msg in
                    ArloChatAPI.APIMessage(
                        role: apiRole(for: msg.role),
                        content: msg.text
                    )
                }

            let reply = try await ArloChatAPI.send(
                messages: payloadMessages,
                firstName: firstName,
                openingLine: openingLine
            )

            await MainActor.run {
                isSending = false
                messages.append(.init(role: .assistant, text: reply))
                showPills = true  // Show pills after each assistant message
            }
        } catch {
            await MainActor.run {
                isSending = false
                showInlineError = true
            }
        }
    }
}

// MARK: - Suggested pills UI

private struct SuggestedPillsRow: View {
    let pills: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pills, id: \.self) { pill in
                    Button {
                        onTap(pill)
                    } label: {
                        Text(pill)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.miyaPrimary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.miyaPrimary.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    ArloChatView(
        familyId: UUID(uuidString: "64dd7be3-4a33-4347-b9cc-9b41a2170451")!,
        firstName: "Josh",
        openingLine: "things look generally on track for your family right now"
    )
}

private struct ChatBubble: View {
    let role: ArloChatView.ChatMessage.Role
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if role == .assistant {
                avatar
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.miyaPrimary.opacity(0.95), Color.miyaPrimary.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )

            Text("M")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var bubble: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(role == .assistant ? .primary : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Group {
                    if role == .assistant {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.miyaPrimary.opacity(0.95), Color.miyaPrimary.opacity(0.70)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .shadow(color: Color.black.opacity(role == .assistant ? 0.05 : 0.10), radius: 10, x: 0, y: 6)
    }
}

private struct InlineErrorBanner: View {
    let title: String
    let actionTitle: String
    let onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("\(title) \(actionTitle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TypingBubble: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6)
            Circle().frame(width: 6, height: 6)
            Circle().frame(width: 6, height: 6)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground).opacity(0.70))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
