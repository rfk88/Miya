import SwiftUI
import Charts

// MARK: - Shared weekly line chart

private struct FamilyWeeklyLineChart: View {
    let title: String
    let subtitle: String
    let series: [FamilyVitalityWeeklyAggregates.WeeklyPoint]
    let accent: Color
    let isLoading: Bool
    let error: String?

    @State private var selectedPoint: FamilyVitalityWeeklyAggregates.WeeklyPoint?

    private var sortedSeries: [FamilyVitalityWeeklyAggregates.WeeklyPoint] {
        series.sorted { $0.weekStartDate < $1.weekStartDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading trend…")
                        .font(.system(size: 14))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(.vertical, 18)
            } else if let err = error {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTerracottaDark)
                    .fixedSize(horizontal: false, vertical: true)
            } else if sortedSeries.count < 2 {
                Text("Not enough data yet for a weekly trend. Keep syncing — we’ll chart your last several weeks once there are at least two full weeks of scores.")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart {
                    RuleMark(y: .value("Mid", 50))
                        .foregroundStyle(Color.black.opacity(0.07))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    if let selectedPoint {
                        RuleMark(x: .value("Selected week", selectedPoint.weekStartDate))
                            .foregroundStyle(accent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        RuleMark(y: .value("Selected score", selectedPoint.value))
                            .foregroundStyle(accent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    ForEach(sortedSeries) { p in
                        AreaMark(
                            x: .value("Week", p.weekStartDate),
                            y: .value("Score", p.value)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.2), accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Week", p.weekStartDate),
                            y: .value("Score", p.value)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(accent)

                        if let last = sortedSeries.last, last.id == p.id {
                            PointMark(
                                x: .value("Week", p.weekStartDate),
                                y: .value("Score", p.value)
                            )
                            .symbolSize(36)
                            .foregroundStyle(accent)
                        }
                    }

                    if let selectedPoint {
                        PointMark(
                            x: .value("Selected week", selectedPoint.weekStartDate),
                            y: .value("Selected score", selectedPoint.value)
                        )
                        .symbolSize(64)
                        .foregroundStyle(accent)
                        .annotation(position: .top, alignment: .center) {
                            selectedPointAnnotation(selectedPoint)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: sortedSeries.map(\.weekStartDate)) { _ in
                        AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.miyaTextTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                        AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                        AxisValueLabel {
                            if let iv = v.as(Int.self) {
                                Text("\(iv)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.miyaTextTertiary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelectedPoint(
                                            at: value.location,
                                            proxy: proxy,
                                            geometry: geometry
                                        )
                                    }
                                    .onEnded { _ in
                                        selectedPoint = nil
                                    }
                            )
                    }
                }
                .frame(height: 190)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Each point is your family’s average for that week on a 0–100 scale (higher is stronger).")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if sortedSeries.count >= 2,
                       let last = sortedSeries.last,
                       let prev = sortedSeries.dropLast().last {
                        let lastI = Int(last.value.rounded())
                        let prevI = Int(prev.value.rounded())
                        Text("Latest week: \(lastI) · Previous: \(prevI)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.miyaTextPrimary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func selectedPointAnnotation(_ point: FamilyVitalityWeeklyAggregates.WeeklyPoint) -> some View {
        VStack(spacing: 2) {
            Text(weekLabel(for: point.weekStartDate))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
            Text("\(Int(point.value.rounded()))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.miyaTextPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.miyaCardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func updateSelectedPoint(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard plotFrame.contains(location),
              let date: Date = proxy.value(atX: location.x - plotFrame.origin.x)
        else { return }

        selectedPoint = sortedSeries.min { lhs, rhs in
            abs(lhs.weekStartDate.timeIntervalSince(date)) < abs(rhs.weekStartDate.timeIntervalSince(date))
        }
    }

    private func weekLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Deeper insights (collapsible)

private struct DeeperInsightsExpandableCard: View {
    let output: DeeperInsightsOutput

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Deeper insights")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.miyaTextTertiary)
                }
                .padding(.bottom, isExpanded ? 10 : 0)
            }
            .buttonStyle(.plain)

            Text(output.evidenceSummary)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.miyaTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(isExpanded ? nil : 3)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !output.interpretation.isEmpty {
                        Text(output.interpretation)
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let support = output.supportAction, !support.isEmpty {
                        Text(support)
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(output.familyAction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(output.footnote)
                        .font(.system(size: 11))
                        .foregroundColor(.miyaTextTertiary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Compact weekly spark (pillar rows)

private struct FamilyWeeklyMicroSparkline: View {
    let series: [FamilyVitalityWeeklyAggregates.WeeklyPoint]
    let color: Color
    /// When true, chart grows horizontally with parent (member rows); when false, fixed 88pt (pillar list).
    var usesFullWidth: Bool = false

    private var sorted: [FamilyVitalityWeeklyAggregates.WeeklyPoint] {
        series.sorted { $0.weekStartDate < $1.weekStartDate }
    }

    var body: some View {
        Group {
            if sorted.count < 2 {
                Text("—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.miyaTextTertiary)
                    .frame(maxWidth: usesFullWidth ? .infinity : nil)
                    .frame(width: usesFullWidth ? nil : 88, height: 24)
            } else {
                Chart {
                    ForEach(sorted) { p in
                        LineMark(
                            x: .value("Week", p.weekStartDate),
                            y: .value("Score", p.value)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 24)
                .frame(maxWidth: usesFullWidth ? .infinity : nil)
                .frame(width: usesFullWidth ? nil : 88)
            }
        }
    }
}

// MARK: - Overview member row (vitality bar + optional weekly spark)

private struct FamilyVitalityOverviewMemberRow: View {
    let member: FamilyMemberScore
    let scoreRows: [DataManager.FamilyVitalityScoreRow]
    let alertMemberIds: Set<String>
    let familyId: String?

    private var showsFill: Bool { member.hasScore && !member.isStale }
    private var scoreVal: Int { max(0, min(100, member.currentScore)) }
    private var sparkSeries: [FamilyVitalityWeeklyAggregates.WeeklyPoint] {
        guard let uid = member.userId else { return [] }
        return FamilyVitalityWeeklyAggregates.weeklyMemberTotalSeries(rows: scoreRows, userId: uid, maxWeeks: 6)
    }
    private var hasAlert: Bool {
        member.userId.map { alertMemberIds.contains($0.lowercased()) } ?? false
    }

    var body: some View {
        Group {
            if let fid = familyId, let uid = member.userId {
                NavigationLink {
                    FamilyMemberProfileView(
                        memberUserId: uid,
                        memberName: member.name,
                        familyId: fid,
                        isCurrentUser: member.isMe
                    )
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(avatarBackground)
                    .frame(width: 46, height: 46)
                Text(member.initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(avatarForeground)
            }
            .overlay(alignment: .bottomTrailing) {
                if hasAlert {
                    Circle()
                        .fill(Color.miyaAmber)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(member.isMe ? "Me" : member.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                VitalityScoreTrack(
                    percent0To100: scoreVal,
                    showsFill: showsFill,
                    height: 8
                )

                if sparkSeries.count >= 2 {
                    FamilyWeeklyMicroSparkline(series: sparkSeries, color: .miyaPrimary, usesFullWidth: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if showsFill {
                    Text("\(scoreVal)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.miyaTextPrimary)
                } else if member.isStale {
                    Text("Out of date")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.miyaTextTertiary)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("—")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.miyaTextTertiary)
                }
            }
            .frame(minWidth: 56, alignment: .trailing)

            if familyId != nil, member.userId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.miyaTextTertiary)
            }
        }
        .padding(.vertical, 10)
    }

    private var avatarBackground: Color {
        guard member.hasScore, !member.isStale else { return Color(hex: "F4F1ED") }
        if member.currentScore >= 75 { return Color(hex: "B8E4EF") }
        if member.currentScore >= 55 { return Color(hex: "FAE5C0") }
        return Color(hex: "F5C9C4")
    }

    private var avatarForeground: Color {
        guard member.hasScore, !member.isStale else { return Color(hex: "9CA3AF") }
        if member.currentScore >= 75 { return Color(hex: "0E7490") }
        if member.currentScore >= 55 { return Color(hex: "9A6B1A") }
        return Color(hex: "A0554B")
    }
}

// MARK: - Profile pillar mapping (VitalityPillar → FamilyMemberProfileView.PillarType)

extension VitalityPillar {
    /// `FamilyMemberProfileView` / navigation use `PillarType.recovery` for stress pillar.
    var memberProfilePillar: PillarType {
        switch self {
        case .sleep: return .sleep
        case .movement: return .movement
        case .stress: return .recovery
        }
    }

    fileprivate var vitalityFactorName: String {
        switch self {
        case .sleep: return "Sleep"
        case .movement: return "Activity"
        case .stress: return "Recovery"
        }
    }
}

// MARK: - Family Vitality Overview (pushed from dashboard hero)

struct FamilyVitalityOverviewView: View {
    @EnvironmentObject private var dataManager: DataManager

    let familyScore: Int
    let verdict: String
    let membersWithData: Int?
    let membersTotal: Int?
    let vitalityFactors: [VitalityFactor]
    let fourWeekDelta: Int?
    let familySnapshot: FamilyVitalitySnapshot?
    let trendInsights: [TrendInsight]
    let trendCoverage: TrendCoverageStatus?
    let familyMembers: [FamilyMemberScore]
    let alertMemberIds: Set<String>

    @State private var scoreRows: [DataManager.FamilyVitalityScoreRow] = []
    @State private var isLoadingChart = false
    @State private var chartLoadError: String?

    private var weeklyTotalSeries: [FamilyVitalityWeeklyAggregates.WeeklyPoint] {
        FamilyVitalityWeeklyAggregates.weeklyFamilyTotalSeries(rows: scoreRows, maxWeeks: 6)
    }

    private var viewerUserId: String? {
        familyMembers.first(where: \.isMe)?.userId
    }

    private var keyFindingBullets: [String] {
        FamilyVitalityKeyFindingsComposer.bullets(
            snapshot: familySnapshot,
            trendInsights: trendInsights,
            trendCoverage: trendCoverage,
            filterPillar: nil,
            factors: vitalityFactors,
            maxCount: 3,
            viewerUserId: viewerUserId
        )
    }

    private var deeperInsightsInput: DeeperInsightsInput {
        DeeperInsightsInput(
            scoreRows: scoreRows,
            vitalityFactors: vitalityFactors,
            familyMembers: familyMembers,
            familySnapshot: familySnapshot,
            trendInsights: trendInsights,
            trendCoverage: trendCoverage,
            fourWeekDelta: fourWeekDelta,
            asOf: Date()
        )
    }

    private var deeperInsightsFamilyCard: some View {
        DeeperInsightsExpandableCard(
            output: FamilyVitalityDeeperInsightsComposer.build(scope: .family, input: deeperInsightsInput)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardDesign.cardSpacing) {
                FamilyVitalityHeroCard(
                    score: familyScore,
                    verdict: verdict,
                    membersWithData: membersWithData,
                    membersTotal: membersTotal,
                    factors: vitalityFactors,
                    fourWeekDelta: fourWeekDelta,
                    showPillars: false
                )

                findingsCard

                FamilyWeeklyLineChart(
                    title: "Family score",
                    subtitle: "By week",
                    series: weeklyTotalSeries,
                    accent: .miyaPrimary,
                    isLoading: isLoadingChart,
                    error: chartLoadError
                )

                deeperInsightsFamilyCard

                pillarsCard

                membersSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.miyaBackground.ignoresSafeArea())
        .navigationTitle("Family vitality")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }

    // MARK: Findings

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key findings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(keyFindingBullets.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.miyaTextTertiary)
                        Text(line)
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: Pillars

    private var pillarsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pillars")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            VStack(spacing: 0) {
                ForEach(Array(VitalityPillar.allCases.enumerated()), id: \.element.rawValue) { index, pillar in
                    pillarRow(pillar)
                    if index < VitalityPillar.allCases.count - 1 {
                        Divider().padding(.leading, 4)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func pillarRow(_ pillar: VitalityPillar) -> some View {
        let factor = vitalityFactors.first { $0.name == pillar.vitalityFactorName }
        let band = factor.map { PillarStateBand.band(for: $0) } ?? .noData

        return NavigationLink {
            PillarDetailView(
                vitalityFactors: vitalityFactors,
                familySnapshot: familySnapshot,
                trendInsights: trendInsights,
                trendCoverage: trendCoverage,
                familyMembers: familyMembers,
                initialPillar: pillar
            )
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(pillar.heroDotColor)
                    .frame(width: 10, height: 10)

                Text(pillar.dashboardDisplayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)

                Spacer()

                Text(band.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.miyaTextTertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Family members")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            VStack(spacing: 0) {
                ForEach(Array(familyMembers.enumerated()), id: \.element.id) { index, member in
                    FamilyVitalityOverviewMemberRow(
                        member: member,
                        scoreRows: scoreRows,
                        alertMemberIds: alertMemberIds,
                        familyId: dataManager.currentFamilyId
                    )
                    if index < familyMembers.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.miyaCardWhite)
            .cornerRadius(DashboardDesign.cardCornerRadius)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Load

    private func loadHistory() async {
        await MainActor.run {
            isLoadingChart = true
            chartLoadError = nil
        }
        let userIds = familyMembers.compactMap(\.userId)
        do {
            let rows = try await FamilyVitalityHistoryFetch.loadFamilyScoreRows(
                dataManager: dataManager,
                familyMemberUserIds: userIds
            )
            await MainActor.run {
                scoreRows = rows
                isLoadingChart = false
            }
        } catch {
            await MainActor.run {
                isLoadingChart = false
                chartLoadError = "Couldn’t load weekly history. You can still read today’s snapshot above."
            }
        }
    }
}

// MARK: - Pillar detail member row (pillar score bar + optional weekly spark)

private struct PillarDetailMemberRow: View {
    let member: FamilyMemberScore
    let stateLabel: String
    let pillarScore: Int
    let showsFill: Bool
    let sparkSeries: [FamilyVitalityWeeklyAggregates.WeeklyPoint]
    let pillarAccent: Color
    let selectedPillar: VitalityPillar
    let familyId: String?

    var body: some View {
        Group {
            if let fid = familyId, let uid = member.userId {
                NavigationLink {
                    FamilyMemberProfileView(
                        memberUserId: uid,
                        memberName: member.name,
                        familyId: fid,
                        isCurrentUser: member.isMe,
                        initialPillar: selectedPillar.memberProfilePillar
                    )
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(selectedPillar.heroDotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(member.isMe ? "Me" : member.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                Text(stateLabel)
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)

                VitalityScoreTrack(
                    percent0To100: pillarScore,
                    showsFill: showsFill,
                    height: 8,
                    fillGradient: [pillarAccent, Color.miyaTealLight]
                )

                if sparkSeries.count >= 2 {
                    FamilyWeeklyMicroSparkline(series: sparkSeries, color: pillarAccent, usesFullWidth: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if showsFill {
                    Text("\(pillarScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.miyaTextPrimary)
                } else {
                    Text("—")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.miyaTextTertiary)
                }
            }
            .frame(minWidth: 40, alignment: .trailing)
            .padding(.top, 2)

            if familyId != nil, member.userId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.miyaTextTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Pillar detail (tabbed)

struct PillarDetailView: View {
    @EnvironmentObject private var dataManager: DataManager

    let vitalityFactors: [VitalityFactor]
    let familySnapshot: FamilyVitalitySnapshot?
    let trendInsights: [TrendInsight]
    let trendCoverage: TrendCoverageStatus?
    let familyMembers: [FamilyMemberScore]

    @State private var selectedPillar: VitalityPillar

    @State private var scoreRows: [DataManager.FamilyVitalityScoreRow] = []
    @State private var isLoadingChart = false
    @State private var chartLoadError: String?

    init(
        vitalityFactors: [VitalityFactor],
        familySnapshot: FamilyVitalitySnapshot?,
        trendInsights: [TrendInsight],
        trendCoverage: TrendCoverageStatus?,
        familyMembers: [FamilyMemberScore],
        initialPillar: VitalityPillar
    ) {
        self.vitalityFactors = vitalityFactors
        self.familySnapshot = familySnapshot
        self.trendInsights = trendInsights
        self.trendCoverage = trendCoverage
        self.familyMembers = familyMembers
        _selectedPillar = State(initialValue: initialPillar)
    }

    private var factor: VitalityFactor? {
        vitalityFactors.first { $0.name == selectedPillar.vitalityFactorName }
    }

    private var weeklyPillarSeries: [FamilyVitalityWeeklyAggregates.WeeklyPoint] {
        FamilyVitalityWeeklyAggregates.weeklyFamilyPillarSeries(rows: scoreRows, pillar: selectedPillar, maxWeeks: 6)
    }

    private var pillarAccent: Color {
        switch selectedPillar {
        case .sleep: return Color(hex: "C4B5D9")
        case .movement: return Color(hex: "7DD3C7")
        case .stress: return selectedPillar.heroDotColor
        }
    }

    /// Softer than full accent so the hero stays readable; matches pillar chroma.
    private var pillarHeroGradient: LinearGradient {
        LinearGradient(
            colors: [
                pillarAccent.opacity(0.50),
                pillarAccent.opacity(0.22),
                Color.miyaCardWhite.opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Caption + band label on tinted fill: darker than global secondary.
    private var pillarHeroMutedForeground: Color {
        Color.miyaTextPrimary.opacity(0.78)
    }

    private var pillarBullets: [String] {
        FamilyVitalityKeyFindingsComposer.bullets(
            snapshot: familySnapshot,
            trendInsights: trendInsights,
            trendCoverage: trendCoverage,
            filterPillar: selectedPillar,
            factors: vitalityFactors,
            maxCount: 3,
            viewerUserId: familyMembers.first(where: \.isMe)?.userId
        )
    }

    private var pillarDeeperInsightsInput: DeeperInsightsInput {
        DeeperInsightsInput(
            scoreRows: scoreRows,
            vitalityFactors: vitalityFactors,
            familyMembers: familyMembers,
            familySnapshot: familySnapshot,
            trendInsights: trendInsights,
            trendCoverage: trendCoverage,
            fourWeekDelta: nil,
            asOf: Date()
        )
    }

    private var pillarDeeperInsightsCard: some View {
        DeeperInsightsExpandableCard(
            output: FamilyVitalityDeeperInsightsComposer.build(
                scope: .pillar(selectedPillar),
                input: pillarDeeperInsightsInput
            )
        )
        .id(selectedPillar.rawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardDesign.cardSpacing) {
                pillarPicker

                pillarHeroCard

                pillarFindingsCard

                FamilyWeeklyLineChart(
                    title: "\(selectedPillar.dashboardDisplayName) — family",
                    subtitle: "By week",
                    series: weeklyPillarSeries,
                    accent: pillarAccent,
                    isLoading: isLoadingChart,
                    error: chartLoadError
                )

                pillarDeeperInsightsCard

                memberRowsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.miyaBackground.ignoresSafeArea())
        .navigationTitle(selectedPillar.dashboardDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }

    private var pillarPicker: some View {
        Picker("Pillar", selection: Binding(
            get: { selectedPillar },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.22)) {
                    selectedPillar = newValue
                }
            }
        )) {
            ForEach(VitalityPillar.allCases, id: \.rawValue) { p in
                Text(p.dashboardDisplayName).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    private var pillarHeroCard: some View {
        let f = factor
        let band = f.map { PillarStateBand.band(for: $0) } ?? .noData
        let pct = f?.percent ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(selectedPillar.heroDotColor)
                    .frame(width: 12, height: 12)
                Text("Family \(selectedPillar.dashboardDisplayName.lowercased())")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(pillarHeroMutedForeground)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(pct)")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundColor(Color.miyaTextPrimary)
                Text(band.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(pillarHeroMutedForeground)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                .fill(pillarHeroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardDesign.cardCornerRadius, style: .continuous)
                .stroke(Color.miyaTextPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var pillarFindingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key findings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(pillarBullets.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.miyaTextTertiary)
                        Text(line)
                            .font(.system(size: 14))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private var memberRowsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.miyaTextPrimary)

            if let f = factor, !f.memberScores.isEmpty {
                let sortedMembers = sortedMemberScores(for: f)
                VStack(spacing: 0) {
                    ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { index, member in
                        memberRow(member: member, templateFactor: f)
                        if index < sortedMembers.count - 1 {
                            Divider()
                        }
                    }
                }
            } else {
                Text("No member breakdown available for this pillar yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.miyaTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaCardWhite)
        .cornerRadius(DashboardDesign.cardCornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func sortedMemberScores(for factor: VitalityFactor) -> [FamilyMemberScore] {
        factor.memberScores.sorted { lhs, rhs in
            let lhsRank = memberDataRank(lhs)
            let rhsRank = memberDataRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func memberDataRank(_ member: FamilyMemberScore) -> Int {
        if member.hasScore && !member.isStale { return 0 }
        if member.isStale { return 1 }
        return 2
    }

    private func memberRow(member: FamilyMemberScore, templateFactor: VitalityFactor) -> some View {
        let label = memberStateLabel(member: member, templateFactor: templateFactor)
        let row = templateFactor.memberScores.first(where: { $0.userId == member.userId })
        let showsFill = (row?.hasScore == true) && (row?.isStale == false)
        let pct = row.map { max(0, min(100, $0.currentScore)) } ?? 0
        let spark: [FamilyVitalityWeeklyAggregates.WeeklyPoint] = {
            guard let uid = member.userId else { return [] }
            return FamilyVitalityWeeklyAggregates.weeklyMemberPillarSeries(
                rows: scoreRows,
                userId: uid,
                pillar: selectedPillar,
                maxWeeks: 6
            )
        }()

        return PillarDetailMemberRow(
            member: member,
            stateLabel: label,
            pillarScore: pct,
            showsFill: showsFill,
            sparkSeries: spark,
            pillarAccent: pillarAccent,
            selectedPillar: selectedPillar,
            familyId: dataManager.currentFamilyId
        )
    }

    private func memberStateLabel(member: FamilyMemberScore, templateFactor: VitalityFactor) -> String {
        guard let row = templateFactor.memberScores.first(where: { $0.userId == member.userId }) else {
            return "No data yet"
        }
        let pct = max(0, min(100, row.hasScore && !row.isStale ? row.currentScore : 0))
        let synthetic = VitalityFactor(
            name: templateFactor.name,
            iconName: templateFactor.iconName,
            percent: pct,
            description: templateFactor.description,
            actionPlan: templateFactor.actionPlan,
            memberScores: [row]
        )
        return PillarStateBand.band(for: synthetic).label
    }

    private func loadHistory() async {
        await MainActor.run {
            isLoadingChart = true
            chartLoadError = nil
        }
        let userIds = familyMembers.compactMap(\.userId)
        do {
            let rows = try await FamilyVitalityHistoryFetch.loadFamilyScoreRows(
                dataManager: dataManager,
                familyMemberUserIds: userIds
            )
            await MainActor.run {
                scoreRows = rows
                isLoadingChart = false
            }
        } catch {
            await MainActor.run {
                isLoadingChart = false
                chartLoadError = "Couldn’t load weekly history for this pillar."
            }
        }
    }
}
