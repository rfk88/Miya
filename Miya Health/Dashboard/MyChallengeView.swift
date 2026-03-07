import SwiftUI

// MARK: - My Challenge View
// Compact card showing the current user's active 7-day challenge progress.

struct MyChallengeView: View {
    let challenge: ActiveChallenge
    
    private var pillarDisplayName: String {
        switch challenge.pillar.lowercased() {
        case "sleep": return "Sleep"
        case "movement": return "Activity"
        case "stress": return "Recovery"
        default: return challenge.pillar.capitalized
        }
    }
    
    private var pillarIcon: String {
        switch challenge.pillar.lowercased() {
        case "sleep": return "moon.stars.fill"
        case "movement": return "figure.run"
        case "stress": return "heart.fill"
        default: return "flag.checkered"
        }
    }
    
    private var endDateFormatted: String? {
        guard let end = challenge.endDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: end) else { return end }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: date)
    }
    
    private var progressFraction: Double {
        let required = max(1, challenge.requiredSuccessDays)
        return Double(challenge.daysSucceeded) / Double(required)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: pillarIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.miyaPrimary)
                Text("Your \(pillarDisplayName) Challenge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.miyaPrimary)
                        .frame(width: max(0, geo.size.width * progressFraction), height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("Day \(challenge.daysEvaluated) of 7 · \(challenge.daysSucceeded) days hit so far")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                if let end = endDateFormatted {
                    Text("Ends \(end)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}
