import SwiftUI

// MARK: - Family Vitality hero card (new)

/// Solid-teal hero card that replaces the legacy white `FamilyVitalityCard`
/// on the redesigned dashboard. Renders:
///   - "FAMILY VITALITY" eyebrow + "X of Y connected" indicator
///   - large family score (78pt) + verdict + 4-week trend delta
///   - progress line + "N points to 100" message under the score
///   - three frosted-glass pillar pills (Sleep / Activity / Recovery)
///
/// `fourWeekDelta` may be nil when there isn't enough history yet (the
/// trend computation requires at least 3 days of data in both the current
/// week and the prior 3-week baseline). When nil, the delta chip is hidden.
struct FamilyVitalityHeroCard: View {
    let score: Int
    let verdict: String
    let membersWithData: Int?
    let membersTotal: Int?
    let factors: [VitalityFactor]
    /// Signed difference between this week's family avg and the prior 3 weeks' avg.
    /// Nil hides the chip entirely (insufficient history).
    var fourWeekDelta: Int? = nil
    var showPillars: Bool = true

    /// Clamped score for the progress bar (defensive against out-of-range data).
    private var clampedScore: Int {
        max(0, min(100, score))
    }

    private var pointsToGoal: Int {
        max(0, 100 - clampedScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topRow
            scoreRow
            progressSection
            if showPillars {
                pillarRow
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.miyaHeroTealStart.opacity(0.86),
                                Color.miyaHeroTealMid.opacity(0.76),
                                Color.miyaHeroTealEnd.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 46)
                    .offset(x: 120, y: -82)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.miyaHeroAccentTeal.opacity(0.30), radius: 24, x: 0, y: 14)
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FAMILY VITALITY")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.white)

            Spacer()

            if let with = membersWithData, let total = membersTotal {
                HStack(spacing: 5) {
                    Text("\(with) of \(total) connected")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.65))
            }
        }
    }

    // MARK: - Score + verdict + delta

    private var scoreRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("\(score)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .tracking(-3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(verdict)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))

                if let delta = fourWeekDelta {
                    fourWeekDeltaChip(delta: delta)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Small white pill showing "+N vs last 4 weeks" / "−N vs last 4 weeks" / "Steady".
    /// All text uses white so it reads cleanly on the teal background.
    private func fourWeekDeltaChip(delta: Int) -> some View {
        let symbolName: String = {
            if delta > 0 { return "arrow.up.right" }
            if delta < 0 { return "arrow.down.right" }
            return "equal"
        }()
        let valueText: String = {
            if delta == 0 { return "Steady" }
            // Use signed integer formatting so we get "+2" / "-4".
            let sign = delta > 0 ? "+" : "−"
            return "\(sign)\(abs(delta))"
        }()
        return HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
            Text(valueText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            if delta != 0 {
                Text("vs last 4 weeks")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Progress to 100

    /// Horizontal progress bar (score / 100) with a supportive message underneath.
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let progressWidth = proxy.size.width * CGFloat(clampedScore) / 100.0
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                    Capsule(style: .continuous)
                        .fill(Color(hex: "C9FFFF"))
                        .frame(width: max(8, progressWidth))
                    Circle()
                        .fill(Color(hex: "DFFFFF"))
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.white.opacity(0.55), radius: 7, x: 0, y: 0)
                        .offset(x: max(0, progressWidth - 7))
                }
            }
            .frame(height: 14)

            HStack(spacing: 6) {
                Text(progressMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                Spacer(minLength: 0)
                Text("\(clampedScore)/100")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
    }

    private var progressMessage: String {
        if clampedScore >= 100 {
            return "You're at 100 — keep it going."
        }
        if clampedScore >= 90 {
            return "Almost there — \(pointsToGoal) to 100."
        }
        if clampedScore >= 70 {
            return "Strong week — \(pointsToGoal) points to 100."
        }
        if clampedScore >= 50 {
            return "Steady progress — \(pointsToGoal) points to 100."
        }
        return "Building momentum — \(pointsToGoal) points to 100."
    }

    // MARK: - Pillar pills

    private var pillarRow: some View {
        HStack(spacing: 8) {
            ForEach(VitalityPillar.allCases, id: \.rawValue) { pillar in
                HeroPillarMetricCard(
                    icon: pillar.metricIconName,
                    title: pillar.dashboardDisplayName,
                    valueLabel: factor(for: pillar).map { PillarStateBand.band(for: $0).label } ?? PillarStateBand.noData.label,
                    accent: pillar.metricAccentColor
                )
            }
        }
    }

    private func factor(for pillar: VitalityPillar) -> VitalityFactor? {
        let factorName: String
        switch pillar {
        case .sleep:    factorName = "Sleep"
        case .movement: factorName = "Activity"
        case .stress:   factorName = "Recovery"
        }
        return factors.first(where: { $0.name == factorName })
    }
}

// MARK: - Pillar metric cards

private struct HeroPillarMetricCard: View {
    let icon: String
    let title: String
    let valueLabel: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                )

            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaDashboardTextPrimary)

                    Text(valueLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.miyaDashboardTextSecond.opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension VitalityPillar {
    var metricIconName: String {
        switch self {
        case .sleep: return "moon.fill"
        case .movement: return "figure.walk"
        case .stress: return "sun.max.fill"
        }
    }

    var metricAccentColor: Color {
        switch self {
        case .sleep: return .miyaSleepAccent
        case .movement: return .miyaActivityAccent
        case .stress: return .miyaRecoveryAccent
        }
    }
}

#if DEBUG
#Preview("Hero — full") {
    FamilyVitalityHeroCard(
        score: 86,
        verdict: "Great week",
        membersWithData: 3,
        membersTotal: 4,
        factors: [
            VitalityFactor(name: "Sleep", iconName: "bed.double.fill", percent: 70, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Activity", iconName: "figure.walk", percent: 88, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Recovery", iconName: "heart.fill", percent: 84, description: "", actionPlan: [], memberScores: [])
        ],
        fourWeekDelta: 2
    )
    .padding()
    .background(Color.miyaBackground)
}

#Preview("Hero — declining") {
    FamilyVitalityHeroCard(
        score: 62,
        verdict: "Steady",
        membersWithData: 3,
        membersTotal: 4,
        factors: [
            VitalityFactor(name: "Sleep", iconName: "bed.double.fill", percent: 60, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Activity", iconName: "figure.walk", percent: 64, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Recovery", iconName: "heart.fill", percent: 58, description: "", actionPlan: [], memberScores: [])
        ],
        fourWeekDelta: -4
    )
    .padding()
    .background(Color.miyaBackground)
}

#Preview("Hero — low data") {
    FamilyVitalityHeroCard(
        score: 42,
        verdict: "Needs attention",
        membersWithData: 1,
        membersTotal: 4,
        factors: [
            VitalityFactor(name: "Sleep", iconName: "bed.double.fill", percent: 28, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Activity", iconName: "figure.walk", percent: 52, description: "", actionPlan: [], memberScores: []),
            VitalityFactor(name: "Recovery", iconName: "heart.fill", percent: 38, description: "", actionPlan: [], memberScores: [])
        ],
        fourWeekDelta: nil
    )
    .padding()
    .background(Color.miyaBackground)
}
#endif
