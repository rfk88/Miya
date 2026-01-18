import Foundation
import SwiftUI
import Supabase

// MARK: - Missing Wearable Notification Model

struct MissingWearableNotification: Identifiable {
    let id: String // "missing_wearable_\(userId)_\(daysStale)"
    let memberName: String
    let memberUserId: String?
    let memberInitials: String
    let daysStale: Int // 3 or 7
    let lastUpdated: Date?
    
    var severity: MissingWearableSeverity {
        daysStale >= 7 ? .critical : .warning
    }
    
    var title: String {
        if daysStale >= 7 {
            return "\(memberName) · No data for 7 days"
        } else {
            return "\(memberName) · No data for 3 days"
        }
    }
    
    var body: String {
        if daysStale >= 7 {
            return "We haven't received wearable data from \(memberName) in 7 days. The family is missing them at Miya!"
        } else {
            return "We haven't received wearable data from \(memberName) in 3 days. Let's check in!"
        }
    }
}

enum MissingWearableSeverity {
    case warning  // 3 days
    case critical // 7 days
    
    var color: Color {
        switch self {
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.circle.fill"
        }
    }
}

enum MessagePlatform {
    case whatsapp
    case imessage
}

// MARK: - Missing Wearable Detail Sheet

struct MissingWearableDetailSheet: View {
    let notification: MissingWearableNotification
    let onDismiss: () -> Void
    let onSendMessage: (String, MessagePlatform) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showMessageTemplates = false
    @State private var suggestedMessages: [(label: String, text: String)] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(notification.severity.color.opacity(0.15))
                                    .frame(width: 50, height: 50)
                                Image(systemName: notification.severity.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(notification.severity.color)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notification.title)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.miyaTextPrimary)
                                
                                Text("\(notification.daysStale) days without data")
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                    
                    // What's happening
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What's happening")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text(notification.body)
                            .font(.system(size: 15))
                            .foregroundColor(.miyaTextPrimary)
                            .lineSpacing(4)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                    
                    // Reach Out Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reach Out")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.miyaTextPrimary)
                                Text("Send a message to \(notification.memberName)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.miyaTextSecondary)
                            }
                            
                            Spacer()
                        }
                        
                        Button {
                            Task {
                                await generateSuggestedMessages()
                                showMessageTemplates = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Send a message")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Missing Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMessageTemplates) {
                MissingWearableMessageSheet(
                    notification: notification,
                    suggestedMessages: suggestedMessages,
                    onSendMessage: { message, platform in
                        onSendMessage(message, platform)
                        showMessageTemplates = false
                    }
                )
            }
        }
    }
    
    private func generateSuggestedMessages() async {
        // Generate default messages based on days stale
        let baseMessage: String
        if notification.daysStale >= 7 {
            baseMessage = "Hey! The family is missing you at Miya. We haven't received your wearable data in 7 days. Can you check your device connection?"
        } else {
            baseMessage = "Hey! We haven't received your wearable data in 3 days. Can you check your device connection?"
        }
        
        await MainActor.run {
            suggestedMessages = [
                (label: "Gentle reminder", text: baseMessage),
                (label: "Friendly check-in", text: "Hey \(notification.memberName)! Just checking in - we haven't seen your wearable data in \(notification.daysStale) days. Everything okay with your device?"),
                (label: "Direct & helpful", text: "Hi \(notification.memberName), your wearable hasn't synced in \(notification.daysStale) days. The family vitality score needs your data! Can you reconnect your device?")
            ]
        }
    }
}

// MARK: - Missing Wearable Message Sheet (reuses MessageTemplatesSheet pattern)

struct MissingWearableMessageSheet: View {
    let notification: MissingWearableNotification
    let suggestedMessages: [(label: String, text: String)]
    let onSendMessage: (String, MessagePlatform) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMessageIndex: Int = 0
    @State private var customMessage: String = ""
    @State private var showCustomInput: Bool = false
    @State private var isEditingMessage = false
    @State private var editedMessage: String = ""
    @State private var selectedTone: MessageTone = .warm
    @State private var isRegeneratingMessage = false
    @State private var regeneratedMessages: [Int: [MessageTone: String]] = [:]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Choose a message to send to \(notification.memberName)")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                // Tone selector (reuse from MessageTemplatesSheet)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose tone:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(MessageTone.allCases) { tone in
                            Button {
                                selectedTone = tone
                                if selectedMessageIndex >= 0 && !suggestedMessages.isEmpty {
                                    Task {
                                        await regenerateMessageWithTone(
                                            messageIndex: selectedMessageIndex,
                                            tone: tone
                                        )
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: tone.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedTone == tone ? tone.color : .gray)
                                    Text(tone.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(selectedTone == tone ? tone.color : .gray)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedTone == tone ? tone.color.opacity(0.1) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedTone == tone ? tone.color : Color(red: 0.82, green: 0.82, blue: 0.84), 
                                                lineWidth: selectedTone == tone ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if isRegeneratingMessage {
                            ProgressView()
                                .scaleEffect(0.9)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Message options
                VStack(spacing: 12) {
                    if !suggestedMessages.isEmpty {
                        ForEach(suggestedMessages.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedMessageIndex = index
                                    showCustomInput = false
                                    isEditingMessage = false
                                } label: {
                                    HStack {
                                        Text(suggestedMessages[index].label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if selectedMessageIndex == index && !showCustomInput {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                // Message text or editor
                                if selectedMessageIndex == index && isEditingMessage {
                                    VStack(alignment: .trailing, spacing: 8) {
                                        TextEditor(text: $editedMessage)
                                            .font(.system(size: 15))
                                            .frame(minHeight: 100)
                                            .padding(8)
                                            .background(Color(red: 0.90, green: 0.90, blue: 0.92))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.blue, lineWidth: 1)
                                            )
                                        
                                        HStack {
                                            Button("Cancel") {
                                                isEditingMessage = false
                                                editedMessage = ""
                                            }
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            
                                            Button("Done") {
                                                isEditingMessage = false
                                            }
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.blue)
                                        }
                                    }
                                } else {
                                    let displayedMsg: String = {
                                        if let cached = regeneratedMessages[index]?[selectedTone] {
                                            return cached
                                        }
                                        return selectedMessageIndex == index && !editedMessage.isEmpty 
                                             ? editedMessage 
                                             : suggestedMessages[index].text
                                    }()
                                    
                                    HStack {
                                        Text(displayedMsg)
                                            .font(.system(size: 15))
                                            .foregroundColor(.miyaTextPrimary)
                                            .multilineTextAlignment(.leading)
                                        
                                        Spacer()
                                        
                                        if selectedMessageIndex == index {
                                            Button {
                                                editedMessage = displayedMsg
                                                isEditingMessage = true
                                            } label: {
                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedMessageIndex == index && !showCustomInput
                                                  ? Color.blue.opacity(0.1)
                                                  : Color(red: 0.95, green: 0.95, blue: 0.97))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedMessageIndex == index && !showCustomInput
                                                    ? Color.blue
                                                    : Color.clear, lineWidth: 2)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Custom message option
                    Button {
                        showCustomInput = true
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Write my own message")
                                .font(.system(size: 15))
                            Spacer()
                            if showCustomInput {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(showCustomInput ? Color.blue.opacity(0.1) : Color(red: 0.95, green: 0.95, blue: 0.97))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(showCustomInput ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if showCustomInput {
                        TextField("Type your message...", text: $customMessage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Send buttons
                VStack(spacing: 12) {
                    Button {
                        let displayedMsg: String = {
                            if showCustomInput {
                                return customMessage
                            }
                            if !suggestedMessages.isEmpty {
                                if let cached = regeneratedMessages[selectedMessageIndex]?[selectedTone] {
                                    return cached
                                }
                                if !editedMessage.isEmpty && selectedMessageIndex == selectedMessageIndex {
                                    return editedMessage
                                }
                                return suggestedMessages[selectedMessageIndex].text
                            }
                            return customMessage
                        }()
                        onSendMessage(displayedMsg, .whatsapp)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Send via WhatsApp")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(showCustomInput && customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button {
                        let displayedMsg: String = {
                            if showCustomInput {
                                return customMessage
                            }
                            if !suggestedMessages.isEmpty {
                                if let cached = regeneratedMessages[selectedMessageIndex]?[selectedTone] {
                                    return cached
                                }
                                if !editedMessage.isEmpty && selectedMessageIndex == selectedMessageIndex {
                                    return editedMessage
                                }
                                return suggestedMessages[selectedMessageIndex].text
                            }
                            return customMessage
                        }()
                        onSendMessage(displayedMsg, .imessage)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Send via iMessage")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(showCustomInput && customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Reach Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func regenerateMessageWithTone(messageIndex: Int, tone: MessageTone) async {
        await MainActor.run {
            isRegeneratingMessage = true
        }
        
        do {
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/regenerate_message") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let originalMessage = suggestedMessages[messageIndex].text
            
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "original_message": originalMessage,
                "tone": tone.rawValue,
                "member_name": notification.memberName
            ])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newMessage = json["message"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            
            await MainActor.run {
                if regeneratedMessages[messageIndex] == nil {
                    regeneratedMessages[messageIndex] = [:]
                }
                regeneratedMessages[messageIndex]?[tone] = newMessage
                isRegeneratingMessage = false
            }
            
        } catch {
            print("❌ Error regenerating message: \(error.localizedDescription)")
            await MainActor.run {
                isRegeneratingMessage = false
            }
        }
    }
}
