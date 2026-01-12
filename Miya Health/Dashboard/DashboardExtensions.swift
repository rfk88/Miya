import SwiftUI

// MARK: - Expandable Insight Section

struct ExpandableInsightSection<Content: View>: View {
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    let backgroundColor: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible, tappable)
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(icon)
                        .font(.system(size: 20))
                    
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.miyaTextSecondary)
                }
                .padding(20)
                .background(backgroundColor)
                .cornerRadius(12, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
            }
            .buttonStyle(.plain)
            
            // Content (collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(20)
                .padding(.top, 0)
                .background(backgroundColor)
                .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Helper for selective corner radius

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
