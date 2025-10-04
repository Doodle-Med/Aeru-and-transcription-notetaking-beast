import Foundation

// MARK: - Job Models
struct TranscriptionJob: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case queued, recording, transcribing, completed, failed, cancelled
    }

    let id: UUID
    let filename: String
    var originalURL: URL
    let createdAt: Date
    var status: Status
    var progress: Double
    var error: String?
    var result: TranscriptionResult?
    var downloadURL: URL?
    var sourceURL: URL?
    var stage: String?
    var duration: TimeInterval?

    init(filename: String, originalURL: URL) {
        self.id = UUID()
        self.filename = filename
        self.originalURL = originalURL
        self.createdAt = Date()
        self.status = .queued
        self.progress = 0.0
        self.duration = nil
        self.sourceURL = nil
        self.stage = nil
    }

    static func == (lhs: TranscriptionJob, rhs: TranscriptionJob) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transcription Results
struct TranscriptionResult: Codable, Equatable {
    let text: String
    let segments: [TranscriptionSegment]
    let language: String?
    let duration: TimeInterval

    init(text: String, segments: [TranscriptionSegment], language: String?, duration: TimeInterval) {
        self.text = text
        self.segments = segments
        self.language = language
        self.duration = duration
    }
}

struct TranscriptionSegment: Codable, Identifiable, Equatable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
    }
}

// MARK: - Model Information
struct WhisperModel: Identifiable, Codable {
    enum Format: String, Codable {
        case ggml
        case coreml
    }

    let id: String
    let name: String
    let displayName: String
    let size: String
    let downloadURL: String?
    let checksum: String?
    let format: Format
    let languageSupport: [String]
    let notes: String?
    let preferredTask: String
    let bundledResourceSubpath: String?
    var isDownloaded: Bool

    var requiresUnzip: Bool {
        downloadURL?.hasSuffix(".zip") == true || downloadURL?.hasSuffix(".mlpackage") == true
    }

    var isBundled: Bool {
        bundledResourceSubpath != nil
    }

    /// Models that have already been converted to Core ML are distributed as .mlpackage.zip archives.
    /// GGML models (the default Whisper.cpp weights) are distributed as raw `.bin` files and work with WhisperKit.

    static let models: [WhisperModel] = [
        WhisperModel(
            id: "openai-whisper-tiny-en-coreml",
            name: "openai_whisper-tiny.en",
            displayName: "Tiny (English, Core ML)",
            size: "73MB",
            downloadURL: nil,
            checksum: nil,
            format: .coreml,
            languageSupport: ["en"],
            notes: "Bundled Core ML model for offline transcription.",
            preferredTask: "transcribe",
            bundledResourceSubpath: "openai_whisper-tiny.en",
            isDownloaded: true
        ),
        WhisperModel(
            id: "openai-whisper-small-en-coreml",
            name: "openai_whisper-small.en",
            displayName: "Small (English, Core ML)",
            size: "217MB",
            downloadURL: nil,
            checksum: nil,
            format: .coreml,
            languageSupport: ["en"],
            notes: "Higher accuracy English model; good balance of quality and speed.",
            preferredTask: "transcribe",
            bundledResourceSubpath: "openai_whisper-small.en",
            isDownloaded: true
        ),
        WhisperModel(
            id: "openai-whisper-base-en-coreml",
            name: "openai_whisper-base.en",
            displayName: "Base (English, Core ML)",
            size: "146MB",
            downloadURL: nil,
            checksum: nil,
            format: .coreml,
            languageSupport: ["en"],
            notes: "Baseline English model with solid accuracy on-device.",
            preferredTask: "transcribe",
            bundledResourceSubpath: "openai_whisper-base.en",
            isDownloaded: true
        )
    ]
}

// MARK: - Export Formats
enum ExportFormat: String, CaseIterable, Codable {
    case text = "txt"
    case json = "json"
    case srt = "srt"
    case vtt = "vtt"

    var displayName: String {
        switch self {
        case .text: return "Plain Text"
        case .json: return "JSON"
        case .srt: return "SRT Subtitles"
        case .vtt: return "WebVTT"
        }
    }
    
    var mimeType: String {
        switch self {
        case .text: return "text/plain"
        case .json: return "application/json"
        case .srt: return "text/srt"
        case .vtt: return "text/vtt"
        }
    }
}

// MARK: - App Capabilities
struct AppCapabilities: Codable {
    let maxConcurrentJobs: Int
    let supportedLanguages: [String]
    let availableModels: [WhisperModel]
    let defaultFormats: [ExportFormat]
}
