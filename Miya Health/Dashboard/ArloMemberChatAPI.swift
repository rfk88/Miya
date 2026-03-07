import Foundation
import Supabase

enum ArloMemberChatAPI {

    // MARK: - Types

    struct Reply: Decodable {
        let reply: String
        let suggested_prompts: [SuggestedPrompt]?
    }
    
    struct SuggestedPrompt: Decodable {
        let id: String
        let title: String
        let intent: String
    }

    struct APIMessage: Encodable {
        let role: String   // "user" | "assistant"
        let content: String
    }

    // MARK: - Chat

    /// Sends member-scoped chat to `arlo_member_chat` edge function.
    static func sendMemberOverview(
        memberUserId: String,
        memberName: String,
        intent: String?,
        factsJSON: String,
        messages: [APIMessage]
    ) async throws -> Reply {

        // 1) Build Edge Function URL (member-only)
        let urlString = "\(SupabaseConfig.supabaseURL)/functions/v1/arlo_member_chat"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        // 2) Structured opening line (your exact format)
        let openingLine = """
MODE: member_overview
MEMBER_ID: \(memberUserId)
MEMBER_NAME: \(memberName)
INTENT: \(intent ?? "")
REQUIRE_METRICS_FIRST: true
REQUIRE_METRICS_MIN: 3
FACTS_JSON: \(factsJSON)
"""

        // 3) Parse facts JSON safely into a dictionary
        let factsObject: Any
        if let data = factsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: []) {
            factsObject = obj
        } else {
            factsObject = [:]
        }

        // 4) Payload (match edge function contract)
        var payload: [String: Any] = [
            "mode": "member_overview",
            "member_id": memberUserId,
            "member_name": memberName,
            "facts": factsObject,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            // Optional, but useful for debugging / future parsing on server
            "openingLine": openingLine
        ]
        if let i = intent {
            payload["intent"] = i
        }

        // 5) Get the CURRENT signed-in session from the shared client
        let client = SupabaseConfig.client
        let session: Session

        do {
            session = try await client.auth.session
        } catch {
            throw NSError(
                domain: "ArloMemberChatAPI",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "You must be signed in to use Miya. No active Supabase session."
                ]
            )
        }

        // 6) Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Required by Supabase Edge Functions
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // CRITICAL: forward USER JWT (not anon key)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        // 7) Execute
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ArloMemberChatAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: body.isEmpty ? "Miya member request failed" : body
                ]
            )
        }

        // 8) Decode
        return try JSONDecoder().decode(Reply.self, from: data)
    }
}
