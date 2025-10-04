import Foundation
import Combine
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
final class LiveTranscriptionManager: ObservableObject {
    @Published private(set) var partialText: String = ""
    @Published private(set) var finalText: String = ""
    @Published private(set) var confidence: Float = 0
    @Published private(set) var backend: LiveTranscriptionBackend = .appleNative
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var errorMessage: String?

    var combinedText: String {
        finalText.isEmpty ? partialText : finalText
    }

    private var appleEngine: AppleStreamingEngine?
    private var streamingDelegate: StreamingDelegateProxy?
    private var liveSession: LiveTranscriptionSession?
    private var windowedEngine: TranscriptionEngine?
#if canImport(AVFoundation)
    private var audioCapture: AudioLiveCapture?
    private var captureCancellable: AnyCancellable?
    private var liveAudioFile: AVAudioFile?
    var liveAudioURL: URL?
    private var lastSaveAt: Date?
#endif
    private var aggregatedSegments: [TranscriptionSegment] = []
    private var stopObserver: NSObjectProtocol?

    func start(settings: AppSettings, modelManager: ModelDownloadManager) async {
        stop()
        backend = settings.liveTranscriptionBackend
        errorMessage = nil
        aggregatedSegments.removeAll()
        partialText = ""
        finalText = ""
        confidence = 0
        CaptureStatusCenter.shared.isLiveStreaming = true
        // Observe global stop from HUD
        stopObserver = NotificationCenter.default.addObserver(forName: CaptureStatusCenter.stopLiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }

        StorageManager.appendToDiagnosticsLog("[LIVE] Selected backend: \(backend)")
        switch backend {
        case .appleNative:
            await startAppleStreaming()
        case .whisperTiny, .whisperBase:
            StorageManager.appendToDiagnosticsLog("[LIVE] Starting Whisper backend: \(backend)")
            await startWindowedStreaming(settings: settings, modelManager: modelManager)
        }
    }

    func stop() {
        StorageManager.appendToDiagnosticsLog("[LIVE] LiveTranscriptionManager stopping - cleaning up all audio resources")
        
        isStreaming = false
        CaptureStatusCenter.shared.isLiveStreaming = false
        streamingDelegate = nil
        if let token = stopObserver {
            NotificationCenter.default.removeObserver(token)
            stopObserver = nil
        }
        
        // Preserve Apple Native capture so user can save after stopping
        #if canImport(Speech)
        if let url = appleEngine?.finalizeCapture() {
            self.liveAudioURL = url
            StorageManager.appendToDiagnosticsLog("[LIVE] Preserved Apple Native audio: \(url.lastPathComponent)")
        }
        
        // Stop Apple engine with proper cleanup
        if let engine = appleEngine {
            StorageManager.appendToDiagnosticsLog("[LIVE] Stopping Apple Native engine")
            engine.stop()
            StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native engine stopped")
        }
        appleEngine = nil
        #endif

        // Stop live session with proper cleanup
        if let session = liveSession {
            StorageManager.appendToDiagnosticsLog("[LIVE] Stopping live session")
            session.stop()
            StorageManager.appendToDiagnosticsLog("[LIVE] Live session stopped")
        }
        liveSession = nil
        
        // Clear windowedEngine after stopping the session
        windowedEngine = nil
        
#if canImport(AVFoundation)
        // Cancel any pending capture operations
        captureCancellable?.cancel()
        captureCancellable = nil
        
        // Stop audio capture with proper cleanup
        if let capture = audioCapture {
            StorageManager.appendToDiagnosticsLog("[LIVE] Stopping audio capture")
            capture.stop()
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio capture stopped")
        }
        audioCapture = nil
        
        // Close current live file so it's finalized on disk
        liveAudioFile = nil
#endif
        
        if finalText.isEmpty && !aggregatedSegments.isEmpty {
            finalText = aggregatedSegments.map { $0.text }.joined(separator: " ")
        }
        // Keep partial text after stop so user can still see and save it
        
        StorageManager.appendToDiagnosticsLog("[LIVE] LiveTranscriptionManager stop completed")
    }

    private func startAppleStreaming() async {
        StorageManager.appendToDiagnosticsLog("[LIVE] Starting Apple Native live transcription")
        
        // Add a small delay to prevent rapid start/stop cycles
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let engine = AppleStreamingEngine()
        let delegate = StreamingDelegateProxy(
            onPartial: { [weak self] text in
                guard let self else { return }
                self.partialText = Self.sanitize(text)
                self.confidence = max(self.confidence, 0.5)
            },
            onFinal: { [weak self] text in
                guard let self else { return }
                if !text.isEmpty {
                    self.finalText = Self.sanitize(text)
                    self.partialText = ""
                }
            },
            onConfidence: { [weak self] value in
                self?.confidence = value
            },
            onStop: { [weak self] in
                self?.isStreaming = false
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                StorageManager.logError(error, context: "Apple Native Live Transcription Error")
                
                // Handle specific error types more gracefully
                if let nsError = error as NSError? {
                    switch nsError.code {
                    case -1009: // Network error
                        NotifyToastManager.shared.show("Network error - continuing offline", icon: "wifi.slash", style: .warning)
                        return // Don't stop for network errors
                    case -1001: // Timeout error
                        NotifyToastManager.shared.show("Speech recognition timeout", icon: "clock", style: .warning)
                        return // Don't stop for timeout errors
                    case -2: // Audio hardware error
                        NotifyToastManager.shared.show("Audio hardware error", icon: "exclamationmark.triangle", style: .error)
                        self.stop()
                        return
                    default:
                        // For "No speech detected" errors, don't show toast or stop
                        if nsError.localizedDescription.contains("No speech detected") {
                            return
                        }
                        NotifyToastManager.shared.show("Live transcription error: \(error.localizedDescription)", icon: "exclamationmark.triangle", style: .error)
                        return
                    }
                }
            },
            onAudioCaptureStarted: { [weak self] url in
                guard let self else { return }
                self.liveAudioURL = url
                StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native audio capture URL set: \(url.lastPathComponent)")
            }
        )

        engine.delegate = delegate
        streamingDelegate = delegate
        appleEngine = engine
        isStreaming = true
        do {
            try await engine.start(localeIdentifier: nil)
        } catch {
            errorMessage = error.localizedDescription
            
            // Provide specific error messages based on the error type
            if let nsError = error as NSError? {
                switch nsError.code {
                case -2: // Audio hardware not available
                    NotifyToastManager.shared.show("Audio hardware not available in simulator. Please test on a real device.", icon: "iphone", style: .warning)
                case -1: // Speech permission or recognizer issues
                    NotifyToastManager.shared.show("Speech recognition not available", icon: "mic.slash", style: .error)
                default:
                    NotifyToastManager.shared.show("Live transcription failed: \(error.localizedDescription)", icon: "exclamationmark.triangle", style: .error)
                }
            } else {
                NotifyToastManager.shared.show("Live transcription failed", icon: "exclamationmark.triangle", style: .error)
            }
            stop()
        }
    }

    private func startWindowedStreaming(settings: AppSettings, modelManager: ModelDownloadManager) async {
#if canImport(AVFoundation)
        guard let modelID = backend.requiredModelID,
              let model = modelManager.models.first(where: { $0.id == modelID }) else {
            errorMessage = "Model not available"
            NotifyToastManager.shared.show("Live model missing", icon: "exclamationmark.triangle", style: .error)
            return
        }

        guard let modelPath = modelManager.getLocalModelPath(for: model) else {
            errorMessage = "Model needs download"
            NotifyToastManager.shared.show("Download \(model.displayName) for live mode", icon: "arrow.down.circle", style: .warning)
            return
        }

        do {
            windowedEngine = try await CoreMLTranscriptionEngine(modelDirectory: modelPath, preferredTask: settings.preferredTask)
        } catch {
            errorMessage = error.localizedDescription
            NotifyToastManager.shared.show("Failed to load live model", icon: "xmark.octagon", style: .error)
            return
        }

        let session = LiveTranscriptionSession(config: .default) { [weak self] in
            guard let self, let engine = self.windowedEngine else {
                fatalError("LiveTranscriptionManager windowedEngine missing")
            }
            return engine
        }
        session.delegate = self
        liveSession = session
        session.start()

        let capture = AudioLiveCapture()
        audioCapture = capture
        captureCancellable = capture.bufferPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak session] buffer in
                guard let self else { return }
                // Lazily open a file for the live session so we can save audio
                #if canImport(AVFoundation)
                if self.liveAudioFile == nil {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
                    let base = "Live-\(timestamp)-\(UUID().uuidString)"
                    let url = StorageManager.makeRecordingURL(filename: "\(base).wav")
                    do {
                        // Use the output format we are feeding to the model (16k mono) for consistency
                        let settings = [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: 16000,
                            AVNumberOfChannelsKey: 1,
                            AVLinearPCMIsFloatKey: true,
                            AVLinearPCMBitDepthKey: 32
                        ] as [String : Any]
                        self.liveAudioFile = try AVAudioFile(forWriting: url, settings: settings)
                        self.liveAudioURL = url
                        StorageManager.appendToDiagnosticsLog("[LIVE] audio file started: \(url.lastPathComponent)")
                    } catch {
                        StorageManager.appendToDiagnosticsLog("[LIVE] failed to open audio file: \(error.localizedDescription)")
                    }
                }
                if let file = self.liveAudioFile {
                    do { try file.write(from: buffer) } catch {
                        StorageManager.appendToDiagnosticsLog("[LIVE] audio write failed: \(error.localizedDescription)")
                    }
                }
                #endif
                session?.ingest(buffer: buffer)
            }

        do {
            try capture.start()
            isStreaming = true
        } catch {
            errorMessage = error.localizedDescription
            NotifyToastManager.shared.show("Microphone access failed", icon: "mic.slash", style: .error)
            stop()
        }
#else
        errorMessage = "Live capture not supported"
#endif
    }
}

@MainActor
extension LiveTranscriptionManager: LiveTranscriptionSessionDelegate {
    nonisolated func liveSession(didUpdateETA secondsRemaining: TimeInterval) {
        Task { @MainActor in
            // Could surface ETA in future UI revisions
            _ = secondsRemaining
        }
    }

    nonisolated func liveSession(didEmitPartial segments: [TranscriptionSegment]) {
        Task { @MainActor in
            aggregatedSegments.append(contentsOf: segments)
            let combined = aggregatedSegments.map { $0.text }.joined(separator: " ")
            // Treat combined rolling text as partial to show in the Live box
            partialText = LiveTranscriptionManager.sanitize(combined)
            confidence = min(confidence + 0.1, 0.9)
        }
    }

    nonisolated func liveSessionDidComplete(final result: TranscriptionResult) {
        Task { @MainActor in
            finalText = LiveTranscriptionManager.sanitize(result.text)
            partialText = ""
        }
    }

    nonisolated func liveSession(didError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            NotifyToastManager.shared.show("Live transcription error", icon: "exclamationmark.triangle", style: .error)
            stop()
        }
    }
}

// MARK: - Sanitization
extension LiveTranscriptionManager {
    static func sanitize(_ text: String) -> String {
        // Remove Whisper special tokens like <|endoftext|>, <|...|>, and any <...>
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    // Finalize the current live audio file for saving
    func finalizeLiveFileForSaving() -> URL? {
        #if canImport(AVFoundation)
        // Check for CoreML audio file first
        if let currentURL = liveAudioURL {
            // Close the file handle to flush to disk
            liveAudioFile = nil
            
            // Verify the file exists and has content
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: currentURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                StorageManager.appendToDiagnosticsLog("[LIVE] Finalizing live file: \(currentURL.lastPathComponent), size: \(fileSize) bytes")
                
                return currentURL
            } catch {
                StorageManager.appendToDiagnosticsLog("[LIVE] Error finalizing live file: \(error.localizedDescription)")
                return currentURL
            }
        }
        
        // Check for Apple Native audio file
        #if canImport(Speech)
        if let appleURL = appleEngine?.finalizeCapture() {
            StorageManager.appendToDiagnosticsLog("[LIVE] Finalizing Apple Native audio: \(appleURL.lastPathComponent)")
            return appleURL
        }
        #endif
        
        StorageManager.appendToDiagnosticsLog("[LIVE] No live audio URL to finalize")
        return nil
        #else
        return nil
        #endif
    }
    
    // Clean up after saving - call this after successful save
    func cleanupAfterSave() {
        liveAudioURL = nil
        // Don't clear windowedEngine here - it might still be needed for the running CoreML session
        // windowedEngine will be cleared in stop() when the session actually ends
        StorageManager.appendToDiagnosticsLog("[LIVE] Cleaned up after save")
    }

    // Expose Apple Native capture finalization to SwiftUI via ObjC selector (optional)
    @objc func finalizeAppleNativeCapture() -> NSURL? {
        #if canImport(Speech)
        if let engine = appleEngine, let url = engine.finalizeCapture() {
            return url as NSURL
        }
        #endif
        return nil
    }

    func canSaveNow(debounceSeconds: TimeInterval = 1.5) -> Bool {
        let now = Date()
        if let last = lastSaveAt, now.timeIntervalSince(last) < debounceSeconds { return false }
        lastSaveAt = now
        return true
    }
}
