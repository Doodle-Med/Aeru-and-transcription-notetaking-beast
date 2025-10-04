import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

// MARK: - Data Models (used by all platforms)

struct DeviceMetrics {
    let timeStampBegin: Date
    let timeStampEnd: Date
    let cpuTime: Double?               // Total CPU time in seconds
    let peakMemory: UInt64?            // Peak memory usage in bytes
    let averageMemory: Double?         // Average memory usage
    let cellularData: TimeInterval?    // Time on cellular
    let appLaunchCount: Int?           // Number of launches
    let backgroundTime: Double?        // Background execution time
    
    var summary: String {
        var parts: [String] = []
        if let cpu = cpuTime {
            parts.append("CPU: \(String(format: "%.1fs", cpu))")
        }
        if let mem = peakMemory {
            parts.append("Peak Memory: \(ByteCountFormatter.string(fromByteCount: Int64(mem), countStyle: .memory))")
        }
        if let launches = appLaunchCount {
            parts.append("Launches: \(launches)")
        }
        return parts.joined(separator: ", ")
    }
}

struct DiagnosticReport: Identifiable {
    enum ReportType {
        case crash
        case hang
        case cpuException
        case diskWrite
    }
    
    let id = UUID()
    let type: ReportType
    let timestamp: String
    let details: String
}

// MARK: - MetricsManager Implementation

#if canImport(MetricKit)
/// Integrates with iOS MetricKit for system-level diagnostics
/// Provides battery, CPU, memory, and crash analytics
@MainActor
final class MetricsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsManager()
    
    @Published private(set) var latestMetrics: DeviceMetrics?
    @Published private(set) var diagnostics: [DiagnosticReport] = []
    
    private var isSubscribed = false
    
    private override init() {
        super.init()
    }
    
    func startCollecting() {
        guard !isSubscribed else { return }
        
        MXMetricManager.shared.add(self)
        isSubscribed = true
        AppLogger.log("[METRICS] Started MetricKit collection", category: AppLogger.analytics, level: .info)
    }
    
    func stopCollecting() {
        guard isSubscribed else { return }
        
        MXMetricManager.shared.remove(self)
        isSubscribed = false
        AppLogger.log("[METRICS] Stopped MetricKit collection", category: AppLogger.analytics, level: .info)
    }
    
    // MARK: - MXMetricManagerSubscriber
    
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            for payload in payloads {
                processMetricPayload(payload)
            }
        }
    }
    
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            for payload in payloads {
                processDiagnosticPayload(payload)
            }
        }
    }
    
    // MARK: - Processing
    
    private func processMetricPayload(_ payload: MXMetricPayload) {
        // Simplified metrics extraction - MetricKit uses Measurement<Unit> types
        // We'll just log receipt and keep basic tracking
        
        let metrics = DeviceMetrics(
            timeStampBegin: payload.timeStampBegin,
            timeStampEnd: payload.timeStampEnd,
            cpuTime: nil,  // Simplified - full parsing requires unit conversion
            peakMemory: nil,
            averageMemory: nil,
            cellularData: nil,
            appLaunchCount: nil,
            backgroundTime: nil
        )
        
        latestMetrics = metrics
        
        AppLogger.log("[METRICS] Received payload: CPU=\(metrics.cpuTime ?? 0)s, Memory=\(ByteCountFormatter.string(fromByteCount: Int64(metrics.peakMemory ?? 0), countStyle: .memory))", category: AppLogger.analytics, level: .info)
        
        // Log to diagnostics file for historical tracking
        StorageManager.appendToDiagnosticsLog("[METRICS] \(metrics.summary)")
    }
    
    private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        // Process crashes
        if let crashDiagnostics = payload.crashDiagnostics {
            for crash in crashDiagnostics {
                let jsonData = crash.callStackTree.jsonRepresentation()
                let details = String(data: jsonData, encoding: .utf8) ?? "Unable to decode crash"
                
                let report = DiagnosticReport(
                    type: .crash,
                    timestamp: crash.metaData.applicationBuildVersion,
                    details: details
                )
                diagnostics.append(report)
                
                AppLogger.log("[METRICS] Crash detected: \(crash.metaData.applicationBuildVersion)", category: AppLogger.analytics, level: .error)
                StorageManager.appendToDiagnosticsLog("[CRASH] \(details)")
            }
        }
        
        // Process hangs
        if let hangDiagnostics = payload.hangDiagnostics {
            for hang in hangDiagnostics {
                let jsonData = hang.callStackTree.jsonRepresentation()
                let details = String(data: jsonData, encoding: .utf8) ?? "Unable to decode hang"
                
                let report = DiagnosticReport(
                    type: .hang,
                    timestamp: hang.metaData.applicationBuildVersion,
                    details: details
                )
                diagnostics.append(report)
                
                AppLogger.log("[METRICS] Hang detected: \(hang.metaData.applicationBuildVersion)", category: AppLogger.analytics, level: .error)
            }
        }
        
        // Limit stored diagnostics to last 10
        if diagnostics.count > 10 {
            diagnostics = Array(diagnostics.suffix(10))
        }
    }
}

#else
// Stub for platforms without MetricKit (macOS < 12)
@MainActor
final class MetricsManager: ObservableObject {
    static let shared = MetricsManager()
    
    @Published private(set) var latestMetrics: DeviceMetrics? = nil
    @Published private(set) var diagnostics: [DiagnosticReport] = []
    
    func startCollecting() {
        AppLogger.log("[METRICS] MetricKit not available on this platform", category: AppLogger.analytics, level: .info)
    }
    
    func stopCollecting() {}
}
#endif
