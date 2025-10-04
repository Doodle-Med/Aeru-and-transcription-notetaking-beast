import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(AVAudioApplication)
import AVAudioApplication
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(Speech) && canImport(AVFoundation)
@MainActor
final class AppleStreamingEngine: StreamingEngine {
    weak var delegate: StreamingEngineDelegate?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    private var activeLocaleIdentifier: String?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private let notificationCenter = NotificationCenter.default

    private var captureFile: AVAudioFile?
    private var captureURL: URL?
    private var captureFormat: AVAudioFormat?

    func start(localeIdentifier: String?) async throws {
        activeLocaleIdentifier = localeIdentifier
        
        StorageManager.logUserAction("Apple Native Live Transcription", details: "Starting with locale: \(localeIdentifier ?? "default")")
        
        // Check microphone permission first
        let micAuth = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        guard micAuth else {
            StorageManager.logUserAction("Apple Native Live Transcription", details: "Failed - Microphone permission denied")
            StorageManager.appendToDiagnosticsLog("[LIVE] Microphone permission denied")
            throw NSError(domain: "Streaming", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
        }
        StorageManager.logSystemEvent("Microphone Permission", details: "Granted")
        StorageManager.appendToDiagnosticsLog("[LIVE] Microphone permission granted")
        
        // Permissions
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        StorageManager.logSystemEvent("Speech Recognition Permission", details: "Status: \(speechAuth.rawValue)")
        guard speechAuth == .authorized else {
            StorageManager.logUserAction("Apple Native Live Transcription", details: "Failed - Speech permission denied: \(speechAuth)")
            StorageManager.appendToDiagnosticsLog("[LIVE] Speech recognition permission denied")
            throw NSError(domain: "Streaming", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech permission denied"])
        }
        StorageManager.logSystemEvent("Speech Recognition Permission", details: "Granted")
        StorageManager.appendToDiagnosticsLog("[LIVE] Speech recognition permission granted")

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Configure audio session for both simulator and device with better conflict handling
        do {
            #if targetEnvironment(simulator)
            // Simulator: use record mode with mixWithOthers to prevent conflicts
            try session.setCategory(.record, mode: .default, options: [.mixWithOthers])
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio session configured for simulator with mixWithOthers")
            #else
            // Device: try multiple configurations for better compatibility
            var configured = false
                    let configurations = [
                        (category: AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.measurement, options: AVAudioSession.CategoryOptions.defaultToSpeaker.union(.allowBluetoothHFP).union(.allowBluetoothA2DP)),
                        (category: AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.defaultToSpeaker.union(.allowBluetoothHFP).union(.allowBluetoothA2DP)),
                        (category: AVAudioSession.Category.record, mode: AVAudioSession.Mode.measurement, options: AVAudioSession.CategoryOptions.allowBluetoothHFP.union(.allowBluetoothA2DP)),
                        (category: AVAudioSession.Category.record, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetoothHFP.union(.allowBluetoothA2DP))
                    ]
            
            for (index, config) in configurations.enumerated() {
                do {
                    try session.setCategory(config.category, mode: config.mode, options: config.options)
                    StorageManager.logSystemEvent("Audio Session Config", details: "Success with config \(index + 1): \(config.category.rawValue), \(config.mode.rawValue)")
                    StorageManager.appendToDiagnosticsLog("[LIVE] Audio session configured for device with config \(index + 1): \(config.category.rawValue), \(config.mode.rawValue)")
                    configured = true
                    break
                } catch {
                    StorageManager.logSystemEvent("Audio Session Config", details: "Failed config \(index + 1): \(error.localizedDescription)")
                    StorageManager.appendToDiagnosticsLog("[LIVE] Audio session config \(index + 1) failed: \(error.localizedDescription)")
                    continue
                }
            }
            
            guard configured else {
                throw NSError(domain: "Streaming", code: -2, userInfo: [NSLocalizedDescriptionKey: "All audio session configurations failed"])
            }
            #endif
            // Set buffer duration with fallback
            do {
                try session.setPreferredIOBufferDuration(0.02)
            } catch {
                try session.setPreferredIOBufferDuration(0.01) // Fallback to smaller buffer
                StorageManager.logSystemEvent("Audio Session Buffer", details: "Using fallback buffer duration: 0.01")
                StorageManager.appendToDiagnosticsLog("[LIVE] Using fallback buffer duration: 0.01")
            }
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio session configured successfully")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio session configuration failed: \(error.localizedDescription)")
            // Fallback to basic configuration with mixWithOthers
            do {
                        #if targetEnvironment(simulator)
                        try session.setCategory(.record, options: [.mixWithOthers])
                        #else
                        try session.setCategory(.playAndRecord, options: AVAudioSession.CategoryOptions.defaultToSpeaker.union(.mixWithOthers))
                        #endif
                StorageManager.appendToDiagnosticsLog("[LIVE] Fallback audio session configuration successful")
            } catch {
                StorageManager.appendToDiagnosticsLog("[LIVE] Fallback audio session configuration failed: \(error.localizedDescription)")
            }
        }
        
        do {
            try session.setActive(true)
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio session activated successfully")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to activate audio session: \(error.localizedDescription)")
            throw NSError(domain: "Streaming", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio session activation failed"])
        }
        #endif

        // Create audio engine with proper configuration
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Reset engine to clear any previous state
        engine.reset()
        StorageManager.appendToDiagnosticsLog("[LIVE] Audio engine created and reset")

        let locale = localeIdentifier.flatMap { Locale(identifier: $0) }
        let recognizer = locale.map { SFSpeechRecognizer(locale: $0) } ?? SFSpeechRecognizer()
        guard let recognizer else {
            throw NSError(domain: "Streaming", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recognizer not available"])
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        #if targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = false // simulator may not have on-device models
        #else
        request.requiresOnDeviceRecognition = true // prefer on-device for better performance and privacy
        #endif
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error = error {
                StorageManager.logError(error, context: "Speech Recognition Task Error")
                
                // Check if this is a recoverable error
                if let nsError = error as NSError? {
                    switch nsError.code {
                    case -1009: // Network error - speech recognition might need network
                        StorageManager.appendToDiagnosticsLog("[LIVE] Network error in speech recognition - continuing with local processing")
                        return // Don't propagate network errors
                    case -1001: // Timeout error
                        StorageManager.appendToDiagnosticsLog("[LIVE] Speech recognition timeout - continuing")
                        return // Don't propagate timeout errors
                    default:
                        StorageManager.appendToDiagnosticsLog("[LIVE] Speech recognition error: \(error.localizedDescription)")
                        self.delegate?.streamingEngine(didError: error)
                        return
                    }
                } else {
                    self.delegate?.streamingEngine(didError: error)
                    return
                }
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            StorageManager.appendToDiagnosticsLog("[LIVE] Speech result: isFinal=\(result.isFinal), text='\(String(text.prefix(50)))...'")
            if result.isFinal {
                self.delegate?.streamingEngine(didEmitFinal: text)
                StorageManager.appendToDiagnosticsLog("[LIVE] Emitted final text, continuing to listen...")
                // DON'T stop the engine on final results - continue listening for more speech
                // self.delegate?.streamingEngineDidStop() // REMOVED: This was causing immediate stop
            } else {
                self.delegate?.streamingEngine(didEmitPartial: text)
                let conf = Float(result.bestTranscription.segments.last?.confidence ?? 0)
                self.delegate?.streamingEngine(didUpdateConfidence: conf)
                StorageManager.appendToDiagnosticsLog("[LIVE] Emitted partial text")
            }
        }

        // Prepare the engine first
        engine.prepare()
        
        // Get the input format after engine preparation
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let format: AVAudioFormat
        
        #if targetEnvironment(simulator)
        // Simulator workaround: check if we have valid audio hardware
        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            // Simulator has no audio hardware - throw a more descriptive error
            throw NSError(domain: "Streaming", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio hardware not available in simulator. Please test on a real device."])
        } else {
            format = inputFormat
            print("[STREAMING] Using input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        }
        #else
        format = inputFormat
        #endif
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            // Optional parallel capture directly from input tap (safe: same HW format)
            let captureEnabled = UserDefaults.standard.bool(forKey: "captureNativeLiveAudio")
            if captureEnabled {
                // Create capture file on first buffer (thread-safe)
                if self.captureFile == nil {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
                    let base = "Live-\(timestamp)-\(UUID().uuidString)"
                    let url = StorageManager.makeRecordingURL(filename: "\(base).wav")
                    do {
                        self.captureFormat = buffer.format
                        // Use the buffer's format settings for consistency, but ensure proper audio levels
                        var settings = buffer.format.settings
                        
                        // Enable normalization for better audio levels
                        if UserDefaults.standard.bool(forKey: "normalizeAppleNativeCapture") {
                            settings[AVLinearPCMIsFloatKey] = true
                            StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native audio normalization enabled")
                        }
                        
                        self.captureFile = try AVAudioFile(forWriting: url, settings: settings)
                        self.captureURL = url
                        StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native audio capture started: \(url.lastPathComponent)")
                        StorageManager.appendToDiagnosticsLog("[LIVE] Buffer format: \(buffer.format), channels: \(buffer.format.channelCount), sampleRate: \(buffer.format.sampleRate)")
                        
                        // Notify delegate that audio capture has started
                        delegate?.streamingEngine(didStartAudioCapture: url)
                    } catch {
                        StorageManager.appendToDiagnosticsLog("[LIVE] Failed to create audio file: \(error.localizedDescription)")
                        StorageManager.appendToDiagnosticsLog("[LIVE] Buffer format was: \(buffer.format)")
                    }
                }
                
                // Write buffer to file
                if let file = self.captureFile {
                    do { 
                        try file.write(from: buffer) 
                    } catch {
                        StorageManager.appendToDiagnosticsLog("[LIVE] Audio write failed: \(error.localizedDescription)")
                    }
                }
            } else {
                // Log once when capture is disabled
                if self.captureFile == nil {
                    StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native audio capture disabled - captureNativeLiveAudio=false")
                }
            }
        }
        // No additional mixer/taps; capture happens in the input tap to avoid format mismatches

        attachObservers()
        
        // Start the audio engine with better error handling
        do {
            StorageManager.logSystemEvent("Audio Engine Start Attempt", details: "Device: \(UIDevice.current.model), OS: \(UIDevice.current.systemVersion)")
            try engine.start()
            audioEngine = engine
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio engine started successfully")
            StorageManager.logSystemEvent("Audio Engine Start Success", details: "Engine running: \(engine.isRunning)")
        } catch {
            StorageManager.logError(error, context: "Audio Engine Start Failure")
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to start audio engine: \(error.localizedDescription)")
            
            // Log detailed error information
            if let nsError = error as NSError? {
                StorageManager.appendToDiagnosticsLog("[LIVE] Error domain: \(nsError.domain), code: \(nsError.code)")
                StorageManager.appendToDiagnosticsLog("[LIVE] Error userInfo: \(nsError.userInfo)")
            }
            
            // Clean up on failure to prevent resource leaks
            engine.stop()
            engine.reset()
            
            throw NSError(domain: "Streaming", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to start audio engine: \(error.localizedDescription)"])
        }
    }

    func stop() {
        performStop(notifyDelegate: true)
    }

    private func performStop(notifyDelegate: Bool) {
        StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native stopping - cleaning up audio resources")
        
        // Stop recognition first to prevent new audio processing
        detachObservers()
        recognitionTask?.finish()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Clean up audio engine more carefully to prevent I/O cycle abandonment
        if let engine = audioEngine {
            // Remove tap before stopping to prevent reconfig conflicts
            if engine.inputNode.numberOfInputs > 0 {
                engine.inputNode.removeTap(onBus: 0)
                StorageManager.appendToDiagnosticsLog("[LIVE] Removed audio tap from input node")
            }
            
            // Stop engine and wait for it to fully stop
            if engine.isRunning {
                engine.stop()
                StorageManager.appendToDiagnosticsLog("[LIVE] Audio engine stopped")
            }
            
            // Reset engine to clear any pending configurations
            engine.reset()
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio engine reset")
        }
        audioEngine = nil
        
        // Close audio capture file before deactivating session
        captureFile = nil
        
        #if os(iOS)
        // Deactivate audio session more carefully
        do {
            let session = AVAudioSession.sharedInstance()
            // Check if session is active before trying to deactivate
            if session.isOtherAudioPlaying {
                StorageManager.appendToDiagnosticsLog("[LIVE] Other audio playing, using mixWithOthers option")
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } else {
                try session.setActive(false)
            }
            StorageManager.appendToDiagnosticsLog("[LIVE] Audio session deactivated successfully")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to deactivate audio session: \(error.localizedDescription)")
            // Try fallback deactivation
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                StorageManager.appendToDiagnosticsLog("[LIVE] Fallback audio session deactivation successful")
            } catch {
                StorageManager.appendToDiagnosticsLog("[LIVE] Fallback audio session deactivation failed: \(error.localizedDescription)")
            }
        }
        #endif

        if notifyDelegate {
            delegate?.streamingEngineDidStop()
        }
        
        StorageManager.appendToDiagnosticsLog("[LIVE] Apple Native stop completed")
    }

    // MARK: - Capture helpers
    func finalizeCapture() -> URL? {
        // Close handle to flush and return the current file
        guard let current = captureURL else { return nil }
        captureFile = nil
        
        // Ensure the file is properly closed and flushed
        do {
            // Try to get file size to verify it's written
            let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            StorageManager.appendToDiagnosticsLog("[LIVE] Finalized capture: \(current.lastPathComponent), size: \(fileSize) bytes")
            
            return current
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] finalize failed: \(error.localizedDescription)")
            return current
        }
    }

    private func attachObservers() {
#if os(iOS)
        detachObservers()
        routeChangeObserver = notificationCenter.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
        interruptionObserver = notificationCenter.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
        mediaResetObserver = notificationCenter.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.restartStreaming() }
        }
#endif
    }

    private func detachObservers() {
#if os(iOS)
        if let token = routeChangeObserver {
            notificationCenter.removeObserver(token)
            routeChangeObserver = nil
        }
        if let token = interruptionObserver {
            notificationCenter.removeObserver(token)
            interruptionObserver = nil
        }
        if let token = mediaResetObserver {
            notificationCenter.removeObserver(token)
            mediaResetObserver = nil
        }
#endif
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override:
            Task { await restartStreaming() }
        default:
            break
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            performStop(notifyDelegate: false)
        case .ended:
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? true
            if shouldResume {
                Task { await restartStreaming() }
            }
        @unknown default:
            break
        }
    }

    private func restartStreaming() async {
        let locale = activeLocaleIdentifier
        performStop(notifyDelegate: false)
        guard let delegate else { return }
        do {
            try await start(localeIdentifier: locale)
        } catch {
            delegate.streamingEngine(didError: error)
        }
    }
}
#else
@MainActor
final class AppleStreamingEngine: StreamingEngine {
    weak var delegate: StreamingEngineDelegate?
    func start(localeIdentifier: String?) async throws { throw NSError(domain: "Streaming", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech not available on this platform"]) }
    func stop() {}
}
#endif
