//
//  RookAuthorizationView.swift
//  Miya Health
//
//  SwiftUI view that handles OAuth authorization flow for Rook API-based data sources
//  Uses ASWebAuthenticationSession for OAuth flow
//

import SwiftUI
import AuthenticationServices

/// View that presents ASWebAuthenticationSession for OAuth
struct RookWebAuthView: UIViewControllerRepresentable {
    let authorizationURL: URL
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        context.coordinator.viewController = viewController
        context.coordinator.onComplete = onComplete
        context.coordinator.onCancel = onCancel
        
        // Start the session when view appears
        DispatchQueue.main.async {
            context.coordinator.startSession(authorizationURL: authorizationURL)
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
        weak var viewController: UIViewController?
        var session: ASWebAuthenticationSession?
        var onComplete: (() -> Void)?
        var onCancel: (() -> Void)?
        
        func startSession(authorizationURL: URL) {
            // Use a generic callback scheme - Rook may not redirect to our app
            // We'll poll status after session completes
            let callbackScheme = "miyahealth"
            
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                if let error = error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        print("🟡 RookWebAuthView: User cancelled OAuth")
                        DispatchQueue.main.async {
                            self?.onCancel?()
                        }
                    } else {
                        print("❌ RookWebAuthView: OAuth error: \(error.localizedDescription)")
                        // Even on error, user might have completed OAuth on provider's site
                        // Poll status to check
                        DispatchQueue.main.async {
                            self?.onComplete?()
                        }
                    }
                    return
                }
                
                // OAuth callback received (if Rook redirects to our app)
                print("✅ RookWebAuthView: OAuth callback received: \(callbackURL?.absoluteString ?? "nil")")
                DispatchQueue.main.async {
                    self?.onComplete?()
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.session = session
            
            // Start the session
            if !session.start() {
                print("❌ RookWebAuthView: Failed to start authentication session")
                DispatchQueue.main.async {
                    self.onCancel?()
                }
            } else {
                print("🟢 RookWebAuthView: Started OAuth session for: \(authorizationURL.absoluteString.prefix(60))...")
            }
        }
        
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

/// Wrapper view that manages the authorization flow
struct RookAuthorizationFlowView: View {
    let dataSource: String
    let dataSourceName: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var authorizationURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isCheckingStatus = false
    @State private var userId: String?
    @State private var didHandleOAuthCompletion = false // Guard against double-triggers
    
    var body: some View {
        ZStack {
            Color.miyaBackground.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Preparing authorization...")
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                }
            } else if let error = errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Authorization Error")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.miyaTextPrimary)
                    
                    Text(error)
                        .font(.system(size: 15))
                        .foregroundColor(.miyaTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.miyaPrimary)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                }
            } else if let url = authorizationURL {
                // Present ASWebAuthenticationSession
                RookWebAuthView(
                    authorizationURL: url,
                    onComplete: {
                        print("🟢 OAUTH_COMPLETE: \(dataSourceName)")
                        // Immediately check authorization status after OAuth completes
                        Task {
                            await handleOAuthCompletion()
                        }
                    },
                    onCancel: {
                        print("🟡 OAUTH_CANCELLED: user cancelled")
                        // User cancelled - don't auto-dismiss, just close
                        Task { @MainActor in
                            dismiss()
                        }
                    }
                )
            }
        }
        .task {
            // Get user ID first
            userId = await authManager.getCurrentUserId()
            guard userId != nil else {
                await MainActor.run {
                    errorMessage = "Please sign in first to connect your wearable."
                    isLoading = false
                }
                return
            }
            await loadAuthorizationURL()
        }
    }
    
    private func loadAuthorizationURL() async {
        guard let userId = userId else {
            await MainActor.run {
                errorMessage = "User ID not available"
                isLoading = false
            }
            return
        }
        
        do {
            let authorizerInfo = try await RookAPIService.shared.getAuthorizerInfo(dataSource: dataSource, userId: userId)
            
            await MainActor.run {
                // Check if already authorized
                if authorizerInfo.authorized {
                    print("✅ RookAuthorizationFlowView: \(dataSourceName) already authorized (data_source: \(authorizerInfo.dataSource))")
                    // Already connected, dismiss and let parent check status
                    isLoading = false
                    dismiss()
                    return
                }
                
                // Check if authorization URL exists (required: authorized == false AND authorizationUrl != nil)
                guard let authURLString = authorizerInfo.authorizationUrl,
                      let authURL = URL(string: authURLString) else {
                    print("❌ RookAuthorizationFlowView: No authorization URL in response (authorized: \(authorizerInfo.authorized))")
                    errorMessage = "Unable to get authorization URL. Please try again."
                    isLoading = false
                    return
                }
                
                print("✅ RookAuthorizationFlowView: Got authorization URL, opening OAuth")
                print("   authorization_url: \(authURLString.prefix(60))...")
                authorizationURL = authURL
                isLoading = false
            }
        } catch {
            await MainActor.run {
                print("❌ RookAuthorizationFlowView: Error loading authorization: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    /// Handle OAuth completion: immediately check if authorized and auto-dismiss if true
    private func handleOAuthCompletion() async {
        // Guard against double-triggers
        guard !didHandleOAuthCompletion, let userId = userId else { return }
        
        await MainActor.run {
            didHandleOAuthCompletion = true
            isCheckingStatus = true
        }
        
        do {
            // Wait a brief moment for Rook to process the authorization (reduced from 2s to 1s)
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Check authorization status immediately
            let isAuthorized = try await RookAPIService.shared.checkConnectionStatus(dataSource: dataSource, userId: userId)
            
            print("🟢 AUTH_CHECK: authorized=\(isAuthorized) for \(dataSourceName)")
            
            await MainActor.run {
                isCheckingStatus = false
                
                if isAuthorized {
                    // AUTO_DISMISS: authorized=true, dismiss immediately
                    print("✅ AUTO_DISMISS: authorized=true for \(dataSourceName), dismissing auth view")
                    
                    // Post notification so parent can update connectedWearables state
                    NotificationCenter.default.post(
                        name: .apiWearableConnected,
                        object: nil,
                        userInfo: [
                            "wearableType": dataSource,
                            "wearableName": dataSourceName,
                            "userId": userId
                        ]
                    )
                    
                    // Dismiss the authorization view
                    dismiss()
                } else {
                    // Not authorized yet - keep view open, user can retry or dismiss manually
                    print("⚠️ RookAuthorizationFlowView: \(dataSourceName) not authorized yet (authorized=false)")
                    // Don't dismiss - let user manually close or retry
                }
            }
        } catch {
            await MainActor.run {
                isCheckingStatus = false
                print("❌ RookAuthorizationFlowView: Error checking authorization status: \(error.localizedDescription)")
                // On error, don't auto-dismiss - let user manually close
            }
        }
    }
    
}

