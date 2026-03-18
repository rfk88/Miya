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
        static let ctaButton = "Start your 14-day free trial"
        static let priceAfterTrial = "£12.99/month after trial · Cancel anytime"
        static let finePrint = ""
        static let restoreLabel = "Restore purchases"
        static let timelineTodayTitle = "Today: Instant access"
        static let timelineTodayDetail = "With free 14-day trial"
        static let timelineMiddleTitle = "Your family all integrated"
        static let timelineMiddleDetail = "We notify you about your trial end via email"
        static let timelineDay14Title = "Day 14: Full membership"
        static let timelineDay14Detail = "Your account is charged £12.99/month. Cancel anytime in the 24h before."
        static let haveACodeLabel = "Have a code?"
    }

    // MARK: - Legal URLs (replace with your actual URLs before release)
    static let termsOfUseURLString = "https://miyahealth.com/terms"
    static let privacyPolicyURLString = "https://fumble.info/"

    /// Valid promo code that bypasses the paywall (case-insensitive).
    static let promoCodeBypass = "MiyaHealthFree"

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
}
