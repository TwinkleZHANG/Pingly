import AppKit
import SwiftUI

enum PinglyTheme {
    static let window = adaptive(
        light: NSColor(calibratedRed: 1.00, green: 0.992, blue: 0.973, alpha: 1),
        dark: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.165, alpha: 1)
    )
    static var sidebar: Color {
        switch accentTheme {
        case .sage:
            adaptive(
                light: NSColor(calibratedRed: 0.91, green: 0.945, blue: 0.906, alpha: 1),
                dark: NSColor(calibratedRed: 0.14, green: 0.19, blue: 0.16, alpha: 1)
            )
        case .apricot:
            adaptive(
                light: NSColor(calibratedRed: 0.985, green: 0.925, blue: 0.855, alpha: 1),
                dark: NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.14, alpha: 1)
            )
        case .blue:
            adaptive(
                light: NSColor(calibratedRed: 0.89, green: 0.935, blue: 0.96, alpha: 1),
                dark: NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.22, alpha: 1)
            )
        }
    }
    static let surface = adaptive(
        light: NSColor(calibratedRed: 0.973, green: 0.961, blue: 0.929, alpha: 1),
        dark: NSColor(calibratedRed: 0.20, green: 0.225, blue: 0.21, alpha: 1)
    )
    static let primaryText = adaptive(
        light: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.17, alpha: 1),
        dark: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.93, alpha: 1)
    )
    static let secondaryText = adaptive(
        light: NSColor(calibratedRed: 0.39, green: 0.44, blue: 0.41, alpha: 1),
        dark: NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.73, alpha: 1)
    )
    static var green: Color {
        switch accentTheme {
        case .sage:
            adaptive(
                light: NSColor(calibratedRed: 0.32, green: 0.46, blue: 0.38, alpha: 1),
                dark: NSColor(calibratedRed: 0.61, green: 0.77, blue: 0.66, alpha: 1)
            )
        case .apricot:
            adaptive(
                light: NSColor(calibratedRed: 0.72, green: 0.43, blue: 0.24, alpha: 1),
                dark: NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.45, alpha: 1)
            )
        case .blue:
            adaptive(
                light: NSColor(calibratedRed: 0.28, green: 0.45, blue: 0.57, alpha: 1),
                dark: NSColor(calibratedRed: 0.56, green: 0.74, blue: 0.86, alpha: 1)
            )
        }
    }
    static var greenSoft: Color {
        switch accentTheme {
        case .sage:
            adaptive(
                light: NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.925, alpha: 1),
                dark: NSColor(calibratedRed: 0.19, green: 0.26, blue: 0.22, alpha: 1)
            )
        case .apricot:
            adaptive(
                light: NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.88, alpha: 1),
                dark: NSColor(calibratedRed: 0.29, green: 0.21, blue: 0.16, alpha: 1)
            )
        case .blue:
            adaptive(
                light: NSColor(calibratedRed: 0.91, green: 0.95, blue: 0.975, alpha: 1),
                dark: NSColor(calibratedRed: 0.17, green: 0.24, blue: 0.29, alpha: 1)
            )
        }
    }
    static let apricot = adaptive(
        light: NSColor(calibratedRed: 0.94, green: 0.70, blue: 0.49, alpha: 1),
        dark: NSColor(calibratedRed: 0.81, green: 0.58, blue: 0.40, alpha: 1)
    )
    static let apricotSoft = adaptive(
        light: NSColor(calibratedRed: 1.00, green: 0.94, blue: 0.875, alpha: 1),
        dark: NSColor(calibratedRed: 0.29, green: 0.22, blue: 0.18, alpha: 1)
    )
    static let border = adaptive(
        light: NSColor(calibratedRed: 0.87, green: 0.87, blue: 0.83, alpha: 1),
        dark: NSColor(calibratedRed: 0.27, green: 0.30, blue: 0.28, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        return Color(nsColor: color)
    }

    private static var accentTheme: PinglyAccentTheme {
        let rawValue = UserDefaults.standard.string(forKey: "accentTheme.v1")
        return rawValue.flatMap(PinglyAccentTheme.init(rawValue:)) ?? .sage
    }
}
