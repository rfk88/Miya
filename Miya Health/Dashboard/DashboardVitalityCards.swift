import SwiftUI

// MARK: - FAMILY VITALITY CARD

struct FamilyVitalityCard: View {
    let score: Int
    let label: String
    let factors: [VitalityFactor]
    let includedMembersText: String?
    let progressScore: Int?
    let onFactorTapped: (VitalityFactor) -> Void

    private var progressFraction: Double {
        // Do NOT change logic: use progressScore if present, otherwise fall back to score/100.
        let p = Double(progressScore ?? score)
        return max(0.0, min(p / 100.0, 1.0))
    }

    private var progressLabelText: String {
        // Do NOT hardcode: reuse the values we already have.
        let current = progressScore ?? score
        return "Progress to optimal: \(current) / 100"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with score on right (like screenshot)
            HStack(alignment: .top) {
                Text("Family Vitality")
                    .font(DashboardDesign.title2Font)
                    .foregroundColor(DashboardDesign.primaryTextColor)
                    
                    Spacer()
                    
                // Score on right (like screenshot)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(DashboardDesign.scoreLargeFont)
                        .foregroundColor(Color.miyaPrimary)  // Use brand color to stand out
                    
                    Text(label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
            }

            // Progress bar + label
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)

                        Capsule()
                            .fill(DashboardDesign.miyaTealSoft)
                            .frame(width: geo.size.width * progressFraction, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(progressLabelText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    
                    if let includedMembersText {
                        Text("• \(includedMembersText)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(DashboardDesign.tertiaryTextColor)
                    }
                }
            }

            // Divider before tiles
                    Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.top, 4)
                    
            // Tiles row (3 compact tiles) built from the SAME `factors` data
            // NOTE: We intentionally do NOT render "What's affecting vitality?" UI.
                            HStack(spacing: 10) {
                ForEach(tilesToShow, id: \.id) { factor in
                    PillarTile(
                        factor: factor,
                        tint: tileTint(for: factor),
                        iconColor: tileIconColor(for: factor)
                    )
                    .onTapGesture {
                        // Keep interaction: tapping a tile selects the factor like before.
                        onFactorTapped(factor)
                    }
                }
            }
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.vertical, DashboardDesign.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius)
                .fill(Color.white)
        )
        .shadow(
            color: DashboardDesign.cardShadowStrong.color,
            radius: DashboardDesign.cardShadowStrong.radius,
            x: DashboardDesign.cardShadowStrong.x,
            y: DashboardDesign.cardShadowStrong.y
        )
    }

    private var tilesToShow: [VitalityFactor] {
        // Keep the same conceptual pillars: Sleep, Activity, Recovery (in that order if present).
        // Do NOT invent; filter from existing factors.
        let order = ["sleep", "activity", "recovery", "stress"]
        var map: [String: VitalityFactor] = [:]
        for f in factors { map[f.name.lowercased()] = f }
        let ordered = order.compactMap { map[$0] }
        // If any missing, fall back to first 3 factors without changing data.
        return ordered.isEmpty ? Array(factors.prefix(3)) : ordered
    }

    private func tileTint(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor.opacity(0.18)
        case "activity": return DashboardDesign.movementColor.opacity(0.18)
        case "stress", "recovery": return DashboardDesign.stressColor.opacity(0.18)
        default: return DashboardDesign.buttonTint.opacity(0.12)
        }
    }

    private func tileIconColor(for factor: VitalityFactor) -> Color {
        switch factor.name.lowercased() {
        case "sleep": return DashboardDesign.sleepColor
        case "activity": return DashboardDesign.movementColor
        case "stress", "recovery": return DashboardDesign.stressColor
        default: return DashboardDesign.buttonTint
        }
    }

    private struct PillarTile: View {
        let factor: VitalityFactor
        let tint: Color
        let iconColor: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Icon (smaller, compact)
                Image(systemName: factor.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)

                // Name (smaller font)
                Text(factor.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardDesign.primaryTextColor)

                // Value + Unit on same line (like screenshot: "50 hrs")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(factor.percent)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text(unitShortText(for: factor.name))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }

                // Full unit text below (no truncation)
                Text(unitText(for: factor.name))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DashboardDesign.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(
                color: DashboardDesign.cardShadow.color,
                radius: DashboardDesign.cardShadow.radius,
                x: DashboardDesign.cardShadow.x,
                y: DashboardDesign.cardShadow.y
            )
        }

        private func unitShortText(for name: String) -> String {
            switch name.lowercased() {
            case "sleep": return "%"
            case "activity": return "%"
            case "stress": return "%"
            case "recovery": return "%"
            default: return ""
            }
        }
        
        private func unitText(for name: String) -> String {
            switch name.lowercased() {
            case "sleep": return "sleep score"
            case "activity": return "activity score"
            case "stress": return "recovery score"
            case "recovery": return "recovery score"
            default: return "score"
            }
        }
    }
}

struct FamilyVitalityPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Family vitality")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)
                .padding(.top, 12)
            
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.miyaPrimary.opacity(0.6))
                
                VStack(spacing: 6) {
                    Text("Waiting for your family")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text("Once your family members complete onboarding and sync their health data, you'll see your family vitality score here.")
                        .font(.system(size: 13))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - PERSONAL VITALITY CARD

struct PersonalVitalityCard: View {
    let currentUser: FamilyMemberScore
    let factors: [VitalityFactor]
    @State private var isExpanded: Bool = false
    
    private func label(for score: Int) -> String {
        switch score {
        case 80...100: return "Great"
        case 60..<80:  return "Good"
        case 40..<60:  return "Okay"
        default:       return "Needs attention"
        }
    }
    
    private func myPillarScore(named factorName: String) -> Int? {
        let match = factors.first(where: { $0.name.lowercased() == factorName.lowercased() })
        return match?.memberScores.first(where: { $0.isMe })?.currentScore
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            HStack(spacing: DashboardDesign.internalSpacing) {
                ZStack {
                    Circle()
                        .fill(DashboardDesign.miyaTealSoft.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(currentUser.initials)
                        .font(DashboardDesign.bodyFont)
                        .foregroundColor(DashboardDesign.miyaTealSoft.opacity(0.9))
                }
                
                VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
                    Text("My Vitality")
                        .font(DashboardDesign.bodySemiboldFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text(label(for: currentUser.currentScore))
                        .font(DashboardDesign.secondaryFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                }
                
                Spacer()
                
                // Clear, non-gauge comparison: current vs optimal (premium typography)
                VStack(alignment: .trailing, spacing: DashboardDesign.tinySpacing) {
                    Text("\(currentUser.currentScore)/\(max(currentUser.optimalScore, 1))")
                        .font(DashboardDesign.scoreSmallFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                    Text("Current / Optimal")
                        .font(DashboardDesign.tinyFont)
                        .foregroundColor(DashboardDesign.secondaryTextColor)
                    if let p = currentUser.progressScore {
                        Text("Progress: \(p)/100")
                            .font(DashboardDesign.tinyFont)
                            .foregroundColor(DashboardDesign.secondaryTextColor)
                    }
                }
            }
            
            if currentUser.optimalScore > 0 {
                ProgressView(value: Double(currentUser.currentScore), total: Double(currentUser.optimalScore))
                    .tint(DashboardDesign.miyaTealSoft)
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide submetrics" : "View submetrics")
                        .font(DashboardDesign.secondarySemiboldFont)
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DashboardDesign.miyaTealSoft)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                let sleep = myPillarScore(named: "Sleep")
                let movement = myPillarScore(named: "Activity")
                let stress = myPillarScore(named: "Recovery")
                
                HStack(spacing: DashboardDesign.internalSpacing) {
                    PillarMini(label: "Sleep", score: sleep)
                    PillarMini(label: "Movement", score: movement)
                    PillarMini(label: "Recovery", score: stress)
                }
            }
        }
        .padding(DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

struct PillarMini: View {
    let label: String
    let score: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.tinySpacing) {
            Text(label)
                .font(DashboardDesign.captionSemiboldFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            
            Text(score.map { "\($0)/100" } ?? "—")
                .font(DashboardDesign.bodySemiboldFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
        }
        .padding(.vertical, DashboardDesign.smallSpacing)
        .padding(.horizontal, DashboardDesign.internalSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardDesign.tertiaryBackgroundColor)
        .cornerRadius(DashboardDesign.smallCornerRadius)
    }
}
