//
//  SubscriptionManager.swift
//  Miya Health
//
//  StoreKit 2: load product, check entitlements, purchase, restore.
//  Product ID and logic are scalable for multiple products later.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    // MARK: - Published state
    @Published private(set) var hasActiveSubscription: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var entitlementCheckComplete: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var purchaseError: String?
    @Published private(set) var restoreMessage: String? // "Restored" or "No purchases to restore"

    private(set) var subscriptionProduct: Product?
    private var transactionUpdates: Task<Void, Never>?

    private let productIds: Set<String> = [PaywallConfig.subscriptionProductId]

    /// Bumped on `reset()` so in-flight loads do not publish after logout.
    private var loadEpoch = 0
    /// Coalesces overlapping `loadProductsAndCheckEntitlements()` calls (init, paywall, foreground).
    private var inflightLoad: Task<Void, Never>?

    /// Legacy in-app promo bypass (removed for App Store 3.1.1). Strip any leftover keys once.
    private static let obsoletedPromoKeyPrefix = "MiyaHealthPromoRedeemed"

    init() {
        clearObsoletedPromoBypassDefaultsIfNeeded()
        transactionUpdates = Task { await listenForTransactionUpdates() }
        Task { await loadProductsAndCheckEntitlements() }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    /// Removes UserDefaults used by the old non–IAP promo bypass so upgrades don’t stay “unlocked” without StoreKit.
    private func clearObsoletedPromoBypassDefaultsIfNeeded() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(Self.obsoletedPromoKeyPrefix) {
            d.removeObject(forKey: key)
        }
    }

    // MARK: - Load products
    /// Loads subscription metadata from StoreKit and refreshes entitlements.
    /// Simulator: select **Products.storekit** in the scheme (Run → Options → StoreKit Configuration) so `Product.products` resolves locally.
    func loadProductsAndCheckEntitlements() async {
        if let existing = inflightLoad {
            await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadProductsAndCheckEntitlements()
        }
        inflightLoad = task
        await task.value
        inflightLoad = nil
    }

    private func performLoadProductsAndCheckEntitlements() async {
        let epoch = loadEpoch
        guard !Task.isCancelled else { return }

        isLoadingProducts = true
        loadError = nil
        purchaseError = nil
        defer {
            if epoch == loadEpoch {
                isLoadingProducts = false
            }
        }

        do {
            let products = try await Product.products(for: Array(productIds))
            guard epoch == loadEpoch, !Task.isCancelled else { return }

            subscriptionProduct = products.first
            if subscriptionProduct == nil {
                loadError = "Product not found. Check App Store Connect."
            }

            let hasEntitlement = await readCurrentEntitlementsVerified()
            guard epoch == loadEpoch, !Task.isCancelled else { return }
            hasActiveSubscription = hasEntitlement
            entitlementCheckComplete = true
        } catch {
            guard epoch == loadEpoch, !Task.isCancelled else { return }
            loadError = error.localizedDescription
            let hasEntitlement = await readCurrentEntitlementsVerified()
            guard epoch == loadEpoch, !Task.isCancelled else { return }
            hasActiveSubscription = hasEntitlement
            entitlementCheckComplete = true
        }
    }

    private func readCurrentEntitlementsVerified() async -> Bool {
        var hasEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if productIds.contains(transaction.productID) {
                hasEntitlement = true
                break
            }
        }
        return hasEntitlement
    }

    // MARK: - Entitlements
    func checkEntitlements() async {
        let hasEntitlement = await readCurrentEntitlementsVerified()
        hasActiveSubscription = hasEntitlement
        entitlementCheckComplete = true
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            if productIds.contains(transaction.productID) {
                await MainActor.run { hasActiveSubscription = true }
            }
            await transaction.finish()
        }
    }

    // MARK: - Purchase
    func purchase() async {
        guard let product = subscriptionProduct else {
            purchaseError = "Product not available."
            return
        }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    if productIds.contains(transaction.productID) {
                        hasActiveSubscription = true
                    }
                    await transaction.finish()
                case .unverified:
                    purchaseError = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore
    func restore() async {
        restoreMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await checkEntitlements()
            restoreMessage = hasActiveSubscription ? "Restored" : "No purchases to restore"
        } catch {
            restoreMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reset (on logout)
    func reset() {
        clearObsoletedPromoBypassDefaultsIfNeeded()
        loadEpoch &+= 1
        inflightLoad?.cancel()
        inflightLoad = nil
        hasActiveSubscription = false
        entitlementCheckComplete = false
        subscriptionProduct = nil
        loadError = nil
        purchaseError = nil
        restoreMessage = nil
        isLoadingProducts = false
    }

    func clearRestoreMessage() {
        restoreMessage = nil
    }

    func clearPurchaseError() {
        purchaseError = nil
    }

    /// Use on launch/resume to keep paywall decisions fresh.
    /// If an entitlement check already completed this session, refresh silently without
    /// resetting the UI gate (prevents "Checking subscription…" spinner on every scene-active bounce).
    func refreshForCurrentSession() async {
        let needsProductReload = subscriptionProduct == nil && loadError != nil
        if needsProductReload {
            await loadProductsAndCheckEntitlements()
            return
        }
        if !entitlementCheckComplete {
            await loadProductsAndCheckEntitlements()
        } else {
            await checkEntitlements()
        }
    }
}
