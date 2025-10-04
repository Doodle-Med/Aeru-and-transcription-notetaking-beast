import CoreHaptics
#if canImport(UIKit)
import UIKit
#endif

struct HapticGenerator {
    #if canImport(UIKit)
    typealias ImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle
    #else
    enum ImpactStyle {
        case medium
        case rigid
    }
    #endif

    static func success() {
        #if canImport(UIKit)
        #if targetEnvironment(simulator)
        return
        #endif
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        #if targetEnvironment(simulator)
        return
        #endif
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }

    static func error() {
        #if canImport(UIKit)
        #if targetEnvironment(simulator)
        return
        #endif
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }

    static func impact(style: ImpactStyle = .medium) {
        #if canImport(UIKit)
        #if targetEnvironment(simulator)
        return
        #endif
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
        #endif
    }
}
