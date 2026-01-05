import Foundation

/// Canonical guided setup status values (mirrors `family_members.guided_setup_status`).
enum GuidedSetupStatus: String, Codable, CaseIterable {
    case pendingAcceptance = "pending_acceptance"
    case acceptedAwaitingData = "accepted_awaiting_data"
    case dataCompletePendingReview = "data_complete_pending_review"
    case reviewedComplete = "reviewed_complete"
}

/// Parse DB value to enum without inventing values.
/// - Returns nil if raw is nil or unknown.
func parseGuidedSetupStatus(_ raw: String?) -> GuidedSetupStatus? {
    guard let raw else { return nil }
    return GuidedSetupStatus(rawValue: raw)
}

/// Normalize for display/routing safety only.
/// - Maps nil/unknown -> `.pendingAcceptance`.
/// - Never write normalized unknowns back to DB.
func normalizeGuidedSetupStatus(_ raw: String?) -> GuidedSetupStatus {
    parseGuidedSetupStatus(raw) ?? .pendingAcceptance
}


