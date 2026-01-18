import SwiftUI

// MARK: - DASHBOARD DESIGN SYSTEM

/// Premium design system for Dashboard components
/// Inspired by Apple Health's polish and iOS HIG patterns
enum DashboardDesign {
    // MARK: - Spacing (matching onboarding flow)
    static let cardPadding: CGFloat = 16  // Like onboarding cards
    static let cardSpacing: CGFloat = 20  // Between cards
    static let sectionSpacing: CGFloat = 24  // Between sections (like onboarding)
    static let internalSpacing: CGFloat = 16  // Inside cards
    static let smallSpacing: CGFloat = 12  // Between related elements
    static let tinySpacing: CGFloat = 8  // Tight spacing
    static let microSpacing: CGFloat = 4  // Very tight
    
    // MARK: - Corner radius (matching onboarding - 16 for cards)
    static let cardCornerRadius: CGFloat = 16  // Like onboarding cards
    static let smallCornerRadius: CGFloat = 12
    static let tinyCornerRadius: CGFloat = 10
    
    // MARK: - Shadows (stronger for depth and gloss effect)
    static let cardShadow = Shadow(
        color: Color.black.opacity(0.08),
        radius: 12,
        x: 0,
        y: 4
    )
    
    static let cardShadowLight = Shadow(
        color: Color.black.opacity(0.05),
        radius: 8,
        x: 0,
        y: 2
    )
    
    static let cardShadowStrong = Shadow(
        color: Color.black.opacity(0.12),
        radius: 16,
        x: 0,
        y: 6
    )
    
    // MARK: - Typography (smaller, cleaner - matching onboarding)
    static let largeTitleFont = Font.system(size: 20, weight: .bold, design: .default)  // Main titles
    static let titleFont = Font.system(size: 18, weight: .semibold, design: .default)  // Section titles
    static let title2Font = Font.system(size: 16, weight: .semibold, design: .default)  // Card titles
    static let sectionHeaderFont = Font.system(size: 15, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .default)  // Primary content
    static let bodySemiboldFont = Font.system(size: 15, weight: .semibold, design: .default)
    static let calloutFont = Font.system(size: 14, weight: .regular, design: .default)  // Card descriptions
    static let subheadlineFont = Font.system(size: 14, weight: .medium, design: .default)
    static let footnoteFont = Font.system(size: 13, weight: .regular, design: .default)
    static let secondaryFont = Font.system(size: 13, weight: .regular, design: .default)
    static let secondarySemiboldFont = Font.system(size: 13, weight: .semibold, design: .default)
    static let captionFont = Font.system(size: 12, weight: .regular, design: .default)
    static let captionSemiboldFont = Font.system(size: 12, weight: .semibold, design: .default)
    static let tinyFont = Font.system(size: 10, weight: .medium, design: .default)
    
    // Score fonts (for vitality numbers - compact sizing)
    static let scoreLargeFont = Font.system(size: 36, weight: .bold, design: .rounded)
    static let scoreMediumFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let scoreSmallFont = Font.system(size: 18, weight: .bold, design: .rounded)
    
    // MARK: - Colors (Real colors like onboarding - vibrant and clear)
    // Primary brand colors
    static let miyaTealSoft = Color.miyaPrimary  // Use actual brand color
    static let miyaEmeraldSoft = Color.miyaEmerald  // Use actual brand color
    
    // Pillar-specific colors (real, vibrant colors like onboarding)
    static let sleepColor = Color.purple  // Real purple like onboarding
    static let movementColor = Color.green  // Real green
    static let stressColor = Color.orange  // Real orange
    static let vitalityColor = Color.blue  // Real blue
    
    // Button tint (for Chat with Arlo)
    static let buttonTint = Color.blue  // Real blue
    
    // Background colors (warmer, softer)
    static var mainBackground: Color {
        Color(red: 0.98, green: 0.98, blue: 0.99)  // Very light warm gray
    }
    
    static var cardBackgroundColor: Color {
        Color.white  // Solid white, no transparency
    }
    
    static var groupedBackground: Color {
        Color(red: 0.97, green: 0.97, blue: 0.98)  // Subtle grouping
    }
    
    static var secondaryBackgroundColor: Color {
        Color(red: 0.97, green: 0.97, blue: 0.98)  // Light gray, no system adaptation
    }
    
    static var tertiaryBackgroundColor: Color {
        Color(red: 0.95, green: 0.95, blue: 0.97)  // Fixed light gray
    }
    
    // Text colors (matching onboarding - use actual Miya colors)
    static var primaryTextColor: Color {
        Color.miyaTextPrimary  // Use actual brand text color
    }
    
    static var secondaryTextColor: Color {
        Color.miyaTextSecondary  // Use actual brand secondary text
    }
    
    static var tertiaryTextColor: Color {
        Color.miyaTextSecondary.opacity(0.7)  // Lighter version
    }
    
    // MARK: - Glass Effect Helper (clean white cards)
    static func glassCardBackground(tint: Color = .white) -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(Color.white)
            .shadow(
                color: cardShadow.color,
                radius: cardShadow.radius,
                x: cardShadow.x,
                y: cardShadow.y
            )
    }
    
    // MARK: - Card Modifier (glass effect with enhanced shadows)
    struct GlassCardModifier: ViewModifier {
        let tint: Color
        
        func body(content: Content) -> some View {
            content
                .padding(cardPadding)
                .background(
                    DashboardDesign.glassCardBackground(tint: tint)
                )
        }
    }
    
    // MARK: - Card styling helper (legacy, for non-glass cards)
    static func cardStyle() -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(cardBackgroundColor)
            .shadow(
                color: cardShadow.color,
                radius: cardShadow.radius,
                x: cardShadow.x,
                y: cardShadow.y
            )
    }
    
    // MARK: - Standard Card Modifier (solid background)
    struct CardModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(cardBackgroundColor)
                )
                .shadow(
                    color: cardShadow.color,
                    radius: cardShadow.radius,
                    x: cardShadow.x,
                    y: cardShadow.y
                )
        }
    }
    
    // MARK: - Icon container styling (softer colors)
    static func iconContainer(size: CGFloat = 40, color: Color = miyaTealSoft) -> some View {
        Circle()
            .fill(color.opacity(0.15))  // Softer opacity
            .frame(width: size, height: size)
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Extension for Card Styling
extension View {
    func dashboardCardStyle() -> some View {
        self.modifier(DashboardDesign.CardModifier())
    }
    
    func glassCardStyle(tint: Color = .white) -> some View {
        self.modifier(DashboardDesign.GlassCardModifier(tint: tint))
    }
}

// MARK: - Helper Shapes
public struct ArcShape: Shape {
    /// 0.0 to 1.0 where 1.0 is a full TOP semicircle (left → right)
    var progress: Double
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Use a true semicircle centered horizontally.
        // The radius is constrained so the stroke won't get clipped.
        let lineWidth: CGFloat = 15 // should match/approx the gauge stroke width
        let radius = (min(rect.width, rect.height * 2) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY)

        let clamped = max(0.0, min(progress, 1.0))
        let startAngle = Angle.degrees(180)
        let endAngle = Angle.degrees(180 - (180 * clamped))
        
        // IMPORTANT: SwiftUI's coordinate system has Y pointing down.
        // To render the TOP semicircle (∩) from left → right, we must draw counterclockwise.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        
        return path
    }
}

// MARK: - TOP BAR
struct DashboardTopBar: View {
    let familyName: String
    let onShareTapped: () -> Void
    let onMenuTapped: () -> Void
    let onNotificationsTapped: () -> Void

    var body: some View {
        ZStack {
            // Premium header with softer emerald color
            DashboardDesign.miyaEmeraldSoft
                .ignoresSafeArea(edges: [.top])

            HStack(spacing: 0) {
                // LEFT — Burger menu (premium tap target)
                Button {
                    onMenuTapped()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                Spacer()

                // CENTER — Family name (refined typography, better spacing)
                Text("\(familyName) Family")
                    .font(DashboardDesign.sectionHeaderFont)
                    .foregroundColor(.white)

                Spacer()

                // RIGHT — Share + Notifications (improved spacing and tap targets)
                HStack(spacing: DashboardDesign.smallSpacing) {
                    Button {
                        onShareTapped()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    Button {
                        onNotificationsTapped()
                    } label: {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .padding(.horizontal, DashboardDesign.smallSpacing)
        }
        .frame(height: 56)
    }
}

// MARK: - Pillar Status Indicator

struct PillarStatusIndicator: View {
    let name: String
    let current: Int
    let target: Int
    
    var progress: Double {
        Double(current) / Double(target)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(Color.miyaPrimary, lineWidth: 3)
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                
                if progress >= 1.0 {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.system(size: 16, weight: .bold))
                } else {
                    Text("\(current)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                }
            }
            
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
