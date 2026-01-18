import SwiftUI

// MARK: - Insight System Components
// Extracted from DashboardView.swift - Phase 9 of refactoring

// MARK: - Family Vitality Insights Card

struct FamilyVitalityInsightsCard: View {
    let snapshot: FamilyVitalitySnapshot
    let trendInsights: [TrendInsight]
    let trendCoverage: TrendCoverageStatus?
    let membersWithData: Int?
    let membersTotal: Int?
    let onStartChallenge: (VitalityPillar) -> Void

    // MARK: - Pillar Visual Mapping
    
    private func pillarIcon(for pillar: VitalityPillar?) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        case .none: return "sparkles"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar?) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        case .none: return .miyaPrimary
        }
    }
    
    /// Whether we have actionable trend insights to show
    private var hasTrendInsights: Bool {
        !trendInsights.isEmpty
    }
    
    private var recommendations: [FamilyRecommendationRow] {
        FamilyRecommendationEngine.build(
            snapshot: snapshot,
            trendInsights: trendInsights,
            coverage: trendCoverage
        )
    }
    
    private var coverageState: (title: String, subtitle: String)? {
        guard let cov = trendCoverage else { return nil }
        if cov.daysAvailable == 0 {
            // Don't show this message - we're already showing snapshot insights below
            // The user is getting value from current-state insights, no need to confuse with "no trends"
            return nil
        }
        if !cov.hasMinimumCoverage {
            return ("Collecting your baseline", "Need \(cov.needMoreDataDays) more day\(cov.needMoreDataDays == 1 ? "" : "s") to detect patterns (based on last 21 days).")
        }
        return nil
    }
    
    /// The primary pillar to focus on (from trends or fallback to snapshot)
    private var primaryPillar: VitalityPillar? {
        trendInsights.first?.pillar ?? snapshot.focusPillar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // SECTION HEADER
            if hasTrendInsights {
                Text("What needs attention this week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            // TREND INSIGHT CARDS (highest priority - only show if we have trend data)
            if trendCoverage?.hasMinimumCoverage == true && hasTrendInsights {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(trendInsights.prefix(2)) { insight in
                        TrendInsightCard(insight: insight) {
                            onStartChallenge(insight.pillar)
                        }
                    }
                }
            } else if trendCoverage?.hasMinimumCoverage == true && !hasTrendInsights {
                // Have trend data but no insights detected
                VStack(alignment: .leading, spacing: 6) {
                    Text("No patterns detected")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Text("We'll alert you when a meaningful change appears.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if snapshot.membersIncluded == 0 {
                // No members with data at all
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No recent data yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        
                        Text("Connect wearables and sync data to see family insights.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            } else {
                // FALLBACK: Show snapshot-based insights (from current member scores)
                // This shows even when we don't have trend data yet
                
                // Show coverage message as informational context (not a blocker)
                if let cov = coverageState {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cov.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                        Text(cov.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Show snapshot headline and help cards
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(pillarColor(for: primaryPillar).opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: pillarIcon(for: primaryPillar))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(pillarColor(for: primaryPillar))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let sub = snapshot.subheadline {
                            Text(sub)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Show help cards from snapshot (member-based insights)
                if !snapshot.helpCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.helpCards.prefix(2)) { card in
                            FamilyHelpActionCard(card: card) {
                                onStartChallenge(card.focusPillar)
                            }
                        }
                    }
                }
            }
            
            // ACTIONABLE RECOMMENDATIONS (if coverage ok and insights exist)
            if trendCoverage?.hasMinimumCoverage == true && !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What to do this week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(recommendations.prefix(2)) { row in
                        RecommendationRowView(row: row, onTap: {
                            onStartChallenge(row.pillar)
                        })
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Trend Insight Card

struct TrendInsightCard: View {
    let insight: TrendInsight
    let onAction: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    private func severityColor(for severity: TrendSeverity) -> Color {
        switch severity {
        case .attention: return .orange
        case .watch: return .yellow
        case .celebrate: return .green
        }
    }
    
    private func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: Avatar + Title
            HStack(spacing: 10) {
                // Avatar with pillar color
                Circle()
                    .fill(pillarColor(for: insight.pillar).opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(makeInitials(from: insight.memberName))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pillarColor(for: insight.pillar))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    // Title: "Dad · Sleep"
                    Text(insight.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    // Body: one-liner insight
                    Text(insight.body)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            // CTA Button
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Image(systemName: pillarIcon(for: insight.pillar))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start \(insight.pillar.displayName) Challenge")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pillarColor(for: insight.pillar))
                .foregroundColor(.white)
                .cornerRadius(999)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
        )
    }
}

// MARK: - Recommendation Row View

struct RecommendationRowView: View {
    let row: FamilyRecommendationRow
    let onTap: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "bed.double.fill"
        case .movement: return "figure.walk"
        case .stress: return "exclamationmark.circle"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pillarIcon(for: row.pillar))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(pillarColor(for: row.pillar))
                .frame(width: 20)
            
            Text(row.text)
                .font(.system(size: 13))
                .foregroundColor(.miyaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Family Help Action Card (Premium Style)

struct FamilyHelpActionCard: View {
    let card: MemberHelpCard
    let onAction: () -> Void
    
    private func pillarIcon(for pillar: VitalityPillar) -> String {
        switch pillar {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .stress: return "heart.fill"
        }
    }
    
    private func pillarColor(for pillar: VitalityPillar) -> Color {
        switch pillar {
        case .sleep: return .purple
        case .movement: return .green
        case .stress: return .orange
        }
    }
    
    private func makeInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Member row
            HStack(spacing: 10) {
                // Avatar
                Circle()
                    .fill(pillarColor(for: card.focusPillar).opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(makeInitials(from: card.memberName))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pillarColor(for: card.focusPillar))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text(card.recommendation)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            // CTA Button (full width, pill style)
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Image(systemName: pillarIcon(for: card.focusPillar))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start \(card.focusPillar.displayName) Challenge")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pillarColor(for: card.focusPillar))
                .foregroundColor(.white)
                .cornerRadius(999)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
        )
    }
}
