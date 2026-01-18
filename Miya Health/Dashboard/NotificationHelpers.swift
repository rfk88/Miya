import SwiftUI
import Supabase

// MARK: - Notification Helper Components
// Extracted from DashboardNotifications.swift for better compilation performance

// MARK: - Share Sheet View

struct MiyaShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to update
    }
}

// MARK: - Insight Chat Sheet (Legacy - kept for compatibility)

struct MiyaInsightChatSheet: View {
    let alertItem: FamilyNotificationItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isSending = false
    @State private var errorText: String?
    
    var body: some View {
        AnyView(
            NavigationView {
                VStack(spacing: 0) {
                    if errorText != nil || messages.isEmpty {
                        VStack(spacing: 12) {
                        if let err = errorText {
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                        if messages.isEmpty {
                            Text("Ask a question about this pattern")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    
                    ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            HStack {
                                if msg.role == "user" {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .trailing)
                                } else {
                                    Text(msg.text)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                                        .cornerRadius(12)
                                        .frame(maxWidth: .infinity * 0.75, alignment: .leading)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                    }
                    .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                }
            }
            .navigationTitle("Ask Miya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        )
    }
    
    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        errorText = nil
        
        messages.append((role: "user", text: text))
        isSending = true
        defer { isSending = false }
        
        do {
            // Extract alert_state_id from debugWhy (format: "serverPattern ... alertStateId=<uuid> ...")
            guard let debugWhy = alertItem.debugWhy,
                  debugWhy.contains("serverPattern"),
                  let alertStateId = extractAlertStateId(from: debugWhy)
            else {
                errorText = "Ask Miya is available for server pattern alerts."
                return
            }
            
            let supabase = SupabaseConfig.client
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(SupabaseConfig.supabaseURL)/functions/v1/miya_insight_chat") else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["alert_state_id": alertStateId, "message": text])
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (obj?["ok"] as? Bool) == true else {
                let errBody = (obj?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown"
                throw NSError(domain: "miya_insight_chat", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Chat failed (status \(httpStatus)): \(errBody)"])
            }
            let reply = obj?["reply"] as? String ?? "Sorry — I couldn't generate a response."
            messages.append((role: "assistant", text: reply))
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Helper Functions

/// Extract alert state ID from debugWhy string
/// Format: "serverPattern ... alertStateId=<uuid> ..."
func extractAlertStateId(from debugWhy: String) -> String? {
    let pattern = "alertStateId=([a-f0-9-]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
          let match = regex.firstMatch(in: debugWhy, options: [], range: NSRange(debugWhy.startIndex..., in: debugWhy)),
          let range = Range(match.range(at: 1), in: debugWhy)
    else { return nil }
    return String(debugWhy[range])
}
