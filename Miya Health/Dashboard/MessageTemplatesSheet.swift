import SwiftUI
import Supabase

// MARK: - Message Templates Sheet
// Extracted from DashboardNotifications.swift for better compilation performance

enum MessageTone: String, CaseIterable, Identifiable {
    case warm = "Warm & caring"
    case motivating = "Motivating"
    case direct = "Direct & friendly"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .warm: return "heart.fill"
        case .motivating: return "flame.fill"
        case .direct: return "message.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .warm: return .pink
        case .motivating: return .orange
        case .direct: return .blue
        }
    }
}

struct MessageTemplatesSheet: View {
    let item: FamilyNotificationItem
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
    
    enum MessagePlatform {
        case whatsapp
        case imessage
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                    Text("Choose a message to send to \(item.memberName)")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                // Tone selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose tone:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(MessageTone.allCases) { tone in
                            Button {
                                selectedTone = tone
                                if selectedMessageIndex >= 0 {
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
                
                // Pre-templated messages as pills
                VStack(spacing: 12) {
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
                            if let cached = regeneratedMessages[selectedMessageIndex]?[selectedTone] {
                                return cached
                            }
                            if !editedMessage.isEmpty && selectedMessageIndex == selectedMessageIndex {
                                return editedMessage
                            }
                            return suggestedMessages[selectedMessageIndex].text
                        }()
                        let message = displayedMsg
                        onSendMessage(message, .whatsapp)
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
                            if let cached = regeneratedMessages[selectedMessageIndex]?[selectedTone] {
                                return cached
                            }
                            if !editedMessage.isEmpty && selectedMessageIndex == selectedMessageIndex {
                                return editedMessage
                            }
                            return suggestedMessages[selectedMessageIndex].text
                        }()
                        let message = displayedMsg
                        onSendMessage(message, .imessage)
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
                "member_name": item.memberName
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
                // Cache regenerated message
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
