import Foundation
import Supabase

enum ArloChatAPI {

    // MARK: - Chat

    struct Reply: Decodable {
        let reply: String
    }

    struct APIMessage: Encodable {
        let role: String   // "user" | "assistant"
        let content: String
    }

    static func send(
        messages: [APIMessage],
        firstName: String,
        openingLine: String
    ) async throws -> String {

        // 1) Build Edge Function URL
        let urlString = "\(SupabaseConfig.supabaseURL)/functions/v1/arlo-chat"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        // 2) Payload
        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "firstName": firstName,
            "openingLine": openingLine
        ]

        // 3) Get the CURRENT signed-in session from the shared client
        let client = SupabaseConfig.client
        let session: Session

        do {
            session = try await client.auth.session
        } catch {
            throw NSError(
                domain: "ArloChatAPI",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "You must be signed in to use Miya. No active Supabase session."
                ]
            )
        }

        // 4) Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Required by Supabase Edge Functions
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // CRITICAL: forward USER JWT (not anon key)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 5) Execute
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ArloChatAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: body.isEmpty ? "Miya request failed" : body
                ]
            )
        }

        // 6) Decode
        let decoded = try JSONDecoder().decode(Reply.self, from: data)
        return decoded.reply
    }
}

// MARK: - Facts RPC

extension ArloChatAPI {

    /// Matches the JSON returned by `get_arlo_facts(p_family_id uuid) returns jsonb`
    struct Facts: Decodable {
        let familyId: UUID
        let timeWindowLabel: String

        let familyVitalityCurrent: Int?
        let familyVitalityDelta: Int?

        let movementContribution: Int
        let sleepContribution: Int
        let recoveryContribution: Int

        let membersTotal: Int
        let membersWithData: Int

        let dataCoverageDays: Int
        let missingMembersCount: Int
        let confidenceLevel: String
        let confidence: Double

        let openerHeadline: String
        let openerWhy: String
        let openerHook: String
        let suggestedPills: [String]

        let memberHighlights: MemberHighlights

        struct MemberHighlights: Decodable {
            let bestSleepMemberName: String?
            let bestMovementMemberName: String?
            let bestRecoveryMemberName: String?
            let mostImprovedMemberName: String?
            let mostImprovedMemberDelta: Int?
        }

        enum CodingKeys: String, CodingKey {
            case familyId = "family_id"
            case timeWindowLabel = "time_window_label"

            case familyVitalityCurrent = "family_vitality_current"
            case familyVitalityDelta = "family_vitality_delta"

            case movementContribution = "movement_contribution"
            case sleepContribution = "sleep_contribution"
            case recoveryContribution = "recovery_contribution"

            case membersTotal = "members_total"
            case membersWithData = "members_with_data"

            case dataCoverageDays = "data_coverage_days"
            case missingMembersCount = "missing_members_count"
            case confidenceLevel = "confidence_level"
            case confidence

            case openerHeadline = "opener_headline"
            case openerWhy = "opener_why"
            case openerHook = "opener_hook"
            case suggestedPills = "suggested_pills"

            case memberHighlights = "member_highlights"
        }
    }

    /// IMPORTANT:
    /// Supabase RPC expects the argument name to match the Postgres parameter.
    /// Your function is `get_arlo_facts(p_family_id uuid)` so we pass `"p_family_id"`.
    ///
    /// This uses `AnyJSON.string(...)` because Supabase Swift RPC params are `AnyJSON` values.
    /// We pass UUID as a canonical string.
    static func fetchFacts(familyId: UUID) async throws -> Facts {
        let client = SupabaseConfig.client
        return try await client
            .rpc("get_arlo_facts", params: ["p_family_id": AnyJSON.string(familyId.uuidString)])
            .execute()
            .value
    }
}
