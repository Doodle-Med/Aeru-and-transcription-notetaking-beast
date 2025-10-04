import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum StorageManager {
    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WhisperControlMobile", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let recordingsDirectory: URL = {
        let dir = appSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let exportsDirectory: URL = {
        let dir = appSupportDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let logsDirectory: URL = {
        let dir = appSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var diagnosticsLogURL: URL {
        logsDirectory.appendingPathComponent("diagnostics.log")
    }

    static func appendToDiagnosticsLog(_ message: String, category: String = "GENERAL", includeStackTrace: Bool = false) {
        ensureDiagnosticsLogExists()
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let threadInfo = Thread.isMainThread ? "[MAIN]" : "[BG-\(Thread.current.name ?? "Unknown")]"
        let memoryInfo = getMemoryInfo()
        
        var logEntry = "[\(timestamp)] \(threadInfo) [\(category)] \(message)"
        
        if includeStackTrace {
            logEntry += "\n[STACK] \(Thread.callStackSymbols.prefix(5).joined(separator: "\n[STACK] "))"
        }
        
        logEntry += "\n[MEMORY] \(memoryInfo)\n"
        
        if let handle = try? FileHandle(forWritingTo: diagnosticsLogURL) {
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        }
    }
    
    static func logUserAction(_ action: String, details: String = "") {
        appendToDiagnosticsLog("USER ACTION: \(action) - \(details)", category: "USER")
    }
    
    static func logSystemEvent(_ event: String, details: String = "") {
        appendToDiagnosticsLog("SYSTEM EVENT: \(event) - \(details)", category: "SYSTEM")
    }
    
    static func logError(_ error: Error, context: String = "") {
        appendToDiagnosticsLog("ERROR: \(error.localizedDescription) - Context: \(context)", category: "ERROR", includeStackTrace: true)
    }
    
    static func logPerformance(_ operation: String, duration: TimeInterval, details: String = "") {
        appendToDiagnosticsLog("PERFORMANCE: \(operation) took \(String(format: "%.3f", duration))s - \(details)", category: "PERF")
    }
    
    private static func getMemoryInfo() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = info.resident_size / 1024 / 1024
            return "Used: \(usedMB)MB"
        }
        return "Unknown"
    }

    static func readDiagnosticsLog() -> String {
        ensureDiagnosticsLogExists()
        guard let data = try? Data(contentsOf: diagnosticsLogURL), let content = String(data: data, encoding: .utf8) else {
            return ""
        }
        return content
    }

    static func clearDiagnosticsLog() {
        ensureDiagnosticsLogExists()
        try? "".data(using: .utf8)?.write(to: diagnosticsLogURL)
    }

    static func copyDiagnosticsToClipboard() {
        #if canImport(UIKit) && !os(watchOS)
        let content = readDiagnosticsLog()
        UIPasteboard.general.string = content
        #endif
    }

    private static func ensureDiagnosticsLogExists() {
        if !FileManager.default.fileExists(atPath: diagnosticsLogURL.path) {
            FileManager.default.createFile(atPath: diagnosticsLogURL.path, contents: nil)
        }
    }

    @discardableResult
    static func createDirectoriesIfNeeded() -> Bool {
        let dirs = [appSupportDirectory, recordingsDirectory, exportsDirectory, logsDirectory]
        for dir in dirs {
            if !FileManager.default.fileExists(atPath: dir.path) {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    print("[StorageManager] Failed to create directory \(dir): \(error)")
                    return false
                }
            }
        }
        return true
    }

    static func makeRecordingURL(filename: String) -> URL {
        let sanitized = filename.replacingOccurrences(of: " ", with: "_")
        return recordingsDirectory.appendingPathComponent("\(sanitized)-\(UUID().uuidString).wav")
    }

    static func cleanupRecordings(olderThan interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        guard let enumerator = FileManager.default.enumerator(at: recordingsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let attributes = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = attributes?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

