import Foundation
import Combine

@MainActor
final class BroadcastTranscriptStore: ObservableObject {
    static let shared = BroadcastTranscriptStore()

    @Published var lines: [String] = []
    @Published var isActive: Bool = false
    @Published var sessionStartTime: Date?
    @Published var currentTranscript: String = ""

    private var timer: AnyCancellable?
    private var sessionStateTimer: AnyCancellable?

    func startPolling(every seconds: TimeInterval = 0.5) {
        stop()
        AppGroupConstants.ensureBroadcastFolder()
        isActive = true
        timer = Timer.publish(every: seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.readTranscript()
            }
        
        // Also monitor session state
        sessionStateTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.readSessionState()
            }
    }

    func stop() {
        timer?.cancel()
        sessionStateTimer?.cancel()
        timer = nil
        sessionStateTimer = nil
        isActive = false
    }

    private func readTranscript() {
        guard let url = AppGroupConstants.liveTranscriptURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        let all = text.split(separator: "\n").map { String($0) }
        if all != lines { 
            lines = all
            currentTranscript = all.joined(separator: " ")
        }
    }
    
    private func readSessionState() {
        guard let url = AppGroupConstants.sessionStateURL,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        if let isActive = json["isActive"] as? Bool {
            self.isActive = isActive
        }
        
        if let sessionStartTime = json["sessionStartTime"] as? TimeInterval, sessionStartTime > 0 {
            self.sessionStartTime = Date(timeIntervalSince1970: sessionStartTime)
        }
    }
}


