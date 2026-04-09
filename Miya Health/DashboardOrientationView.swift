 //
//  DashboardOrientationView.swift
//  Miya Health
//
//  First-time post-onboarding walkthrough (7 cards). Shown once per user from DashboardView.
//

import SwiftUI

// MARK: - Persistence

enum DashboardOrientationStorage {
    static let keyPrefix = "miya.hasCompletedDashboardOrientation"

    private static func completionKey(userId: String) -> String {
        // Normalize to lowercase so UUID variants (uppercase from uuidString vs any lowercase
        // paths) always resolve to the same UserDefaults key.
        let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(keyPrefix).\(uid)"
    }

    static func hasCompleted(userId: String?) -> Bool {
        guard let uid = normalized(userId) else { return false }
        return UserDefaults.standard.bool(forKey: completionKey(userId: uid))
    }

    static func markCompleted(userId: String?) {
        guard let uid = normalized(userId) else {
#if DEBUG
            print("⚠️ DashboardOrientationStorage: markCompleted called with nil/empty userId — completion not saved")
#endif
            return
        }
        let key = completionKey(userId: uid)
        UserDefaults.standard.set(true, forKey: key)
#if DEBUG
        print("✅ DashboardOrientationStorage: Marked completed uid=\(uid) key=\(key)")
#endif
    }

    /// Clear for the current user id key (e.g. on logout if you want the next account to see the tour).
    static func clearForUser(userId: String?) {
        guard let uid = normalized(userId) else { return }
        UserDefaults.standard.removeObject(forKey: completionKey(userId: uid))
    }

    /// Migrates legacy unscoped completion flag to the current user once, then removes the legacy key.
    static func migrateLegacyCompletionIfNeeded(userId: String?) {
        guard let uid = normalized(userId) else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyPrefix) != nil else { return }
        let userScopedKey = completionKey(userId: uid)
        if defaults.bool(forKey: keyPrefix), defaults.object(forKey: userScopedKey) == nil {
            defaults.set(true, forKey: userScopedKey)
        }
        defaults.removeObject(forKey: keyPrefix)
    }

    /// If completion was saved under `alternateId` but not `primaryId`, copies it to `primaryId`.
    /// This guards against check/save mismatches when two ID sources (DataManager vs
    /// OnboardingManager) temporarily return different values for the same authenticated user.
    static func crossCheckAndMigrateIfNeeded(primaryId: String?, alternateId: String?) {
        guard let primary = normalized(primaryId) else { return }
        guard let alternate = normalized(alternateId),
              alternate.lowercased() != primary.lowercased() else { return }
        let primaryKey = completionKey(userId: primary)
        let alternateKey = completionKey(userId: alternate)
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: primaryKey),
              defaults.bool(forKey: alternateKey) else { return }
        defaults.set(true, forKey: primaryKey)
#if DEBUG
        print("🔄 DashboardOrientationStorage: Migrated completion from alternate uid=\(alternate) -> primary uid=\(primary)")
#endif
    }

    private static func normalized(_ userId: String?) -> String? {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !uid.isEmpty else { return nil }
        return uid
    }
}

// MARK: - Page model

private struct DashboardOrientationPage: Identifiable {
    let id: Int
    let title: String
    let bodyText: String
    /// Extra line for card 4 (inbox vs family notifications).
    let footnote: String?
    let previewKind: DashboardOrientationPreviewKind
}

// MARK: - View

struct DashboardOrientationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Used to scope UserDefaults; pass `onboardingManager.currentUserId` or equivalent.
    let userId: String?
    let onFinished: () -> Void

    @State private var currentPage: Int = 0
    @State private var previewScale: CGFloat = 1.0

    private let pages: [DashboardOrientationPage] = [
        DashboardOrientationPage(
            id: 0,
            title: "Your family health hub",
            bodyText: "Miya shows if your family is doing okay and flags what needs attention, so you know when to check in.",
            footnote: nil,
            previewKind: .familyHub
        ),
        DashboardOrientationPage(
            id: 1,
            title: "Everyone completes their own setup",
            bodyText: "Each person needs to finish setup so their data is accurate. If they do not, you will see gaps or missing signals.",
            footnote: nil,
            previewKind: .everyoneSetup
        ),
        DashboardOrientationPage(
            id: 2,
            title: "Your family at a glance",
            bodyText: "Use this as your quick check. See how everyone is doing in seconds, then tap a person to go deeper.",
            footnote: nil,
            previewKind: .familyMVP
        ),
        DashboardOrientationPage(
            id: 3,
            title: "Family notifications: when to look",
            bodyText: "This is where Miya flags when something changes, so you know when to check in with someone. Early on it may be quiet, and that is normal.",
            footnote: "The bell in the top corner is your personal inbox—not the same list as Family notifications.",
            previewKind: .familyNotifications
        ),
        DashboardOrientationPage(
            id: 4,
            title: "Challenge each other (optional)",
            bodyText: "Use challenges to keep each other consistent. It is simple, light accountability that helps healthy habits stick.",
            footnote: nil,
            previewKind: .challenges
        ),
        DashboardOrientationPage(
            id: 5,
            title: "Care, not surveillance",
            bodyText: "If something looks off, send a quick message or check in. Small actions make the biggest difference.",
            footnote: nil,
            previewKind: .careSupport
        ),
        DashboardOrientationPage(
            id: 6,
            title: "",
            bodyText: "",
            footnote: nil,
            previewKind: .ready
        )
    ]

    private var isLastPage: Bool { currentPage >= pages.count - 1 }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(0.26).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        cardContent(page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.86), value: currentPage)

                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onChange(of: currentPage) { _, _ in
            pulseIcon()
        }
        .onAppear {
            pulseIcon()
        }
    }

    private var headerBar: some View {
        HStack {
            Spacer()
            Button("Skip") {
                completeAndDismiss()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.miyaTextSecondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func cardContent(_ page: DashboardOrientationPage) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            DashboardOrientationFeaturePreview(
                kind: page.previewKind,
                pulseScale: previewScale,
                onReadyEnterTapped: page.previewKind == .ready
                    ? { completeAndDismiss() }
                    : nil
            )
            .padding(.bottom, 2)

            if page.previewKind != .ready {
                Text(page.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.bodyText)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.93))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                if let footnote = page.footnote {
                    Text(footnote)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 24)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if !isLastPage {
                Button {
                    advance()
                } label: {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.miyaPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .accessibilityLabel("Next slide")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func advance() {
        guard currentPage < pages.count - 1 else { return }
        if reduceMotion {
            currentPage += 1
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                currentPage += 1
            }
        }
    }

    private func pulseIcon() {
        if reduceMotion {
            previewScale = 1.0
            return
        }
        previewScale = 0.96
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            previewScale = 1.0
        }
    }

    private func completeAndDismiss() {
        DashboardOrientationStorage.markCompleted(userId: userId)
        onFinished()
    }
}

#Preview {
    DashboardOrientationView(userId: "preview-user") {}
}
