//
//  PaywallView.swift
//  Miya Health
//
//  Superadmin paywall: 14-day trial, £12.99/month. Miya design system only.
//  No Rook/Supabase dependency so Preview works.
//

import SwiftUI

struct PaywallView: View {
    var onStartTrial: () -> Void
    var onRestore: () -> Void
    @ObservedObject var subscriptionManager: SubscriptionManager

    @State private var testimonialIndex: Int = 0
    @State private var testimonialTimer: Timer?
    @State private var outcomeBulletsVisible: Bool = false
    @State private var showCodeEntry: Bool = false
    @State private var enteredPromoCode: String = ""
    @State private var promoCodeError: String?

    init(
        onStartTrial: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        subscriptionManager: SubscriptionManager? = nil
    ) {
        self.onStartTrial = onStartTrial
        self.onRestore = onRestore
        self._subscriptionManager = ObservedObject(wrappedValue: subscriptionManager ?? SubscriptionManager())
    }

    private var isBusy: Bool {
        subscriptionManager.isPurchasing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                outcomeBulletsSection
                testimonialsSection
                ctaButton
                priceReassurance
                restoreAndHaveACodeRow
                restoreMessage
                legalSection
            }
            .padding(.horizontal, MiyaTheme.hPad)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .background(paywallBackground.ignoresSafeArea())
        .onAppear {
            startTestimonialTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                outcomeBulletsVisible = true
            }
        }
        .onDisappear { testimonialTimer?.invalidate() }
        .sheet(isPresented: $showCodeEntry) {
            promoCodeSheet
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PaywallConfig.Copy.title)
                .font(.system(size: 26, weight: .bold))
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
    private var ctaButton: some View {
        Group {
            Button(action: onStartTrial) {
                Text(PaywallConfig.Copy.ctaButton)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: MiyaTheme.buttonH)
                    .background(Color.miyaPrimary)
                    .cornerRadius(MiyaTheme.radius)
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.7 : 1)
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
            .padding(.top, MiyaTheme.ctaGap)

            if let err = subscriptionManager.purchaseError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(Color.miyaTerracotta)
            }
        }
    }

    private var priceReassurance: some View {
        Text(PaywallConfig.Copy.priceAfterTrial)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(Color.miyaTextPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var restoreAndHaveACodeRow: some View {
        HStack {
            Button(action: onRestore) {
                Text(PaywallConfig.Copy.restoreLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.miyaPrimary)
            }
            .disabled(isBusy)
            Spacer(minLength: 0)
            Button(action: {
                enteredPromoCode = ""
                promoCodeError = nil
                showCodeEntry = true
            }) {
                Text(PaywallConfig.Copy.haveACodeLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.miyaTextTertiary)
            }
        }
        .padding(.top, 8)
    }

    private var promoCodeSheet: some View {
        VStack(spacing: 20) {
            Text("Enter code")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.miyaTextPrimary)
            TextField("Code", text: $enteredPromoCode)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if let err = promoCodeError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(Color.miyaTerracotta)
            }
            HStack(spacing: 12) {
                Button("Cancel") {
                    showCodeEntry = false
                }
                .foregroundColor(Color.miyaTextSecondary)
                Button("Redeem") {
                    if subscriptionManager.redeemPromoCode(enteredPromoCode) {
                        showCodeEntry = false
                    } else {
                        promoCodeError = "Invalid code"
                    }
                }
                .foregroundColor(Color.miyaPrimary)
                .fontWeight(.medium)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.miyaBackground)
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

#Preview {
    PaywallView(onStartTrial: {}, onRestore: {})
}
