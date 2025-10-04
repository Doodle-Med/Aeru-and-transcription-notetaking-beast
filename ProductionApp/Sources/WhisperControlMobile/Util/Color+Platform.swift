import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static var platformGroupedBackground: Color {
#if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
#elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
#else
        return Color.gray.opacity(0.05)
#endif
    }

    static var platformSecondaryBackground: Color {
#if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
#elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
#else
        return Color.gray.opacity(0.08)
#endif
    }

    static var platformTertiaryBackground: Color {
#if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
#elseif canImport(AppKit)
        return Color(NSColor.underPageBackgroundColor)
#else
        return Color.gray.opacity(0.12)
#endif
    }

    static var platformQuaternaryFill: Color {
#if canImport(UIKit)
        return Color(UIColor.quaternaryLabel)
#elseif canImport(AppKit)
        return Color(NSColor.disabledControlTextColor)
#else
        return Color.gray.opacity(0.18)
#endif
    }
    
    // Custom colors for better dark mode support
    static var whisperCardBackground: Color {
#if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
#elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
#else
        return Color.gray.opacity(0.08)
#endif
    }
    
    static var whisperCardBorder: Color {
#if canImport(UIKit)
        return Color(UIColor.separator)
#elseif canImport(AppKit)
        return Color(NSColor.separatorColor)
#else
        return Color.gray.opacity(0.2)
#endif
    }
    
    static var whisperAccent: Color {
        return Color.accentColor
    }
    
    static var whisperSuccess: Color {
        return Color.green
    }
    
    static var whisperWarning: Color {
        return Color.orange
    }
    
    static var whisperError: Color {
        return Color.red
    }
}

