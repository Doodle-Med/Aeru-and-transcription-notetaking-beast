import Foundation
import SwiftUI
#if canImport(ReplayKit)
import ReplayKit
#endif

struct ReplayKitPickerView: UIViewRepresentable {
    let preferredExtensionBundleId: String?

    func makeUIView(context: Context) -> UIView {
        #if canImport(ReplayKit)
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = preferredExtensionBundleId
        picker.showsMicrophoneButton = true
        return picker
        #else
        return UIView()
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        #if canImport(ReplayKit)
        if let picker = uiView as? RPSystemBroadcastPickerView {
            picker.preferredExtension = preferredExtensionBundleId
        }
        #endif
    }
}


