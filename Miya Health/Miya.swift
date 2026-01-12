//
//  Miya.swift
//  Miya Health
//
//  App-wide color definitions for the Miya design system.
//

import SwiftUI

// MARK: - Color Extensions
extension Color {
    /// Initialize a Color from a hex string like "7C9885".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1.0
        )
    }
}

// MARK: - Hearth & Garden Palette
extension Color {
    // Sage (Primary)
    static let miyaSage = Color(hex: "7C9885")
    static let miyaSageLight = Color(hex: "A8C5B3")
    static let miyaSageDark = Color(hex: "5A7362")
    
    // Terracotta (Warmth/Alerts)
    static let miyaTerracotta = Color(hex: "C97064")
    static let miyaTerracottaLight = Color(hex: "E8AFA7")
    static let miyaTerracottaDark = Color(hex: "A55549")
    
    // Cream (Neutral/Base)
    static let miyaCreamBg = Color(hex: "FAF8F5")
    static let miyaCardWhite = Color.white
    static let miyaSurfaceGrey = Color(hex: "F4F1ED")
    
    // Charcoal (Text)
    static let miyaTextPrimary = Color(hex: "2C3333")
    static let miyaTextSecondary = Color(hex: "6B7280")
    static let miyaTextTertiary = Color(hex: "9CA3AF")
    
    // Supporting
    static let miyaAmber = Color(hex: "E8A449")
    static let miyaLavender = Color(hex: "9B89B3")
    static let miyaSkyBlue = Color(hex: "7BA4C0")
    
    // Legacy aliases for backward compatibility
    static let miyaPrimary = miyaSage
    static let miyaBackground = miyaCreamBg
    static let miyaEmerald = miyaSage          // legacy teal → sage
    static let miyaSecondary = miyaAmber       // legacy gold secondary → amber
}
