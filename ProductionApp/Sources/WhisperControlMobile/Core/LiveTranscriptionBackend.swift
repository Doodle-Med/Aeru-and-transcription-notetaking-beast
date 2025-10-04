import Foundation

enum LiveTranscriptionBackend: String, CaseIterable, Codable, Identifiable {
    case appleNative
    case whisperTiny
    case whisperBase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleNative:
            return "Apple Speech"
        case .whisperTiny:
            return "Whisper Tiny (HF)"
        case .whisperBase:
            return "Whisper Base (HF)"
        }
    }

    var detail: String {
        switch self {
        case .appleNative:
            return "Low-latency on-device engine powered by SFSpeechRecognizer."
        case .whisperTiny:
            return "39MB on-device Whisper Tiny model from Hugging Face. Fast with lower accuracy."
        case .whisperBase:
            return "142MB Whisper Base model from Hugging Face. Balanced accuracy and speed."
        }
    }

    var requiredModelID: String? {
        switch self {
        case .appleNative:
            return nil
        case .whisperTiny:
            return "openai-whisper-tiny-en-coreml"
        case .whisperBase:
            return "openai-whisper-base-en-coreml"
        }
    }
}

