import Foundation

/// Composes up to three grounded "key finding" lines for Family Vitality overview / pillar screens.
/// Sources: `FamilyVitalitySnapshot`, `TrendInsight`, optional `FamilyRecommendationEngine` rows.
enum FamilyVitalityKeyFindingsComposer {
    /// - Parameter filterPillar: When non-nil (pillar detail), only insights/recommendations for that pillar are used.
    static func bullets(
        snapshot: FamilyVitalitySnapshot?,
        trendInsights: [TrendInsight],
        trendCoverage: TrendCoverageStatus?,
        filterPillar: VitalityPillar?,
        factors: [VitalityFactor] = [],
        maxCount: Int = 3,
        viewerUserId: String? = nil
    ) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        func normalized(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        func appendUnique(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, out.count < maxCount else { return }
            let key = normalized(t)
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(t)
        }

        let insights: [TrendInsight] = {
            guard let p = filterPillar else { return trendInsights }
            return trendInsights.filter { $0.pillar == p }
        }().filter { insight in
            guard !factors.isEmpty else { return true }
            return DashboardDataRelevance.shouldShowInsight(insight, factors: factors)
        }

        // 1) Attention / watch — prefer bodies (full sentence).
        for ins in insights where ins.severity != .celebrate {
            appendUnique(ins.body)
        }

        // 2) Snapshot support messages (overview only — not pillar-tagged)
        if filterPillar == nil, let snap = snapshot, snap.membersIncluded > 0 {
            for m in snap.supportMembers {
                appendUnique(m.message)
            }
        }

        // 3) Celebrate trends
        for ins in insights where ins.severity == .celebrate {
            appendUnique(ins.body)
        }

        // 4) Celebrate members (overview only — messages are not pillar-tagged)
        if filterPillar == nil, let snap = snapshot {
            for m in snap.celebrateMembers {
                appendUnique(m.message)
            }
        }

        // 5) Recommendations (pillar-aware)
        if let snap = snapshot {
            let recs = FamilyRecommendationEngine.build(
                snapshot: snap,
                trendInsights: factors.isEmpty ? trendInsights : insights,
                coverage: trendCoverage
            )
            let filtered: [FamilyRecommendationRow] = {
                guard let p = filterPillar else { return recs }
                return recs.filter { $0.pillar == p }
            }()
            for r in filtered {
                appendUnique(r.text)
            }
        }

        // 6) Snapshot headline / alignment — only if still room and overview (headline is family-wide)
        if out.count < maxCount, filterPillar == nil, let snap = snapshot, snap.membersIncluded > 0 {
            appendUnique(snap.headline(viewerUserId: viewerUserId))
        }
        if out.count < maxCount, filterPillar == nil, let snap = snapshot, snap.membersIncluded > 0 {
            appendUnique(snap.alignmentLevel.description)
        }

        // 7) Safe fallback lines so the card never feels empty or thin.
        // These are intentionally general: they do not invent health conclusions.
        if maxCount >= 2 {
            let minimumCount = min(2, maxCount)
            let fallbackLines: [String] = {
                if let pillar = filterPillar {
                    let name = pillar.dashboardDisplayName.lowercased()
                    return [
                        "No urgent changes stand out for family \(name) right now.",
                        "Keep an eye on \(name) as more synced days come in.",
                        "Consistent \(name) routines can support the family vitality score."
                    ]
                }

                if let snap = snapshot, snap.membersIncluded > 0 {
                    return [
                        "Your family has enough synced data to keep tracking weekly vitality.",
                        "Small, steady improvements across sleep, activity, or recovery can lift the family score.",
                        "Nice progress — keep the healthy routines going this week."
                    ]
                }

                return [
                    "As more family members sync data, Miya will highlight stronger patterns here.",
                    "Every synced day helps build a clearer picture of family vitality.",
                    "Small, steady routines can support the family vitality score."
                ]
            }()

            for line in fallbackLines where out.count < minimumCount {
                appendUnique(line)
            }
        }

        return Array(out.prefix(maxCount))
    }
}
