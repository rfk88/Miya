import SwiftUI

// MARK: - Profile View

struct ProfileView: View {
    let memberName: String
    let vitalityScore: Int
    let vitalityTrendDelta: Int
    let vitalityLabel: String
    
    // MARK: - Derived
    
    private var trendText: String {
        if vitalityTrendDelta > 0 {
            return "+\(vitalityTrendDelta) from last week"
        } else if vitalityTrendDelta < 0 {
            return "\(vitalityTrendDelta) from last week" // already negative
        } else {
            return "Same as last week"
        }
    }
    
    private var trendColor: Color {
        if vitalityTrendDelta > 0 {
            return .green
        } else if vitalityTrendDelta < 0 {
            return .red
        } else {
            return .secondary
        }
    }
    
    private var progressFraction: Double {
        max(0, min(Double(vitalityScore) / 100.0, 1.0))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    
                    // AVATAR + NAME (outside the card)
                    HStack(spacing: 12) {
                        // Avatar placeholder (circle + border)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 46, height: 46)
                            .overlay(
                                Circle()
                                    .stroke(Color.miyaTextSecondary.opacity(0.25), lineWidth: 1)
                            )
                            .overlay(
                                Text(initials(from: memberName))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.miyaTextPrimary)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(memberName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Text("Member in your family")
                                .font(.system(size: 12))
                                .foregroundColor(.miyaTextSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // TOP: VITALITY CARD WITH OURA-STYLE GAUGE
                    VStack(alignment: .leading, spacing: 16) {
                        SemiCircleGauge(
                            score: vitalityScore,
                            label: vitalityLabel,
                            progress: progressFraction,
                            trendText: trendText,
                            trendColor: trendColor
                        )
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                    
                    // ARLO HEALTH AGENT CARD
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("How is \(memberName) doing?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.miyaTextPrimary)
                            
                            Spacer()
                            
                            Text("AI health analysis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.miyaPrimary)
                        }
                        
                        Text("Arlo will summarise sleep, activity and stress trends for \(memberName) once wearables are connected to Miya.")
                            .font(.system(size: 12))
                            .foregroundColor(.miyaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button {
                            // Later: trigger Arlo insight sheet
                            print("Ask Arlo about \(memberName)")
                        } label: {
                            Text("Ask Arlo about \(memberName)")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.miyaPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(999)
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                    
                    // CURRENT CHALLENGE CARD (EMPTY STATE)
                    currentChallengeCard(for: memberName)
                }
                .padding(16)
            }
        }
        .navigationTitle("\(memberName)’s Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Current Challenge Card
    
    private func currentChallengeCard(for name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header row
            HStack {
                Text("Current challenge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
                
                Spacer()
            }
            .padding(.top, 4)
            
            // Content (mirrors dashboard Mission Hub empty state)
            VStack(spacing: 8) {
                Image(systemName: "trophy")
                    .font(.system(size: 24))
                    .foregroundColor(.miyaTextSecondary)
                
                Text("No active challenge for \(name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text("Start a new family challenge from the main dashboard and \(name)’s streak and dots will show here.")
                    .font(.system(size: 13))
                    .foregroundColor(.miyaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    // Later: jump back to dashboard / open Mission Hub sheet
                    print("Challenge \(name)")
                } label: {
                    Text("Challenge \(name)")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Helpers
    
    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last  = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combo = (first + last)
        return combo.isEmpty ? String(name.prefix(1)).uppercased() : combo.uppercased()
    }
}

// MARK: - Semicircle Vitality Gauge
// Note: ArcShape is defined in DashboardView.swift

struct SemiCircleGauge: View {
    let score: Int          // e.g. 72
    let label: String       // e.g. "Good"
    let progress: Double    // 0.0–1.0
    let trendText: String
    let trendColor: Color
    
    var body: some View {
        VStack(spacing: -30) {
            
            // Oura-style arc + centre icon
            ZStack {
                // Background arc (full semicircle)
                ArcShape(progress: 1.0)
                    .stroke(
                        Color(.systemGray5),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                
                // Active gradient arc (portion = progress)
                ArcShape(progress: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.8, blue: 0.75),
                                Color(red: 0.15, green: 0.55, blue: 1.0),
                                Color(red: 0.5, green: 0.3, blue: 1.0)
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                
                // Centre icon sitting on the arc
                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .overlay(
                        Image(systemName: "heart.fill")   // placeholder icon
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.miyaPrimary)
                    )
                    .offset(y: -18) // move it up into the arc
            }
            .frame(height: 110)
            
            // Compact text stack pulled closer to the arc
            VStack(spacing: 2) {
                Text("Vitality score")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.miyaTextSecondary)
                
                Text("\(score)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.miyaTextPrimary)
                
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.miyaTextSecondary)
                
                Text(trendText)
                    .font(.system(size: 13))
                    .foregroundColor(trendColor)
            }
            .padding(.top, -8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileView(
            memberName: "Mum",
            vitalityScore: 72,
            vitalityTrendDelta: 3,
            vitalityLabel: "Good"
        )
    }
}