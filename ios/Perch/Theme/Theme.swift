//
//  Theme.swift
//  Perch
//
//  Central design system: colors, typography helpers, and spacing.
//  "Oura Ring meets One Medical" — calm, premium, clinical-but-warm.
//

import SwiftUI

extension Color {
    /// Create a color from a 24-bit hex value (e.g. 0xF7F4EF).
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

private func dynamicColor(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    })
}

/// Brand palette for Perch. Adaptive colors shift gently between the warm
/// "paper" light mode and the Oura-like deep navy dark mode.
enum Palette {
    // Adaptive surfaces & text
    static let paper = dynamicColor(light: 0xF7F4EF, dark: 0x11202B)
    static let surface = dynamicColor(light: 0xFFFFFF, dark: 0x162A36)
    static let surfaceElevated = dynamicColor(light: 0xFCFAF6, dark: 0x1B3240)
    static let ink = dynamicColor(light: 0x1C2B33, dark: 0xF1ECE3)
    static let inkSoft = dynamicColor(light: 0x3A4A52, dark: 0xCBD4D6)
    static let mist = dynamicColor(light: 0x8A9499, dark: 0x6E7E86)
    static let hairline = dynamicColor(light: 0xE7E1D7, dark: 0x243A47)

    // Brand constants (consistent across modes)
    static let sage = Color(hex: 0x3E6B5E)
    static let sageSoft = Color(hex: 0x6E988A)
    static let amber = Color(hex: 0xE0A458)
    static let amberSoft = Color(hex: 0xEBC487)
    static let navy = Color(hex: 0x11202B)
    static let cream = Color(hex: 0xF7F4EF)
}

/// Standard spacing scale (8pt grid).
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Corner radii used across cards and controls.
enum Radius {
    static let card: CGFloat = 24
    static let control: CGFloat = 16
    static let pill: CGFloat = 100
}
