import Foundation

// MARK: - Insights feed padding (minimum two meaningful rows)

/// Inputs for generating padded insight rows without touching `DataManager`.
struct SuggestedFeedInsightContext {
    let familySnapshot: FamilyVitalitySnapshot?
    let vitalityFactors: [VitalityFactor]
    let familyVitalityScore: Int?
    let familyVitalityFourWeekDelta: Int?
    let trendCoverage: TrendCoverageStatus?
    let familyMembers: [FamilyMemberScore]
    let familyDisplayName: String?
    let viewerUserId: String?
}

enum SuggestedFeedInsightPad {
    private static let maxRows = 4
    private static let minimumRows = 2

    /// When organic `suggestedFeed()` has fewer than two rows, append data-grounded rows
    /// until at least two exist (capped at four total). Organic lanes and order are preserved.
    static func padIfNeeded(_ feed: SuggestedFeed, context: SuggestedFeedInsightContext) -> SuggestedFeed {
        var lane1 = feed.lane1
        var lane2 = feed.lane2
        var lane3 = feed.lane3

        func total() -> Int { lane1.count + lane2.count + lane3.count }
        guard total() < minimumRows else { return feed }

        var usedNormalized = Set((lane1 + lane2 + lane3).map { normalize($0.text) })

        let familyChatLabel = chatLabel(from: context.familyDisplayName)

        for row in candidateRows(context: context, familyChatLabel: familyChatLabel) {
            if total() >= maxRows { break }
            if total() >= minimumRows { break }
            let key = normalize(row.text)
            guard !key.isEmpty, !usedNormalized.contains(key) else { continue }
            usedNormalized.insert(key)
            switch row.lane {
            case .wins: lane1.append(row)
            case .checkIn: lane2.append(row)
            case .familyOps: lane3.append(row)
            }
        }

        // If duplicates or thin candidates left us under two rows, add hard fallbacks.
        var fallbackAttempt = 0
        while total() < minimumRows && total() < maxRows && fallbackAttempt < 8 {
            let fallback = ultimateFallbackRow(index: total(), familyChatLabel: familyChatLabel)
            let key = normalize(fallback.text)
            fallbackAttempt += 1
            if usedNormalized.contains(key) { continue }
            usedNormalized.insert(key)
            switch fallback.lane {
            case .wins: lane1.append(fallback)
            case .checkIn: lane2.append(fallback)
            case .familyOps: lane3.append(fallback)
            }
        }

        return SuggestedFeed(lane1: lane1, lane2: lane2, lane3: lane3)
    }

    private static func chatLabel(from displayName: String?) -> String {
        let t = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "your family" : t
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Padded rows use **checkIn** for coaching-style lines and **wins** for clearly positive lines
    /// so lane dots match tone.
    private static func candidateRows(
        context: SuggestedFeedInsightContext,
        familyChatLabel: String
    ) -> [SuggestedRow] {
        var out: [SuggestedRow] = []
        let miya = SuggestedRow.Action.openMiyaChat(memberUserId: nil, memberName: familyChatLabel)

        if let snapshot = context.familySnapshot {
            let headline = snapshot.headline(viewerUserId: context.viewerUserId)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !headline.isEmpty {
                out.append(
                    SuggestedRow(
                        id: "pad-snapshot-headline",
                        lane: .checkIn,
                        memberUserId: nil,
                        text: headline,
                        action: miya
                    )
                )
            }

            if let focus = effectiveFocusPillar(snapshot: snapshot, factors: context.vitalityFactors) {
                if let line = focusMicroActionLine(
                    focus: focus,
                    state: snapshot.familyStateLabel,
                    alignment: snapshot.alignmentLevel
                ) {
                    out.append(
                        SuggestedRow(
                            id: "pad-focus-\(focus.rawValue)",
                            lane: .checkIn,
                            memberUserId: nil,
                            text: line,
                            action: miya
                        )
                    )
                }
            }

            if let strength = snapshot.strengthPillar,
               let focusEff = effectiveFocusPillar(snapshot: snapshot, factors: context.vitalityFactors),
               strength != focusEff {
                let sName = strength.dashboardDisplayName
                let fName = focusEff.dashboardDisplayName.lowercased()
                let line = "\(sName) is a family strength right now - lean on those habits while you gently support \(fName)."
                out.append(
                    SuggestedRow(
                        id: "pad-strength-\(strength.rawValue)-\(focusEff.rawValue)",
                        lane: .wins,
                        memberUserId: nil,
                        text: line,
                        action: miya
                    )
                )
            }
        }

        if let delta = context.familyVitalityFourWeekDelta {
            if let line = fourWeekLine(delta: delta) {
                out.append(
                    SuggestedRow(
                        id: "pad-fourweek-\(delta)",
                        lane: .wins,
                        memberUserId: nil,
                        text: line,
                        action: miya
                    )
                )
            }
        }

        if let score = context.familyVitalityScore, (38..<72).contains(score) {
            let line = "Your family score is \(score) right now - small weekly repeats move it more than one-off hero weeks."
            out.append(
                SuggestedRow(
                    id: "pad-score-context-\(score)",
                    lane: .checkIn,
                    memberUserId: nil,
                    text: line,
                    action: miya
                )
            )
        }

        if let cov = context.trendCoverage, !cov.hasMinimumCoverage {
            let days = max(1, cov.needMoreDataDays)
            let line = "Sharper week-to-week insights unlock after about \(days) more day\(days == 1 ? "" : "s") of synced data - keep wearables on when you can."
            out.append(
                SuggestedRow(
                    id: "pad-coverage-\(days)",
                    lane: .checkIn,
                    memberUserId: nil,
                    text: line,
                    action: miya
                )
            )
        }

        let staleCount = context.familyMembers.filter(\.isStale).count
        if staleCount > 0 {
            let line = "\(staleCount) family member\(staleCount == 1 ? "" : "s") have older scores - a quick sync makes next week's insights much sharper."
            out.append(
                SuggestedRow(
                    id: "pad-stale-\(staleCount)",
                    lane: .checkIn,
                    memberUserId: nil,
                    text: line,
                    action: miya
                )
            )
        }

        return out
    }

    private static func ultimateFallbackRow(index: Int, familyChatLabel: String) -> SuggestedRow {
        let miya = SuggestedRow.Action.openMiyaChat(memberUserId: nil, memberName: familyChatLabel)
        switch index % 3 {
        case 0:
            return SuggestedRow(
                id: "pad-fallback-connect-\(index)",
                lane: .checkIn,
                memberUserId: nil,
                text: "When everyone connects a wearable, this board starts telling one clear family story - invite people in when it feels right.",
                action: miya
            )
        case 1:
            return SuggestedRow(
                id: "pad-fallback-miya-\(index)",
                lane: .checkIn,
                memberUserId: nil,
                text: "Ask Miya for one small habit your household can try this week - keep it boringly doable so it sticks.",
                action: miya
            )
        default:
            return SuggestedRow(
                id: "pad-fallback-scan-\(index)",
                lane: .checkIn,
                memberUserId: nil,
                text: "When you have two quiet minutes, scan family vitality together - one small tweak beats a big reset.",
                action: miya
            )
        }
    }

    private static func effectiveFocusPillar(
        snapshot: FamilyVitalitySnapshot,
        factors: [VitalityFactor]
    ) -> VitalityPillar? {
        if let f = snapshot.focusPillar { return f }
        return lowestPillarByFactorAverage(factors: factors)
    }

    private static func lowestPillarByFactorAverage(factors: [VitalityFactor]) -> VitalityPillar? {
        let map = Dictionary(uniqueKeysWithValues: factors.map { ($0.name.lowercased(), $0) })
        let candidates: [(key: String, pillar: VitalityPillar)] = [
            ("sleep", .sleep),
            ("activity", .movement),
            ("recovery", .stress),
            ("stress", .stress)
        ]
        var best: (VitalityPillar, Int)?
        for c in candidates {
            guard let f = map[c.key] else { continue }
            let p = f.percent
            if best == nil || p < best!.1 { best = (c.pillar, p) }
        }
        return best?.0
    }

    private static func focusMicroActionLine(
        focus: VitalityPillar,
        state: FamilyState,
        alignment: AlignmentLevel
    ) -> String? {
        let focusName = focus.dashboardDisplayName.lowercased()
        let tail: String = {
            switch (state, alignment) {
            case (.rebuilding, .wide):
                return "Pick one tiny habit everyone can try once this week."
            case (.rebuilding, _), (_, .wide):
                return "Rebuild rhythm with one repeat habit, not a full overhaul."
            case (.steady, .tight):
                return "Protect the basics you already share."
            case (.strong, _):
                return "Keep the easy wins visible for the household."
            default:
                return "One shared anchor habit helps the group stay aligned."
            }
        }()
        let core: String
        switch focus {
        case .sleep:
            core = "This week: repeat one wind-down time most nights (screens off 30 minutes before) to support \(focusName)."
        case .movement:
            core = "This week: add one 10-minute walk after a meal together - small repeats lift \(focusName) fastest."
        case .stress:
            core = "This week: keep the last hour before bed lighter - a few slow breaths go a long way for \(focusName)."
        }
        return "\(core) \(tail)"
    }

    private static func fourWeekLine(delta: Int) -> String? {
        if delta >= 2 {
            return "Your family score is up about \(delta) points versus the prior few weeks - keep doing what is working."
        }
        if delta <= -2 {
            return "Your family score is down about \(abs(delta)) points versus the prior few weeks - one gentle week of basics usually steadies the ship."
        }
        if delta == 1 || delta == -1 {
            return delta == 1
                ? "Your family score is slightly up versus the prior few weeks - small gains compound."
                : "Your family score is slightly softer versus the prior few weeks - worth a light check-in, not a panic."
        }
        return "Your family score is roughly in line with the prior few weeks - steady is still a win."
    }
}
