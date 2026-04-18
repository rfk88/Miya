//
//  PaywallView.swift
//  Miya Health
//
//  Superadmin paywall: trial CTA label; renewal price on button (StoreKit); footnote below.
//  Subscription access is StoreKit-only (App Store 3.1.1).
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    var onStartTrial: () -> Void
    var onRestore: () -> Void
    @ObservedObject var subscriptionManager: SubscriptionManager

    @State private var testimonialIndex: Int = 0
    @State private var testimonialTimer: Timer?
    @State private var outcomeBulletsVisible: Bool = false
    @State private var isOfferCodeRedemptionPresented = false
    @State private var isManageSubscriptionsPresented = false

    init(
        onStartTrial: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        subscriptionManager: SubscriptionManager
    ) {
        self.onStartTrial = onStartTrial
        self.onRestore = onRestore
        self._subscriptionManager = ObservedObject(wrappedValue: subscriptionManager)
    }

    private var isBusy: Bool {
        subscriptionManager.isPurchasing || subscriptionManager.isLoadingProducts
    }

    /// Purchase is only offered when StoreKit returned a product (avoids generic errors when product list is empty).
    private var canStartPurchase: Bool {
        subscriptionManager.subscriptionProduct != nil
            && !subscriptionManager.isPurchasing
            && !subscriptionManager.isLoadingProducts
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                productAvailabilitySection
                outcomeBulletsSection
                testimonialsSection
                ctaButton
                postCtaReassurance
                restoreRow
                restoreMessage
                legalSection
            }
            .padding(.horizontal, MiyaTheme.hPad)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .background(paywallBackground.ignoresSafeArea())
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        .offerCodeRedemption(isPresented: $isOfferCodeRedemptionPresented) { result in
            Task { @MainActor in
                if case .success = result {
                    await subscriptionManager.checkEntitlements()
                }
            }
        }
        .onAppear {
            startTestimonialTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                outcomeBulletsVisible = true
            }
        }
        .onDisappear { testimonialTimer?.invalidate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PaywallConfig.Copy.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.miyaTextPrimary)
            if !PaywallConfig.Copy.subtitle.isEmpty {
                Text(PaywallConfig.Copy.subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.miyaTextSecondary)
            }
        }
    }

    private static let outcomeBulletRowSpacing: CGFloat = 20
    private static let outcomeBulletConnectorHeight: CGFloat = 32 + outcomeBulletRowSpacing

    private var outcomeBulletsSection: some View {
        VStack(alignment: .leading, spacing: Self.outcomeBulletRowSpacing) {
            ForEach(Array(PaywallConfig.outcomeBullets.enumerated()), id: \.element.id) { index, bullet in
                outcomeBulletRow(
                    icon: bullet.iconName,
                    title: bullet.title,
                    detail: bullet.detail,
                    showLineBelow: index < PaywallConfig.outcomeBullets.count - 1
                )
                .opacity(outcomeBulletsVisible ? 1 : 0)
                .offset(y: outcomeBulletsVisible ? 0 : -28)
                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.12), value: outcomeBulletsVisible)
            }
        }
        .padding(.vertical, 12)
    }

    private func outcomeBulletRow(icon: String, title: String, detail: String, showLineBelow: Bool) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.miyaPrimary.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundColor(Color.miyaPrimary)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                if showLineBelow {
                    Rectangle()
                        .fill(Color.miyaTextTertiary.opacity(0.4))
                        .frame(width: 2, height: Self.outcomeBulletConnectorHeight)
                }
            }
            .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.miyaTextPrimary)
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.miyaTextSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var paywallBackground: some View {
        ZStack {
            Color.miyaBackground
            LinearGradient(
                colors: [
                    Color.miyaTeal.opacity(0.12),
                    Color.miyaTealLight.opacity(0.04),
                    Color.miyaBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Ellipse()
                .fill(Color.miyaTeal.opacity(0.07))
                .frame(width: 320, height: 280)
                .blur(radius: 60)
                .offset(x: 80, y: -80)
            Ellipse()
                .fill(Color.miyaTealLight.opacity(0.06))
                .frame(width: 260, height: 220)
                .blur(radius: 50)
                .offset(x: -60, y: 200)
            Ellipse()
                .fill(Color.miyaTeal.opacity(0.05))
                .frame(width: 200, height: 180)
                .blur(radius: 45)
                .offset(x: 100, y: 320)
        }
    }

    private var testimonialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let t = PaywallConfig.testimonials[testimonialIndex % PaywallConfig.testimonials.count]
            Text(t.quote)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color.miyaTextPrimary)
                .italic()
            if let author = t.author {
                Text(author)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.miyaTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.miyaSurfaceGrey.opacity(0.6))
        .cornerRadius(MiyaTheme.radius)
        .overlay(
            RoundedRectangle(cornerRadius: MiyaTheme.radius)
                .stroke(Color.miyaTextTertiary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
    }

    private func startTestimonialTimer() {
        testimonialTimer?.invalidate()
        testimonialTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            DispatchQueue.main.async {
                testimonialIndex = (testimonialIndex + 1) % PaywallConfig.testimonials.count
            }
        }
        testimonialTimer?.tolerance = 0.5
    }

    @ViewBuilder
    private var productAvailabilitySection: some View {
        if subscriptionManager.isLoadingProducts && subscriptionManager.subscriptionProduct == nil {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.miyaPrimary))
                Text("Loading subscription options…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.miyaTextSecondary)
            }
        } else if let loadErr = subscriptionManager.loadError, subscriptionManager.subscriptionProduct == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("We couldn’t load the subscription from the App Store.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.miyaTextPrimary)
                Text(loadErr)
                    .font(.system(size: 13))
                    .foregroundColor(Color.miyaTerracotta)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await subscriptionManager.loadProductsAndCheckEntitlements()
                    }
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.miyaPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Color.miyaPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.miyaSurfaceGrey.opacity(0.45))
            .cornerRadius(MiyaTheme.radius)
        } else if subscriptionManager.entitlementCheckComplete,
                  subscriptionManager.subscriptionProduct == nil,
                  subscriptionManager.loadError == nil {
            Text("Subscription is temporarily unavailable. Check your connection, confirm the app’s subscription is set up in App Store Connect, then tap below to retry.")
                .font(.system(size: 13))
                .foregroundColor(Color.miyaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    await subscriptionManager.loadProductsAndCheckEntitlements()
                }
            } label: {
                Text("Retry")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.miyaPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Color.miyaPrimary)
        }
    }

    @ViewBuilder
    private var ctaButton: some View {
        Group {
            if let product = subscriptionManager.subscriptionProduct {
                VStack(spacing: 10) {
                    Button(action: onStartTrial) {
                        Text(PaywallConfig.Copy.ctaButton)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: MiyaTheme.buttonH)
                            .background(canStartPurchase ? Color.miyaPrimary : Color.gray.opacity(0.35))
                            .cornerRadius(MiyaTheme.radius)
                    }
                    .disabled(!canStartPurchase)
                    .opacity(subscriptionManager.isPurchasing ? 0.7 : 1)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                    Text(
                        String(
                            format: String(
                                localized: "Free for 14 days, then %@. Cancel anytime.",
                                comment: "Paywall: trial, then StoreKit renewal price (e.g. $12.99 / month), then cancel note"
                            ),
                            product.paywallSlashPeriodLine
                        )
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color.miyaTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 14)
            } else {
                Button(action: onStartTrial) {
                    Text(PaywallConfig.Copy.ctaButton)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: MiyaTheme.buttonH)
                        .background(canStartPurchase ? Color.miyaPrimary : Color.gray.opacity(0.35))
                        .cornerRadius(MiyaTheme.radius)
                }
                .disabled(!canStartPurchase)
                .opacity(subscriptionManager.isPurchasing ? 0.7 : 1)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                .padding(.top, MiyaTheme.ctaGap)
            }

            if let err = subscriptionManager.purchaseError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(Color.miyaTerracotta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shown under the CTA; pricing caption already includes “Cancel anytime.” when the product is loaded.
    @ViewBuilder
    private var postCtaReassurance: some View {
        EmptyView()
    }

    private var restoreRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Button(action: onRestore) {
                    Text(PaywallConfig.Copy.restoreLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.miyaPrimary)
                }
                .disabled(subscriptionManager.isPurchasing)
                Spacer(minLength: 12)
                Button {
                    isOfferCodeRedemptionPresented = true
                } label: {
                    Text(PaywallConfig.Copy.redeemOfferCodeLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.miyaPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .disabled(subscriptionManager.isPurchasing)
            }
            Button {
                isManageSubscriptionsPresented = true
            } label: {
                Text(PaywallConfig.Copy.manageSubscriptionLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.miyaPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(subscriptionManager.isPurchasing)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var restoreMessage: some View {
        if let msg = subscriptionManager.restoreMessage {
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(Color.miyaTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var legalSection: some View {
        HStack(spacing: 4) {
            if let termsURL = URL(string: PaywallConfig.termsOfUseURLString) {
                Link("Terms of Use", destination: termsURL)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.miyaTextTertiary)
            }
            Text("·")
                .font(.system(size: 12))
                .foregroundColor(Color.miyaTextTertiary)
            if let privacyURL = URL(string: PaywallConfig.privacyPolicyURLString) {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.miyaTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - StoreKit billing line (App Store 3.1.2(c))

private extension Product {
    /// Standard recurring subscription price via `price` + `priceFormatStyle` (renewal amount), not introductory-offer pricing.
    /// Re-check in Sandbox after any pay-as-you-go or pay-up-front intro changes in App Store Connect.
    var paywallStandardRecurringDisplayPrice: String {
        price.formatted(priceFormatStyle)
    }

    /// Localized standard renewal price + billing period for the paywall hero line (App Store 3.1.2(c)).
    var paywallBilledAmountLine: String {
        let priceString = paywallStandardRecurringDisplayPrice
        let suffix = paywallSubscriptionPeriodSuffix
        if suffix.isEmpty { return priceString }
        return "\(priceString) \(suffix)"
    }

    /// e.g. "$12.99 / month" using StoreKit renewal price; falls back to `paywallBilledAmountLine` for unusual periods.
    var paywallSlashPeriodLine: String {
        let p = paywallStandardRecurringDisplayPrice
        guard let period = subscription?.subscriptionPeriod else { return p }
        let v = period.value
        let u = period.unit
        switch (u, v) {
        case (.month, 1):
            return p + String(localized: " / month", comment: "Subscription price with slash before billing period")
        case (.year, 1):
            return p + String(localized: " / year", comment: "Subscription price with slash before billing period")
        case (.week, 1):
            return p + String(localized: " / week", comment: "Subscription price with slash before billing period")
        case (.day, 1):
            return p + String(localized: " / day", comment: "Subscription price with slash before billing period")
        default:
            return paywallBilledAmountLine
        }
    }

    var paywallSubscriptionPeriodSuffix: String {
        guard let period = subscription?.subscriptionPeriod else { return "" }
        return Self.paywallLocalizedPeriodPhrase(value: period.value, unit: period.unit)
    }

    static func paywallLocalizedPeriodPhrase(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        switch (unit, value) {
        case (.day, 1):
            return String(localized: "per day", comment: "Subscription billing period suffix")
        case (.week, 1):
            return String(localized: "per week", comment: "Subscription billing period suffix")
        case (.month, 1):
            return String(localized: "per month", comment: "Subscription billing period suffix")
        case (.year, 1):
            return String(localized: "per year", comment: "Subscription billing period suffix")
        case (.day, let v) where v != 1:
            return String(format: String(localized: "Every %d days", comment: "Subscription billing period"), v)
        case (.week, let v) where v != 1:
            return String(format: String(localized: "Every %d weeks", comment: "Subscription billing period"), v)
        case (.month, let v) where v != 1:
            return String(format: String(localized: "Every %d months", comment: "Subscription billing period"), v)
        case (.year, let v) where v != 1:
            return String(format: String(localized: "Every %d years", comment: "Subscription billing period"), v)
        default:
            return ""
        }
    }
}

#Preview {
    PaywallView(onStartTrial: {}, onRestore: {}, subscriptionManager: SubscriptionManager())
}
