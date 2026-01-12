import SwiftUI
import SwiftUIX

// MARK: - Minimal loaders (keep layout stable; avoid flashing placeholders)

struct DashboardInlineLoaderCard: View {
    let title: String
    
    var body: some View {
        HStack(spacing: DashboardDesign.internalSpacing) {
            ActivityIndicator()
                .animated(true)
                .style(.regular)
            Text("Loading \(title)…")
                .font(DashboardDesign.bodyFont)
                .foregroundColor(DashboardDesign.secondaryTextColor)
            Spacer()
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.vertical, DashboardDesign.internalSpacing)
        .background(DashboardDesign.glassCardBackground(tint: .white))
    }
}

struct FamilyVitalityLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.internalSpacing) {
            Text("Family vitality")
                .font(DashboardDesign.sectionHeaderFont)
                .foregroundColor(DashboardDesign.primaryTextColor)
                .padding(.top, DashboardDesign.cardPadding)
            
            Spacer()
            
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ActivityIndicator()
                        .animated(true)
                        .style(.large)
                    Text("Loading family score…")
                        .font(DashboardDesign.bodySemiboldFont)
                        .foregroundColor(DashboardDesign.primaryTextColor)
                }
                Spacer()
            }
            
            Spacer()
        }
        .padding(.horizontal, DashboardDesign.cardPadding)
        .padding(.bottom, DashboardDesign.cardPadding)
        .background(DashboardDesign.glassCardBackground(tint: .white))
        .frame(minHeight: 200)
    }
}

struct LoadingStepRow: View {
    let step: Int
    let currentStep: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(textColor)
        }
    }
    
    private var iconName: String {
        if currentStep > step {
            return "checkmark.circle.fill"
        } else if currentStep == step {
            return "arrow.right.circle.fill"
        } else {
            return "circle"
        }
    }
    
    private var iconColor: Color {
        if currentStep > step {
            return .green
        } else if currentStep == step {
            return .blue
        } else {
            return .miyaTextSecondary.opacity(0.4)
        }
    }
    
    private var textColor: Color {
        if currentStep >= step {
            return .miyaTextPrimary
        } else {
            return .miyaTextSecondary.opacity(0.6)
        }
    }
}
