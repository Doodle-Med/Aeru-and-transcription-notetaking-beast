import Foundation

@MainActor
final class AnalyticsTracker: ObservableObject {
    static let shared = AnalyticsTracker()

    @Published private(set) var metrics = AnalyticsMetrics()
    @Published private(set) var recentEvents: [AnalyticsLogEntry] = []

    private init() {}

    func prepare() {
        // Future hook for analytics or log uploads
    }

    func reset(to metrics: AnalyticsMetrics = AnalyticsMetrics()) {
        self.metrics = metrics
        recentEvents.removeAll()
    }

    func record(_ event: AnalyticsEvent) {
        metrics.apply(event)
        let entry = AnalyticsLogEntry(event: event, timestamp: Date())
        recentEvents.append(entry)
        if recentEvents.count > 50 {
            recentEvents.removeFirst(recentEvents.count - 50)
        }
        StorageManager.appendToDiagnosticsLog(entry.diagnosticsMessage)
    }
}

struct AnalyticsMetrics {
    private(set) var jobsCompleted: Int = 0
    private(set) var jobsFailed: Int = 0
    private(set) var modelDownloads: Int = 0
    private(set) var modelDownloadFailures: Int = 0
    private(set) var cloudFallbacks: Int = 0
    private(set) var toastsPresented: Int = 0
    private(set) var lastUpdated: Date = Date()

    mutating func apply(_ event: AnalyticsEvent) {
        switch event {
        case .jobCompleted:
            jobsCompleted += 1
        case .jobFailed:
            jobsFailed += 1
        case .modelDownloaded:
            modelDownloads += 1
        case .modelDownloadFailed:
            modelDownloadFailures += 1
        case .cloudFallback:
            cloudFallbacks += 1
        case .toastPresented:
            toastsPresented += 1
        }
        lastUpdated = Date()
    }
}

struct AnalyticsLogEntry: Identifiable {
    let id = UUID()
    let event: AnalyticsEvent
    let timestamp: Date

    var diagnosticsMessage: String {
        "[Analytics] \(timestampFormatter.string(from: timestamp)) - \(event.description)"
    }

    private var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
}

enum AnalyticsEvent {
    case jobCompleted(modelID: String, duration: TimeInterval?)
    case jobFailed(modelID: String?, reason: String)
    case modelDownloaded(modelID: String)
    case modelDownloadFailed(modelID: String, reason: String)
    case cloudFallback(provider: String)
    case toastPresented(style: ToastMessage.Style)

    var description: String {
        switch self {
        case let .jobCompleted(modelID, duration):
            if let duration {
                return "Job completed with model \(modelID) in \(String(format: "%.2fs", duration))."
            }
            return "Job completed with model \(modelID)."
        case let .jobFailed(modelID, reason):
            return "Job failed (model: \(modelID ?? "unknown")) – \(reason)."
        case let .modelDownloaded(modelID):
            return "Model downloaded: \(modelID)."
        case let .modelDownloadFailed(modelID, reason):
            return "Model download failed: \(modelID) – \(reason)."
        case let .cloudFallback(provider):
            return "Cloud fallback triggered for provider \(provider)."
        case let .toastPresented(style):
            return "Toast presented (\(style.label))."
        }
    }
}

private extension ToastMessage.Style {
    var label: String {
        switch self {
        case .success: return "success"
        case .warning: return "warning"
        case .error: return "error"
        case .info: return "info"
        }
    }
}
