//
//  SignInWithAppleHelper.swift
//  Miya Health
//
//  Shared Sign in with Apple button and nonce handling for Supabase native auth.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

/// Generates a random nonce string for Sign in with Apple.
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        let rand: UInt8 = .random(in: 0 ... 255)
        result.append(charset[Int(rand) % charset.count])
        remaining -= 1
    }
    return result
}

/// Returns SHA256 hash of the nonce as a hex string (Apple expects this format for the request).
private func sha256Nonce(_ nonce: String) -> String {
    let data = Data(nonce.utf8)
    let hash = SHA256.hash(data: data)
    return hash.map { String(format: "%02x", $0) }.joined()
}

/// A Sign in with Apple button that generates nonce, requests .fullName and .email, and passes credential to the handler.
/// The handler receives idToken (string), raw nonce (for Supabase), and fullName (only on first authorization).
struct SignInWithAppleButtonView: View {
    var onCredential: (String, String?, PersonNameComponents?) async -> Void

    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let raw = randomNonceString()
            currentNonce = raw
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256Nonce(raw)
        } onCompletion: { result in
            let nonce = currentNonce
            currentNonce = nil
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    return
                }
                Task {
                    await onCredential(idToken, nonce, credential.fullName)
                }
            case .failure:
                break
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: MiyaTheme.buttonH)
        .background(
            RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous)
                .fill(Color(white: 0.96))
        )
        .clipShape(RoundedRectangle(cornerRadius: MiyaTheme.radius, style: .continuous))
    }
}
