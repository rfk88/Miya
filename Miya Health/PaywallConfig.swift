//
//  PaywallConfig.swift
//  Miya Health
//
//  Single place for paywall product ID, copy, and testimonials.
//  Change these when you add products in App Store Connect or update copy.
//

import Foundation

enum PaywallConfig {
    // MARK: - Product ID (must match App Store Connect exactly)
    static let subscriptionProductId = "com.Miya_Health.monthly"

    // MARK: - Copy
    struct Copy {
        static let title = "Stay ahead of your family's health."
        static let subtitle = ""
        /// Second line on the subscribe control (under the StoreKit price line).
        static let ctaButton = "Start 14-day free trial"
        /// Subordinate renewal disclosure; references the price on the button without repeating the amount (3.1.2(c)).
        static let ctaRenewalFootnote = "Auto-renewing subscription. After the trial, you’ll be charged this amount unless you cancel."
        /// Under the CTA; must stay smaller than the main button label.
        static let cancelAnytimeReassurance = "Cancel anytime."
        static let finePrint = ""
        static let restoreLabel = "Restore purchases"
        /// Restore runs Apple’s sync and may ask you to sign in with your Apple ID.
        static let subscriptionUsesAppleIDFootnote = "Subscriptions use your Apple Media account (Settings → Media & Purchases), not your Miya email. Restore is only if access doesn’t appear after reinstall."
        /// Opens Apple’s subscription management UI (helps TestFlight / sandbox testing).
        static let manageSubscriptionLabel = "Manage subscription"
        /// App Store subscription offer codes only (system redemption sheet — not custom promo).
        static let redeemOfferCodeLabel = "Redeem offer code"
        static let timelineTodayTitle = "Today: Instant access"
        static let timelineTodayDetail = "With free 14-day trial"
        static let timelineMiddleTitle = "Your family all integrated"
        static let timelineMiddleDetail = "We notify you about your trial end via email"
        static let timelineDay14Title = "Day 14: Full membership"
        static let timelineDay14Detail = "Your account is charged the subscription price. Cancel anytime in the 24h before renewal."
    }

    // MARK: - Legal URLs (replace with your actual URLs before release)
    static let termsOfUseURLString = "https://miyahealth.com/terms"
    static let privacyPolicyURLString = "https://fumble.info/"

    // MARK: - Outcome bullets (title + detail)
    struct OutcomeBullet: Identifiable {
        let id = UUID()
        let iconName: String
        let title: String
        let detail: String
    }

    static let outcomeBullets: [OutcomeBullet] = [
        OutcomeBullet(iconName: "chart.bar.fill", title: "See your family's health at a glance", detail: "Track sleep, recovery, and habits in one place."),
        OutcomeBullet(iconName: "exclamationmark.triangle.fill", title: "Spot problems early", detail: "Miya highlights patterns before they become issues."),
        OutcomeBullet(iconName: "person.3.fill", title: "Stay connected as a family", detail: "Shared insights help everyone stay accountable."),
    ]

    // MARK: - Testimonials
    struct Testimonial: Identifiable {
        let id = UUID()
        let quote: String
        let author: String?
    }

    static let testimonials: [Testimonial] = [
        Testimonial(quote: "Miya helped us spot patterns in our sleep and activity we hadn't noticed before. It's like having a simple health dashboard for the whole family.", author: "— Emma, mum of two"),
        Testimonial(quote: "We finally have one place to see how everyone in the family is doing. It's made healthy habits something we talk about together.", author: "— James, dad of three"),
        Testimonial(quote: "With work and kids, it's hard to stay on top of everyone's health. Miya makes it easy to see everything in seconds.", author: "— Laura, mum of two"),
        Testimonial(quote: "We all had wearables but never really understood the data. Miya turns it into something that actually makes sense.", author: "— Daniel, father of two"),
        Testimonial(quote: "Small habits add up over time, but it's easy to miss the signals. Miya helps us stay ahead of it as a family.", author: "— Sarah, mum of three"),
    ]

    // MARK: - App Review (copy into App Store Connect → App Review Information → Notes)

    /// Guideline 3.1.2(c): paste into Notes for Review on resubmission.
    static let appStoreReviewNoteGuideline312c = """
    We updated the in-app subscription paywall per Guideline 3.1.2(c): the recurring subscription price from StoreKit is the first line on the primary control (e.g. localized price with “/ month”), in larger type than the free-trial action line below it; auto-renewal terms follow in smaller secondary text.
    If the review references the system subscription confirmation sheet, that UI is provided by StoreKit and cannot be customized; our custom paywall reflects the hierarchy above.
    """
}
