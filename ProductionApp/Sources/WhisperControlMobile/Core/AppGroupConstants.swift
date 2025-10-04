import Foundation

enum AppGroupConstants {
    // Update in Signing & Capabilities when you create the App Group
    static let identifier = "group.com.josephhennig.whispercontrolmobile"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var liveTranscriptURL: URL? {
        containerURL()?.appendingPathComponent("broadcast/live_transcript.jsonl", isDirectory: false)
    }

    static var liveSessionMetaURL: URL? {
        containerURL()?.appendingPathComponent("broadcast/session.json", isDirectory: false)
    }
    
    static var sessionStateURL: URL? {
        containerURL()?.appendingPathComponent("broadcast/session_state.json", isDirectory: false)
    }

    static func ensureBroadcastFolder() {
        guard let base = containerURL()?.appendingPathComponent("broadcast", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
}


