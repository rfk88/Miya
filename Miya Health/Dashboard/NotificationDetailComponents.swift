import SwiftUI

// MARK: - Notification Detail UI Components
// Extracted from DashboardNotifications.swift for better compilation performance

// MARK: - Animated Typing Dot

struct TypingDot: View {
    let delay: Double
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.6))
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.4)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Whoop-Style Chat Bubble

struct WhoopStyleBubble: View {
    let message: ChatMessage
    let memberName: String
    
    private func parseMarkdown(_ markdown: String) -> AttributedString {
        // Parse markdown to AttributedString for bold, bullets, etc.
        do {
            var options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            options.allowsExtendedAttributes = true
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .miya {
                // Miya avatar - circular with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("M")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Message bubble - Whoop-style rounded with markdown support
                VStack(alignment: .leading, spacing: 0) {
                    Text(parseMarkdown(message.text))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.miyaTextPrimary)
                }
                .padding(14)
                .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                .cornerRadius(18)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
                
                Spacer()
            } else {
                Spacer()
                
                // User message bubble - blue gradient
                Text(message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(18)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.70, alignment: .trailing)
            }
        }
    }
}

// MARK: - Pill Prompt Grid (kept for suggestion shortcuts)

struct PillPromptGrid: View {
    let prompts: [PillPrompt]
    let onTap: (PillPrompt) -> Void
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(prompts) { prompt in
                PillButton(prompt: prompt) {
                    onTap(prompt)
                }
            }
        }
    }
}

struct PillButton: View {
    let prompt: PillPrompt
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(prompt.icon)
                    .font(.system(size: 14))
                Text(prompt.text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 0.82, green: 0.82, blue: 0.84), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Flow layout for pill wrapping (1-2 rows max)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: ProposedViewSize.unspecified)
        }
    }
}

struct FlowResult {
    var size: CGSize = .zero
    var positions: [CGPoint] = []
    
    init(in maxWidth: CGFloat, subviews: FlowLayout.Subviews, spacing: CGFloat) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        
        self.size = CGSize(width: maxWidth, height: y + lineHeight)
    }
}
