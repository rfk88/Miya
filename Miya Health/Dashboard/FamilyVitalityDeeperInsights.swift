import Foundation

// MARK: - Deeper insights (family vitality + pillar detail)

/// Where the narrative is scoped: whole family vs one pillar.
enum DeeperInsightsScope: Equatable {
    case family
    case pillar(VitalityPillar)
}

/// Inputs for `FamilyVitalityDeeperInsightsComposer` (pure; no network).
struct DeeperInsightsInput {
    let scoreRows: [DataManager.FamilyVitalityScoreRow]
    let vitalityFactors: [VitalityFactor]
    let familyMembers: [FamilyMemberScore]
    let familySnapshot: FamilyVitalitySnapshot?
    let trendInsights: [TrendInsight]
    let trendCoverage: TrendCoverageStatus?
    let fourWeekDelta: Int?
    let asOf: Date
}

/// Warm, family-facing copy plus a factual footnote (gentle read, not clinical).
struct DeeperInsightsOutput: Equatable {
    let evidenceSummary: String
    let interpretation: String
    let familyAction: String
    let supportAction: String?
    let footnote: String
}

enum FamilyVitalityDeeperInsightsComposer {

    static func build(scope: DeeperInsightsScope, input: DeeperInsightsInput) -> DeeperInsightsOutput {
        let factors = input.vitalityFactors
        let relevantInsights = input.trendInsights.filter {
            DashboardDataRelevance.shouldShowInsight($0, factors: factors)
        }
        let foot = footnote(asOf: input.asOf, coverage: input.trendCoverage, scoreRows: input.scoreRows)

        switch scope {
        case .family:
            return buildFamily(input: input, relevantInsights: relevantInsights, footnote: foot)
        case .pillar(let pillar):
            return buildPillar(pillar: pillar, input: input, relevantInsights: relevantInsights, footnote: foot)
        }
    }

    // MARK: - Family

    private static func buildFamily(
        input: DeeperInsightsInput,
        relevantInsights: [TrendInsight],
        footnote: String
    ) -> DeeperInsightsOutput {
        let series = FamilyVitalityWeeklyAggregates.weeklyFamilyTotalSeries(rows: input.scoreRows, maxWeeks: 6)
        let sorted = series.sorted { $0.weekStartDate < $1.weekStartDate }
        let evidence: String
        if sorted.count < 2 {
            evidence = "Once we have a couple of full weeks of synced scores, Miya can describe how your family rhythm is moving week to week."
        } else {
            switch FamilyVitalityWeeklyAggregates.weekOverWeekTrend(series: series) {
            case .up:
                evidence = "Looking at your family score week by week, things have been inching in an encouraging direction lately."
            case .down:
                evidence = "Looking at your family score week by week, things have softened a little - that is a normal ebb for busy households."
            case .flat:
                evidence = "Your family score has been fairly steady week to week - a quiet sign your routines are holding."
            case .insufficientData:
                evidence = "We are still gathering enough weeks to read the shape of your family score - check back soon."
            }
        }

        var paragraphs: [String] = []
        if let snap = input.familySnapshot {
            if snap.membersIncluded > 0 {
                paragraphs.append(snap.familyStateLabel.description)
                paragraphs.append(snap.alignmentLevel.description)
            } else {
                paragraphs.append("Right now Miya is still getting to know your household's rhythm - a little more synced time goes a long way.")
            }
            if let focus = snap.focusPillar, let strength = snap.strengthPillar, focus != strength {
                paragraphs.append(
                    "If you pick one place to cheer each other on, \(strength.dashboardDisplayName) is already a bright spot, while \(focus.dashboardDisplayName.lowercased()) is the gentle place a little extra kindness helps."
                )
            } else if let focus = snap.focusPillar {
                paragraphs.append("The pillar that has been asking for the most household patience lately is \(focus.dashboardDisplayName.lowercased()) - small, shared tweaks usually beat big lectures.")
            }
        }

        if let delta = input.fourWeekDelta {
            if delta >= 3 {
                paragraphs.append("Compared with the few weeks before, your family score has crept up - worth noticing what is working and doing more of that together.")
            } else if delta <= -3 {
                paragraphs.append("Compared with the few weeks before, your family score has dipped a touch - often that is fatigue or schedule, not effort. One calm week of basics usually helps.")
            }
        }

        if let win = relevantInsights.first(where: { $0.severity == .celebrate }) {
            let name = firstName(win.memberName)
            paragraphs.append("\(name) has had a nice stretch in \(win.pillar.dashboardDisplayName.lowercased()) - a simple shout-out at dinner can keep that warmth going.")
        } else if let watch = relevantInsights.first(where: { $0.severity != .celebrate }) {
            let name = firstName(watch.memberName)
            paragraphs.append("Miya noticed \(name) in \(watch.pillar.dashboardDisplayName.lowercased()) could use a softer week - nothing to fix in one night, just a little extra grace together.")
        }

        if paragraphs.isEmpty {
            paragraphs.append("Miya is still building a fuller picture of your family rhythm - keep syncing and check back soon.")
        }

        let interpretation = paragraphs.joined(separator: " ")

        let familyAction = familyHouseholdNudge(snapshot: input.familySnapshot)

        let support: String?
        if let snap = input.familySnapshot,
           let m = snap.supportMembers.first {
            let name = firstName(m.memberName)
            let pillarHint = snap.focusPillar?.dashboardDisplayName.lowercased() ?? "wellness"
            support = "If you do one caring thing this week, a low-pressure check-in with \(name) about \(pillarHint) (listening first) usually lands better than advice."
        } else {
            support = nil
        }

        return DeeperInsightsOutput(
            evidenceSummary: evidence,
            interpretation: interpretation,
            familyAction: familyAction,
            supportAction: support,
            footnote: footnote
        )
    }

    // MARK: - Pillar

    private static func buildPillar(
        pillar: VitalityPillar,
        input: DeeperInsightsInput,
        relevantInsights: [TrendInsight],
        footnote: String
    ) -> DeeperInsightsOutput {
        let series = FamilyVitalityWeeklyAggregates.weeklyFamilyPillarSeries(rows: input.scoreRows, pillar: pillar, maxWeeks: 6)
        let sorted = series.sorted { $0.weekStartDate < $1.weekStartDate }
        let pillarLabel = pillar.dashboardDisplayName

        let evidence: String
        if sorted.count < 2 {
            evidence = "We need a little more week-by-week \(pillarLabel.lowercased()) history before Miya can paint the household trend here."
        } else {
            switch FamilyVitalityWeeklyAggregates.weekOverWeekTrend(series: series) {
            case .up:
                evidence = "Your family's \(pillarLabel.lowercased()) picture has nudged upward week over week - worth a small celebration together."
            case .down:
                evidence = "Your family's \(pillarLabel.lowercased()) picture has eased down a little week over week - that often tracks busy seasons, not a single person."
            case .flat:
                evidence = "Your family's \(pillarLabel.lowercased()) picture has been steady week to week - consistency is doing more than you think."
            case .insufficientData:
                evidence = "We are still lining up enough weeks to describe \(pillarLabel.lowercased()) clearly for the household."
            }
        }

        var paragraphs: [String] = []
        let factorName = factorDisplayNameForPillar(pillar)
        if let factor = input.vitalityFactors.first(where: { $0.name == factorName }) {
            let band = PillarStateBand.band(for: factor)
            paragraphs.append(
                "Across everyone, \(pillarLabel) is sitting in a \(band.label.lowercased()) band right now - that is a shared story, not a scoreboard."
            )
        }

        if let snap = input.familySnapshot, snap.membersIncluded > 0 {
            if snap.focusPillar == pillar {
                paragraphs.append("This is also the pillar Miya would nudge the household toward first if you want one gentle theme for the week.")
            } else if snap.strengthPillar == pillar {
                paragraphs.append("This pillar is one of the places your family already has momentum - lean on those habits when other weeks feel heavier.")
            }
        }

        let pillarInsights = relevantInsights.filter { $0.pillar == pillar }
        if let win = pillarInsights.first(where: { $0.severity == .celebrate }) {
            let name = firstName(win.memberName)
            paragraphs.append("\(name) has helped lift this pillar lately - a quiet thank-you goes further than a pep talk.")
        } else if let w = pillarInsights.first(where: { $0.severity != .celebrate }) {
            let name = firstName(w.memberName)
            paragraphs.append("\(name) is carrying a bit more load here - a shared plan beats solo willpower.")
        }

        if paragraphs.isEmpty {
            paragraphs.append("Miya is still lining up enough detail on \(pillarLabel) for the whole household - a little more synced time helps.")
        }

        let interpretation = paragraphs.joined(separator: " ")

        let familyAction = pillarHouseholdNudge(pillar: pillar)

        let support: String?
        if let snap = input.familySnapshot,
           let m = snap.supportMembers.first,
           snap.focusPillar == pillar {
            let name = firstName(m.memberName)
            support = "If someone could use backup on \(pillarLabel.lowercased()) this week, \(name) might appreciate a walk, a wind-down, or just being asked how they are really doing, with no agenda."
        } else {
            support = nil
        }

        return DeeperInsightsOutput(
            evidenceSummary: evidence,
            interpretation: interpretation,
            familyAction: familyAction,
            supportAction: support,
            footnote: footnote
        )
    }

    // MARK: - Shared helpers

    private static func factorDisplayNameForPillar(_ pillar: VitalityPillar) -> String {
        DashboardDataRelevance.factorName(for: pillar)
    }

    private static func footnote(
        asOf: Date,
        coverage: TrendCoverageStatus?,
        scoreRows: [DataManager.FamilyVitalityScoreRow]
    ) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateStyle = .medium
        df.timeStyle = .none
        let day = df.string(from: asOf)
        if let cov = coverage, !cov.hasMinimumCoverage {
            return "Based on synced scores through \(day). Sharper trend detail unlocks after a bit more daily history together."
        }
        if scoreRows.isEmpty {
            return "Based on what is loaded today (\(day)). Pull to refresh after everyone has synced."
        }
        return "Based on synced family scores through \(day). This is a gentle read for your household, not a medical judgement."
    }

    private static func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }

    private static func familyHouseholdNudge(snapshot: FamilyVitalitySnapshot?) -> String {
        guard let snap = snapshot, let focus = snap.focusPillar else {
            return "Pick one tiny household habit this week (same bedtime snack, a Sunday walk, phones down at dinner once) and repeat it - families change faster with repetition than intensity."
        }
        switch focus {
        case .sleep:
            return "Try one shared wind-down cue this week (same lights-down time, same calm playlist) - sleep loves boring consistency more than hero nights."
        case .movement:
            return "Try one short movement ritual together this week (after-dinner walk, Saturday stretch) - joy counts as fitness here."
        case .stress:
            return "Try one softer evening this week (lighter plans, a few slow breaths together) - recovery is a team sport in busy homes."
        }
    }

    private static func pillarHouseholdNudge(pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep:
            return "This week: agree on one quiet hour before bed for the household - not perfect silence, just gentler energy."
        case .movement:
            return "This week: add one low-stakes outing or at-home dance break together - laughter still counts as movement."
        case .stress:
            return "This week: protect one calm pocket most evenings - even ten minutes of unhurried time helps everyone feel steadier."
        }
    }
}
