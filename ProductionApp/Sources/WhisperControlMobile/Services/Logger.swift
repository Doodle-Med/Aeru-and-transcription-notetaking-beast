import Foundation
import OSLog

/// Centralized logging using iOS native OSLog
/// Replaces custom file-based diagnostics logging with system-integrated approach
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.whispercontrol.mobile"
    
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let job = Logger(subsystem: subsystem, category: "job")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let analytics = Logger(subsystem: subsystem, category: "analytics")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    
    /// Legacy compatibility: write to both OSLog and diagnostics file
    /// Remove file logging once migration complete
    static func log(_ message: String, category: Logger, level: OSLogType = .default) {
        switch level {
        case .debug:
            category.debug("\(message, privacy: .public)")
        case .info:
            category.info("\(message, privacy: .public)")
        case .error:
            category.error("\(message, privacy: .public)")
        case .fault:
            category.fault("\(message, privacy: .public)")
        default:
            category.log("\(message, privacy: .public)")
        }
        
        // Maintain backward compatibility with diagnostics view
        StorageManager.appendToDiagnosticsLog(message)
    }
}
