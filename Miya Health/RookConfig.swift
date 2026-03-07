//
//  RookConfig.swift
//  Miya Health
//
//  ROOK SDK/API credentials. Production must use non-committed config (Secrets.xcconfig).
//  Set RookClientUUID and RookSecretKey via INFOPLIST_KEY_* in Secrets.xcconfig; missing values cause a clear runtime failure.
//

import Foundation

enum RookConfig {
    private static func require(key: String) -> String {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fatalError("RookConfig: \(key) is missing or empty. Copy Miya Health/Secrets.xcconfig.example to Miya Health/Secrets.xcconfig and set INFOPLIST_KEY_RookClientUUID and INFOPLIST_KEY_RookSecretKey. See tools/README.md.")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var clientUUID: String { require(key: "RookClientUUID") }
    static var secretKey: String { require(key: "RookSecretKey") }
}
