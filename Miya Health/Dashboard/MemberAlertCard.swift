import SwiftUI

// MARK: - Member alert card (redesign)

/// Terracotta-bordered card surfaced for each family member whose longest
/// active server pattern alert has reached 3+ consecutive days.
///
/// One card per member, regardless of how many pillars triggered. The card
/// keeps the collapsed state calm, then surfaces contextual support actions
/// after the user expands the card.
struct MemberAlertCard: View {
    let alert: ConsolidatedMemberAlert
    let representativeItem: FamilyNotificationItem
    let supportPresentation: AlertSupportPresentation
    let isExpanded: Bool
    let currentUserId: String?
    /// Optional resolved name of the person who last acted on the alert,
    /// used to render "Sent by …". Pass `nil` to hide.
    let actedByName: String?

    let onDismiss: (ConsolidatedMemberAlert) -> Void
    let onToggleExpand: (ConsolidatedMemberAlert) -> Void
    let onSnooze: (FamilyNotificationItem, Int?) -> Void
    let onSendMessage: (FamilyNotificationItem, AlertSupportPresentation) -> Void
    let onStartSupportChallenge: (FamilyNotificationItem, AlertSupportPresentation) -> Void
    /// Opens the notification detail sheet with pill-based chat (check-in flow).
    let onOpenAlertChat: (ConsolidatedMemberAlert) -> Void

    @State private var showSnoozeDialog = false

    private var alertBorder: Color { Color.miyaAlertBorder }
    private var alertBackground: Color { Color.miyaAlertSurface }

    private var pillarsLine: String {
        let names = alert.pillars.map { $0.dashboardDisplayName }
        if names.isEmpty {
            return ""
        }
        if names.count == 1 {
            return "\(names[0]) low"
        }
        let joined = names.joined(separator: " · ")
        return "\(joined) all low"
    }

    private var titleLine: String {
        let plural = alert.signalCount == 1 ? "signal" : "signals"
        let dayPlural = alert.maxDurationDays == 1 ? "day" : "days"
        let subject = MemberProfileOwnVoice.isCurrentUser(
            memberUserId: alert.memberUserId,
            authUserId: currentUserId
        ) ? "You" : alert.firstName
        return "\(subject) — \(alert.signalCount) \(plural), \(alert.maxDurationDays) \(dayPlural)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Rectangle()
                .fill(Color.miyaAlertBorder)
                .frame(height: 0.5)
            actionRow
            if isExpanded {
                expandedBody
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(alertBackground)
                Rectangle()
                    .fill(Color.miyaAlertCoral)
                    .frame(width: 4)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(alertBorder, lineWidth: 1)
        )
        .shadow(color: Color.miyaAlertCoral.opacity(0.10), radius: 16, x: 0, y: 8)
        .alert("Are you sure you want to snooze this?", isPresented: $showSnoozeDialog) {
            Button("Snooze (\(snoozeDefaultDays) days)") {
                onSnooze(representativeItem, snoozeDefaultDays)
            }
            Button("Not a concern (30 days)") {
                onSnooze(representativeItem, 30)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header row (avatar + text + dismiss)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.miyaAlertCoral.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.miyaAlertCoral.opacity(0.10), lineWidth: 0.75)
                    )
                Text(alert.memberInitials)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.miyaAlertCoral)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.miyaDashboardTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(pillarsLine)
                    .font(.system(size: 13))
                    .foregroundColor(.miyaDashboardTextSecond)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Action row (snooze / see why / sent-by)

    private var actionRow: some View {
        HStack(spacing: 16) {
            actionButton(systemImage: isExpanded ? "info.circle.fill" : "info.circle", label: isExpanded ? "Hide" : "See why") {
                onToggleExpand(alert)
            }
            actionButton(systemImage: "moon.zzz", label: "Snooze") {
                showSnoozeDialog = true
            }
            Spacer(minLength: 0)
            if let name = actedByName, !name.isEmpty {
                Text("Sent by \(name)")
                    .font(.system(size: 11))
                    .foregroundColor(.miyaDashboardTextSecond.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func actionButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.miyaDashboardTextSecond)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Expanded body

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.miyaTextPrimary.opacity(0.08))
                .frame(height: 0.5)

            Text(representativeItem.body)
                .font(.system(size: 15))
                .foregroundColor(.miyaDashboardTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            supportActionBlock

            if let careCopy = careContextLine {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaAlertCoral.opacity(0.85))
                    Text(careCopy)
                        .font(.system(size: 12))
                        .foregroundColor(.miyaDashboardTextSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                onOpenAlertChat(alert)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("See all that's been happening with \(alert.firstName)")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.miyaAlertCoral)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.miyaAlertCoral.opacity(0.10))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("See all that's been happening with \(alert.firstName)")
            .accessibilityHint("Opens the notification chat with suggested prompts.")
        }
    }

    private var supportActionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(supportPresentation.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.miyaDashboardTextPrimary)
                Text(supportPresentation.explanation)
                    .font(.system(size: 13))
                    .foregroundColor(.miyaDashboardTextSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = supportPresentation.statusLine {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.miyaHeroAccentTeal)
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.miyaDashboardTextSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if let action = supportPresentation.primaryAction,
                   let label = supportPresentation.primaryLabel {
                    supportButton(label: label, action: action, isPrimary: true)
                }
                if let action = supportPresentation.secondaryAction,
                   let label = supportPresentation.secondaryLabel {
                    supportButton(label: label, action: action, isPrimary: false)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.miyaCardWhite.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.miyaAlertBorder.opacity(0.85), lineWidth: 1)
        )
    }

    private func supportButton(label: String, action: AlertSupportAction, isPrimary: Bool) -> some View {
        Button {
            switch action {
            case .sendMessage:
                onSendMessage(representativeItem, supportPresentation)
            case .startChallenge:
                onStartSupportChallenge(representativeItem, supportPresentation)
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPrimary ? .white : .miyaHeroAccentTeal)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isPrimary ? Color.miyaHeroAccentTeal : Color.miyaHeroAccentTeal.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    /// Mirrors today's `careContextBanner` selection logic, condensed into
    /// a single line of copy.
    private var careContextLine: String? {
        if let outcome = representativeItem.outcomeMessage, !outcome.isEmpty {
            return outcome
        }
        if representativeItem.careState == .monitoring,
           let due = representativeItem.followUpDueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Follow-up due \(formatter.string(from: due))"
        }
        return nil
    }

    // MARK: Snooze helpers (mirror existing FamilyNotificationsCard logic)

    private var snoozeDefaultDays: Int {
        guard let current = representativeItem.triggerWindowDays else { return 3 }
        let next: Int? = {
            switch current {
            case 3: return 7
            case 7: return 14
            case 14: return 21
            default: return nil
            }
        }()
        if let next = next, next > current {
            return next - current
        }
        return 7
    }
}
