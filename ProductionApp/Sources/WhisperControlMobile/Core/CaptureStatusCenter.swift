import Foundation
import Combine

@MainActor
final class CaptureStatusCenter: ObservableObject {
    static let shared = CaptureStatusCenter()
    @Published var isLiveStreaming: Bool = false
    @Published var isReplayKitActive: Bool = false

    // Global control events
    static let stopLiveNotification = Notification.Name("CaptureStatusCenter.stopLive")
    static let forceStopReplayKitNotification = Notification.Name("CaptureStatusCenter.forceStopReplayKit")
}


