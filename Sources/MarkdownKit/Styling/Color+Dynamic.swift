import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// A color that adapts to light and dark appearance.
    public static func dynamic(light: Color, dark: Color) -> Color {
        // Convert eagerly: converting inside the provider may hop to the main thread.
        #if canImport(UIKit)
        let lightColor = UIColor(light), darkColor = UIColor(dark)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
        #else
        let lightColor = NSColor(light), darkColor = NSColor(dark)
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua]) == .aqua ? lightColor : darkColor
        })
        #endif
    }

    /// Creates an sRGB color from a `0xRRGGBB` value.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
