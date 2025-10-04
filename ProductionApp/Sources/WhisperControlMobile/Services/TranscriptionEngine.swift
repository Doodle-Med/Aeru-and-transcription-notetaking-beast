import Foundation
import CoreML
import AVFoundation
import WhisperKit
import OSLog

enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey(provider: String)
    case http(status: Int, body: String, provider: String)
    case emptyResponse(provider: String)
    case invalidAudioFormat
    case modelLoadingFailed(String)
    case inferenceFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): return "\(provider) API key is missing."
        case .http(let status, let body, let provider): return "\(provider) API Error (\(status)): \(body)"
        case .emptyResponse(let provider): return "\(provider) returned an empty response."
        case .invalidAudioFormat: return "Invalid audio format for transcription."
        case .modelLoadingFailed(let message): return "Failed to load transcription model: \(message)"
        case .inferenceFailed(let message): return "Transcription inference failed: \(message)"
        case .unknown(let message): return "An unknown transcription error occurred: \(message)"
        }
    }
}

// MARK: - Transcription Engine Protocol
protocol TranscriptionEngine: AnyObject {
    func transcribe(audioURL: URL, settings: TranscriptionSettings) async throws -> TranscriptionResult
    var progressHandler: ((Double) -> Void)? { get set }
}

// MARK: - Transcription Settings
struct TranscriptionSettings {
    let modelPath: URL
    let language: String?
    let translate: Bool
    let temperature: Float?
    let beamSize: Int?
    let bestOf: Int?
    let suppressRegex: String?
    let initialPrompt: String?
    let vad: Bool
    let diarize: Bool
    let durationEstimate: TimeInterval?
    let preferredTask: String
    let preserveTimestamps: Bool
}

// MARK: - Core ML Engine
class CoreMLTranscriptionEngine: TranscriptionEngine {
    private let pipeline: WhisperKit
    var progressHandler: ((Double) -> Void)?

    init(modelDirectory: URL, preferredTask: String) async throws {
        print("🔍 [TranscriptionEngine] Initializing with modelDirectory: \(modelDirectory.path)")
        let resourceValues = try? modelDirectory.resourceValues(forKeys: [.isDirectoryKey])
        print("🔍 [TranscriptionEngine] Directory exists: \(resourceValues?.isDirectory ?? false)")
        
        if resourceValues?.isDirectory == false && modelDirectory.pathExtension.lowercased() == "bin" {
            throw TranscriptionError.modelLoadingFailed("GGML weights currently require Whisper.cpp bindings. Please choose a Core ML (.mlpackage) model or enable cloud offload.")
        }

        print("🔍 [TranscriptionEngine] Creating WhisperKit with modelFolder: \(modelDirectory.path)")
        pipeline = try await WhisperKit(
            model: nil,
            modelFolder: modelDirectory.path,
            load: true,
            download: false
        )
        print("✅ [TranscriptionEngine] WhisperKit initialized successfully")
    }

    func transcribe(audioURL: URL, settings: TranscriptionSettings) async throws -> TranscriptionResult {
        var decodeOptions = DecodingOptions()
        decodeOptions.task = settings.translate ? .translate : .transcribe
        decodeOptions.language = settings.language
        decodeOptions.detectLanguage = settings.language == nil
        
        // Wire AppSettings through to WhisperKit decode options
        if let temperature = settings.temperature {
            decodeOptions.temperature = temperature
        }
        if let beamSize = settings.beamSize, beamSize > 0 {
            decodeOptions.topK = beamSize
        }
        // Note: WhisperKit VAD is automatic; diarization requires separate models
        // suppressRegex would need custom post-processing
        
        progressHandler?(0.1)

        let transcriptionResults = try await pipeline.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions,
            callback: { [weak self] progress in
                let elapsed = progress.timings.fullPipeline
                let estimated = progress.timings.inputAudioSeconds
                if estimated > 0, elapsed.isFinite {
                    let ratio = min(max(elapsed / estimated, 0), 1)
                    self?.progressHandler?(ratio)
                }
                return true
            }
        )

        guard let transcription = transcriptionResults.first else {
            throw TranscriptionError.inferenceFailed("No transcription results")
        }

        let segments = transcription.segments.map { segment in
            TranscriptionSegment(
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end),
                text: sanitizeTranscriptText(segment.text, preserve: settings.preserveTimestamps),
            )
        }

        let duration = segments.last?.end ?? settings.durationEstimate ?? 0

        return TranscriptionResult(
            text: sanitizeTranscriptText(transcription.text, preserve: settings.preserveTimestamps),
            segments: segments,
            language: transcription.language,
            duration: duration
        )
    }
}

// MARK: - Cloud Transcription Provider
class CloudTranscriptionProvider: TranscriptionEngine {
    private let uploader = ChunkedUploader()

    private func executeWithRetry(attempts: Int = 3, operation: @escaping @Sendable () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delay: UInt64 = 200_000_000
        var lastError: Error?

        while attempt < attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                attempt += 1
                // AppLogger.log("Network retry \(attempt)/\(attempts) due to: \(error.localizedDescription)", category: AppLogger.network, level: .info)
                if attempt >= attempts {
                    break
                }
                try? await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    enum Provider {
        case openai
        case gemini
    }

    private let provider: Provider
    private let apiKey: String?
    var progressHandler: ((Double) -> Void)?

    // Cache Gemini model names per process to avoid repeated list calls
    private static var cachedGeminiModels: [String]?

    init(provider: Provider, apiKey: String?) {
        self.provider = provider
        self.apiKey = apiKey
    }

    func transcribe(audioURL: URL, settings: TranscriptionSettings) async throws -> TranscriptionResult {
        switch provider {
        case .openai:
            return try await transcribeWithOpenAI(audioURL: audioURL, settings: settings)
        case .gemini:
            return try await transcribeWithGemini(audioURL: audioURL, settings: settings)
        }
    }

    private func transcribeWithOpenAI(audioURL: URL, settings: TranscriptionSettings) async throws -> TranscriptionResult {
        guard let apiKey = apiKey else { throw TranscriptionError.missingAPIKey(provider: "OpenAI") }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let multipartFile = try createMultipartFormFile(
            boundary: boundary, 
            audioURL: audioURL, 
            model: "whisper-1", 
            translate: settings.translate,
            temperature: settings.temperature,
            enableTimestampGranularities: settings.diarize  // Request speaker labels if diarization enabled
        )
        defer { try? FileManager.default.removeItem(at: multipartFile.url) }
        request.setValue(String(multipartFile.length), forHTTPHeaderField: "Content-Length")
        let uploadRequest = request

        let start = Date()
        let (data, response) = try await executeWithRetry { [self] in
            try await self.uploader.uploadFile(uploadRequest, fileURL: multipartFile.url)
        }
        progressHandler?(0.2)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.http(status: -1, body: "Invalid response", provider: "OpenAI")
        }

        guard httpResponse.statusCode == 200 else {
            let body = prettyErrorBody(from: data, provider: "OpenAI")
            // AppLogger.log("OpenAI error (\(httpResponse.statusCode)): \(body)", category: AppLogger.network, level: .error)
            await MainActor.run {
                NotifyToastManager.shared.show("OpenAI failed: \(httpResponse.statusCode)", icon: "xmark.octagon", style: .error)
                AnalyticsTracker.shared.record(.jobFailed(modelID: "whisper-1", reason: body))
            }
            throw TranscriptionError.http(status: httpResponse.statusCode, body: body, provider: "OpenAI")
        }

        progressHandler?(0.6)

        let latency = Date().timeIntervalSince(start)
        // AppLogger.log("OpenAI transcription success (latency: \(String(format: "%.2fs", latency)), duration estimate: \(settings.durationEstimate ?? 0))", category: AppLogger.network, level: .info)
        await MainActor.run {
            NotifyToastManager.shared.show("OpenAI transcription complete", icon: "cloud.fill", style: .success)
            AnalyticsTracker.shared.record(.jobCompleted(modelID: "whisper-1", duration: settings.durationEstimate ?? 0))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiResponse = try decoder.decode(OpenAITranscriptionResponse.self, from: data)

        let segments = apiResponse.segments?.map { segment in
            TranscriptionSegment(start: segment.start, end: segment.end, text: sanitizeTranscriptText(segment.text, preserve: settings.preserveTimestamps))
        } ?? [TranscriptionSegment(start: 0.0, end: settings.durationEstimate ?? 0.0, text: apiResponse.text)]

        progressHandler?(1.0)

        return TranscriptionResult(
            text: sanitizeTranscriptText(apiResponse.text, preserve: settings.preserveTimestamps),
            segments: segments,
            language: apiResponse.language ?? settings.language,
            duration: segments.last?.end ?? settings.durationEstimate ?? 0.0
        )
    }

    private func transcribeWithGemini(audioURL: URL, settings: TranscriptionSettings) async throws -> TranscriptionResult {
        guard let apiKey = apiKey else { throw TranscriptionError.missingAPIKey(provider: "Gemini") }
        // Resolve endpoint/model combinations and retry on 404 with a different base/model
        func makeURL(base: String, model: String) -> URL {
            URL(string: "https://generativelanguage.googleapis.com/\(base)/\(model):generateContent?key=\(apiKey)")!
        }

        // Fetch available models (once) if none provided in settings
        if (settings.preferredTask.isEmpty) { /* no-op, placeholder to satisfy lints if needed */ }
        if CloudTranscriptionProvider.cachedGeminiModels == nil {
            CloudTranscriptionProvider.cachedGeminiModels = try? await fetchGeminiModelNames(apiKey: apiKey)
        }

        // Default to commonly available combo; retry logic will adjust if needed
        var base = "v1"
        var model = "models/gemini-1.5-flash-001"
        var request = URLRequest(url: makeURL(base: base, model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let base64 = audioData.base64EncodedString()

        let payload = GeminiRequest(contents: [
            GeminiRequest.Content(parts: [
                .init(text: "Transcribe the provided audio and return plain text captions with timestamps."),
                .init(inlineData: .init(mimeType: "audio/wav", data: base64))
            ])
        ])

        request.httpBody = try JSONEncoder().encode(payload)
        let dataRequest = request

        let start = Date()
        let (data, response) = try await executeWithRetry {
            try await URLSession.shared.data(for: dataRequest)
        }
        progressHandler?(0.2)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.http(status: -1, body: "Invalid response", provider: "Gemini")
        }

        guard httpResponse.statusCode == 200 else {
            let body = prettyErrorBody(from: data, provider: "Gemini")
            // AppLogger.log("Gemini error (\(httpResponse.statusCode)): \(body)", category: AppLogger.network, level: .error)
            if httpResponse.statusCode == 404 {
                // Retry with alternate base/model combinations
                let fallbacks: [(String, String)] = [
                    ("v1", "models/gemini-1.5-flash"),
                    ("v1beta", "models/gemini-1.5-flash-latest"),
                    ("v1", "models/gemini-1.5-flash-001"),
                    ("v1beta", "models/gemini-1.5-pro"),
                    ("v1", "models/gemini-1.5-pro"),
                    ("v1beta", "models/gemini-1.5-flash-002")
                ]
                for (b, m) in fallbacks {
                    base = b; model = m
                    var retry = URLRequest(url: makeURL(base: b, model: m))
                    retry.httpMethod = "POST"
                    retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    retry.httpBody = request.httpBody
                    do {
                        let (rd, rr) = try await URLSession.shared.data(for: retry)
                        if let rresp = rr as? HTTPURLResponse, rresp.statusCode == 200 {
                            request = retry
                            // Swap to success path with rd
                            let apiResponse = try decodeGeminiResponse(from: rd)
                            guard let firstCandidate = apiResponse.candidates.first else {
                                throw TranscriptionError.emptyResponse(provider: "Gemini")
                            }
                            progressHandler?(0.6)
                            let text = sanitizeTranscriptText(firstCandidate.content.parts.compactMap { $0.text }.joined(separator: " "), preserve: settings.preserveTimestamps)
                            let segs = [TranscriptionSegment(start: 0.0, end: settings.durationEstimate ?? 0.0, text: text)]
                            let result = TranscriptionResult(text: text, segments: segs, language: settings.language, duration: segs.last?.end ?? settings.durationEstimate ?? 0.0)
                            let latency = Date().timeIntervalSince(start)
                            // AppLogger.log("Gemini transcription success (fallback: base=\(b), model=\(m), latency: \(String(format: "%.2fs", latency)))", category: AppLogger.network, level: .info)
                            await MainActor.run {
                                NotifyToastManager.shared.show("Gemini transcription complete", icon: "cloud.sun.fill", style: .success)
                                AnalyticsTracker.shared.record(.jobCompleted(modelID: m, duration: settings.durationEstimate ?? 0))
                            }
                            return result
                        }
                    } catch { /* try next */ }
                }
                // If still failing, try discovered models list (if available)
                if let discovered = CloudTranscriptionProvider.cachedGeminiModels, !discovered.isEmpty {
                    // Prefer flash, then pro, then rest
                    let sorted = discovered.sorted { a, b in
                        let sa = scoreModelName(a)
                        let sb = scoreModelName(b)
                        return sa > sb
                    }
                    for fullName in sorted {
                        var retry = URLRequest(url: makeURL(base: "v1", model: fullName))
                        retry.httpMethod = "POST"
                        retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        retry.httpBody = request.httpBody
                        do {
                            let (rd, rr) = try await URLSession.shared.data(for: retry)
                            if let rresp = rr as? HTTPURLResponse, rresp.statusCode == 200 {
                                let apiResponse = try decodeGeminiResponse(from: rd)
                                guard let firstCandidate = apiResponse.candidates.first else { continue }
                                progressHandler?(0.6)
                                let text = sanitizeTranscriptText(firstCandidate.content.parts.compactMap { $0.text }.joined(separator: " "), preserve: settings.preserveTimestamps)
                                let segs = [TranscriptionSegment(start: 0.0, end: settings.durationEstimate ?? 0.0, text: text)]
                                let result = TranscriptionResult(text: text, segments: segs, language: settings.language, duration: segs.last?.end ?? settings.durationEstimate ?? 0.0)
                                let latency = Date().timeIntervalSince(start)
                                // AppLogger.log("Gemini transcription success (discovered model: \(fullName), latency: \(String(format: "%.2fs", latency)))", category: AppLogger.network, level: .info)
                                await MainActor.run {
                                    NotifyToastManager.shared.show("Gemini transcription complete", icon: "cloud.sun.fill", style: .success)
                                    AnalyticsTracker.shared.record(.jobCompleted(modelID: fullName, duration: settings.durationEstimate ?? 0))
                                }
                                return result
                            }
                        } catch { /* continue */ }
                    }
                }
            }
            let failedModel = model
            await MainActor.run {
                NotifyToastManager.shared.show("Gemini failed: \(httpResponse.statusCode)", icon: "xmark.octagon", style: .error)
                AnalyticsTracker.shared.record(.jobFailed(modelID: failedModel, reason: body))
            }
            throw TranscriptionError.http(status: httpResponse.statusCode, body: body, provider: "Gemini")
        }

        progressHandler?(0.6)
        let latency = Date().timeIntervalSince(start)
        // AppLogger.log("Gemini transcription success (latency: \(String(format: "%.2fs", latency)), duration estimate: \(settings.durationEstimate ?? 0))", category: AppLogger.network, level: .info)
        let successModel = model
        await MainActor.run {
            NotifyToastManager.shared.show("Gemini transcription complete", icon: "cloud.sun.fill", style: .success)
            AnalyticsTracker.shared.record(.jobCompleted(modelID: successModel, duration: settings.durationEstimate ?? 0))
        }
        let apiResponse = try decodeGeminiResponse(from: data)
        guard let firstCandidate = apiResponse.candidates.first else {
            throw TranscriptionError.emptyResponse(provider: "Gemini")
        }

        let text = sanitizeTranscriptText(firstCandidate.content.parts.compactMap { $0.text }.joined(separator: " "), preserve: settings.preserveTimestamps)
        let segments = [TranscriptionSegment(start: 0.0, end: settings.durationEstimate ?? 0.0, text: text)]

        progressHandler?(1.0)

        return TranscriptionResult(
            text: text,
            segments: segments,
            language: settings.language,
            duration: segments.last?.end ?? settings.durationEstimate ?? 0.0
        )
    }
}

// MARK: - Engine Factory
class TranscriptionEngineFactory {
    static func createEngine(type: TranscriptionEngineType, context: EngineContext) async throws -> TranscriptionEngine {
        switch type {
        case .local:
            return try await CoreMLTranscriptionEngine(modelDirectory: context.modelDirectory, preferredTask: context.preferredTask)
        case .openai:
            return CloudTranscriptionProvider(provider: .openai, apiKey: context.apiKey)
        case .gemini:
            return CloudTranscriptionProvider(provider: .gemini, apiKey: context.apiKey)
        }
    }
}

enum TranscriptionEngineType {
    case local
    case openai
    case gemini
}

struct EngineContext {
    let modelDirectory: URL
    let preferredTask: String
    let apiKey: String?
}

// MARK: - Transcript sanitizer
@inline(__always)
private func sanitizeTranscriptText(_ text: String, preserve: Bool) -> String {
    if preserve { return text }
    // Remove special tokens like <|startoftranscript|>, <|endoftranscript|>
    // and inline timestamp markers like <|0.00|> etc.
    if text.isEmpty { return text }
    var cleaned = text
    // Fast path: if no '<|' present, return immediately
    // We'll still do additional cleanup for bracketed cues below
    // Remove known markers
    let patterns: [String] = [
        "<\\|startoftranscript\\|>",
        "<\\|endoftranscript\\|>",
        "<\\|startofprompt\\|>",
        "<\\|endofprompt\\|>"
    ]
    for p in patterns {
        cleaned = cleaned.replacingOccurrences(of: p, with: "", options: .regularExpression)
    }
    // Strip any <|number|> style timestamp tokens (e.g., <|0.00|>, <|12.345|>)
    cleaned = cleaned.replacingOccurrences(
        of: "<\\|[0-9]+(\\.[0-9]+)?\\|>",
        with: "",
        options: .regularExpression
    )
    // Remove leading bracketed time ranges like: [ 0m0s118ms - 0m3s918ms ]
    // Do this per-line so we can keep the spoken text that follows
    let lines = cleaned.components(separatedBy: .newlines).map { line -> String in
        var lineOut = line
        // Remove leading bracketed range
        lineOut = lineOut.replacingOccurrences(
            of: "^\\s*\\[[^\\]]*\\]\\s*",
            with: "",
            options: [.regularExpression]
        )
        // If the remaining line is only a parenthetical non-speech cue, drop it
        let trimmed = lineOut.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return ""
        }
        // Otherwise, remove inline parenthetical cues like (Engine sounds)
        lineOut = lineOut.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        return lineOut.trimmingCharacters(in: .whitespaces)
    }
    cleaned = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    // Collapse excess whitespace introduced by removals
    cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
}

// MARK: - OpenAI DTOs
private struct OpenAITranscriptionResponse: Decodable {
    struct Segment: Decodable {
        let start: Double
        let end: Double
        let text: String
    }

    let text: String
    let language: String?
    let segments: [Segment]?
}

// MARK: - Gemini DTOs
private struct GeminiRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            struct InlineData: Encodable {
                let mimeType: String
                let data: String
            }

            let text: String?
            let inlineData: InlineData?

            init(text: String) {
                self.text = text
                self.inlineData = nil
            }

            init(inlineData: InlineData) {
                self.text = nil
                self.inlineData = inlineData
            }
        }

        let parts: [Part]
    }

    let contents: [Content]
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        struct Part: Decodable {
            let text: String?
        }

        let parts: [Part]
    }

    let candidates: [Candidate]
}

// MARK: - Gemini model listing
private struct GeminiModelList: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private func fetchGeminiModelNames(apiKey: String) async throws -> [String] {
    let bases = ["v1", "v1beta"]
    var names: Set<String> = []
    for base in bases {
        if let url = URL(string: "https://generativelanguage.googleapis.com/\(base)/models?key=\(apiKey)") {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let list = try? JSONDecoder().decode(GeminiModelList.self, from: data) {
                        list.models.forEach { names.insert($0.name) }
                    }
                }
            } catch { /* continue */ }
        }
    }
    return Array(names)
}

private func scoreModelName(_ name: String) -> Int {
    var score = 0
    let lower = name.lowercased()
    if lower.contains("flash") { score += 3 }
    if lower.contains("pro") { score += 2 }
    if lower.contains("1.5") { score += 1 }
    if lower.contains("latest") { score += 1 }
    return score
}

// MARK: - Multipart helper
private func createMultipartFormFile(
    boundary: String, 
    audioURL: URL, 
    model: String, 
    translate: Bool,
    temperature: Float? = nil,
    enableTimestampGranularities: Bool = false
) throws -> (url: URL, length: Int64) {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("openai-upload-\(UUID().uuidString).tmp")
    FileManager.default.createFile(atPath: tempURL.path, contents: nil)

    guard let handle = try? FileHandle(forWritingTo: tempURL) else {
        throw TranscriptionError.unknown("Unable to create multipart form file")
    }

    func write(_ string: String) throws {
        if let data = string.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    try write("--\(boundary)\r\n")
    try write("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    try write("\(model)\r\n")

    if translate {
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"translate\"\r\n\r\n")
        try write("true\r\n")
    }
    
    if let temperature = temperature {
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        try write("\(temperature)\r\n")
    }
    
    // Request detailed timestamps for potential diarization
    if enableTimestampGranularities {
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n")
        try write("segment\r\n")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        try write("verbose_json\r\n")
    }

    try write("--\(boundary)\r\n")
    try write("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
    try write("Content-Type: audio/wav\r\n\r\n")

    let audioHandle = try FileHandle(forReadingFrom: audioURL)
    defer { try? audioHandle.close() }
    while autoreleasepool(invoking: {
        let chunk = audioHandle.readData(ofLength: 1_048_576)
        if !chunk.isEmpty {
            try? handle.write(contentsOf: chunk)
            return true
        }
        return false
    }) {}

    try write("\r\n")
    try write("--\(boundary)--\r\n")
    let length = try handle.seekToEnd()
    try handle.close()

    return (tempURL, Int64(length))
}

private func prettyErrorBody(from data: Data, provider: String) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String
            let code = error["code"] ?? error["status"]
            let reason = error["reason"] ?? error["type"]
            return [message, code, reason]
                .compactMap { $0 }
                .map { String(describing: $0) }
                .joined(separator: " | ")
        }
    }
    return String(data: data, encoding: .utf8) ?? "Unknown \(provider) error"
}

private func decodeGeminiResponse(from data: Data) throws -> GeminiResponse {
    if let jsonString = String(data: data, encoding: .utf8), jsonString.contains("data:") {
        let lines = jsonString.split(separator: "\n").filter { $0.hasPrefix("data:") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let candidates = try lines.compactMap { line -> GeminiResponse.Candidate? in
            let payload = line.dropFirst(5)
            guard let payloadData = payload.data(using: .utf8) else { return nil }
            return try decoder.decode(GeminiResponse.Candidate.self, from: payloadData)
        }
        return GeminiResponse(candidates: candidates)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(GeminiResponse.self, from: data)
}
