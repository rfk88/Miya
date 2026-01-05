import Foundation

/// Lightweight, read-only interpretation layer derived mechanically from `VitalityBreakdown`.
/// No scoring changes, no new thresholds/ranges.
struct VitalityExplanation: Codable {
    
    struct Pillar: Codable, Identifiable {
        let id: String                 // matches PillarBreakdown.id ("sleep" | "movement" | "stress")
        let label: String              // "Sleep" / "Movement" / "Stress"
        let primaryLimiterSubmetricId: String?
        let primaryLimiterLabel: String?
        let lostPoints: Double?
        let text: String
    }
    
    let totalText: String
    let pillars: [Pillar]
    
    static func derive(from breakdown: VitalityBreakdown) -> VitalityExplanation {
        // Per pillar: choose submetric with largest loss (maxPoints - points).
        let pillarExplanations: [Pillar] = breakdown.pillars.map { pillar in
            let limiter: SubmetricBreakdown? = pillar.submetrics.max(by: { a, b in
                (a.maxPoints - a.points) < (b.maxPoints - b.points)
            })
            
            let limiterPhrase: String = {
                guard let lim = limiter else { return "no submetrics" }
                switch lim.status {
                case .missing:
                    return "missing \(lim.label.lowercasingFirstLetter())"
                case .low:
                    return "low \(lim.label.lowercasingFirstLetter())"
                case .ok, .optimal:
                    return lim.label.lowercasingFirstLetter()
                }
            }()
            
            let text = "\(pillar.label) score is limited mainly by \(limiterPhrase)."
            
            return Pillar(
                id: pillar.id,
                label: pillar.label,
                primaryLimiterSubmetricId: limiter?.id,
                primaryLimiterLabel: limiter?.label,
                lostPoints: limiter.map { $0.maxPoints - $0.points },
                text: text
            )
        }
        
        // Overall: choose the single submetric across all pillars with the largest loss.
        let allSubmetrics = breakdown.pillars.flatMap { $0.submetrics }
        let overallLimiter = allSubmetrics.max(by: { a, b in
            (a.maxPoints - a.points) < (b.maxPoints - b.points)
        })
        
        let overallPhrase: String = {
            guard let lim = overallLimiter else { return "no submetrics" }
            switch lim.status {
            case .missing:
                return "missing \(lim.label.lowercasingFirstLetter())"
            case .low:
                return "low \(lim.label.lowercasingFirstLetter())"
            case .ok, .optimal:
                return lim.label.lowercasingFirstLetter()
            }
        }()
        
        let totalText =
            "This vitality score was calculated using \(breakdown.pillarsUsed) of \(breakdown.pillarsPossible) pillars. Missing pillars do not reduce your score.\n" +
            "Your vitality is currently \(Int(breakdown.totalScore.rounded())) because \(overallPhrase) is the main limiting factor."
        
        return VitalityExplanation(
            totalText: totalText,
            pillars: pillarExplanations
        )
    }
}

private extension String {
    func lowercasingFirstLetter() -> String {
        guard let first = first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}


