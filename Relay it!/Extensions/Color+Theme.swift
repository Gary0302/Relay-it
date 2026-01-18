//
//  Color+Theme.swift
//  Relay it!
//
//  Cohesive theme colors for the app
//

import SwiftUI

extension Color {
    // MARK: - Primary Theme Colors (Sage/Olive palette)

    /// Main background - soft sage green
    static let themeBackground = Color(hex: "e4eadd")

    /// Slightly darker for panels/cards
    static let themeSurface = Color(hex: "d4dcc9")

    /// Even darker for hover states
    static let themeSurfaceHover = Color(hex: "c4ccb9")

    /// Accent color - deeper olive green
    static let themeAccent = Color(hex: "6b7c5e")

    /// Secondary accent - muted sage
    static let themeSecondary = Color(hex: "8a9a7c")

    // MARK: - Text Colors

    /// Primary text - dark charcoal
    static let themeText = Color(hex: "2c3527")

    /// Secondary text - muted
    static let themeTextSecondary = Color(hex: "5a6654")

    /// Tertiary text - very muted
    static let themeTextTertiary = Color(hex: "7a8a74")

    // MARK: - UI Element Colors

    /// Input field background
    static let themeInput = Color(hex: "f5f7f2")

    /// Border color
    static let themeBorder = Color(hex: "b8c4ac")

    /// Divider color
    static let themeDivider = Color(hex: "c8d4bc")

    /// Card background
    static let themeCard = Color(hex: "eef2e9")

    /// Selected state
    static let themeSelected = Color(hex: "6b7c5e").opacity(0.15)

    // MARK: - Semantic Colors

    /// Success green
    static let themeSuccess = Color(hex: "4a7c59")

    /// Warning amber
    static let themeWarning = Color(hex: "c9a227")

    /// Error/destructive
    static let themeError = Color(hex: "b54a4a")

    /// Info blue-green
    static let themeInfo = Color(hex: "4a7c7c")

    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
