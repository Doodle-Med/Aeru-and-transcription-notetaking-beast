import Foundation
import Combine
#if canImport(ReplayKit)
import ReplayKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
final class ReplayKitCaptureService: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var outputURL: URL?
    @Published private(set) var isActive: Bool = false

#if canImport(ReplayKit) && canImport(AVFoundation)
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted: Bool = false
    private var isStopping: Bool = false
    private var lastStopAt: Date = .distantPast
    private var stopObserver: NSObjectProtocol?

    func start() async throws {
#if targetEnvironment(simulator)
        throw NSError(domain: "ReplayKit", code: -20, userInfo: [NSLocalizedDescriptionKey: "ReplayKit capture is not supported on the iOS Simulator. Please run on a physical device."])
#else
        guard !isRecording else { 
            print("[ReplayKit] Already recording, ignoring start request")
            return 
        }
        
        // Prevent rapid start/stop cycles
        guard !isStopping else {
            print("[ReplayKit] Still stopping from previous session, ignoring start request")
            return
        }
        
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw NSError(domain: "ReplayKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "ReplayKit not available"])
        }
        
        // If a previous session is still active in ReplayKit, force stop it first
        if recorder.isRecording {
            print("[ReplayKit] Previous session still active, force stopping first")
            await forceStop()
            // Wait a moment for cleanup
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
#endif

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        let fileName = "ReplayKit-\(timestamp)-\(UUID().uuidString).m4a"
        let url = StorageManager.makeRecordingURL(filename: fileName)

        // Prepare writer (AAC 44.1kHz mono)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ]
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioIn.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioIn) else {
            throw NSError(domain: "ReplayKit", code: -11, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input"]) 
        }
        writer.add(audioIn)

        self.assetWriter = writer
        self.audioInput = audioIn
        self.sessionStarted = false
        self.outputURL = url

        // If a previous session is still active in ReplayKit, force stop it first
        let activeRecorder = RPScreenRecorder.shared()
        if activeRecorder.isRecording {
            await _ = stop()
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            activeRecorder.startCapture(handler: { [weak self] (sample: CMSampleBuffer, type: RPSampleBufferType, error: Error?) in
                guard let self else { return }
                if let error { print("[ReplayKit] capture error: \(error.localizedDescription)"); return }
                guard type == .audioApp || type == .audioMic else { return }
                guard let writer = self.assetWriter, let audioIn = self.audioInput else { return }

                if !self.sessionStarted {
                    self.sessionStarted = true
                    writer.startWriting()
                    let startTime = CMSampleBufferGetPresentationTimeStamp(sample)
                    writer.startSession(atSourceTime: startTime)
                    Task { @MainActor in
                        self.isRecording = true
                        self.isActive = true
                        CaptureStatusCenter.shared.isReplayKitActive = true
                    }
                }

                if audioIn.isReadyForMoreMediaData {
                    _ = audioIn.append(sample)
                }
            }, completionHandler: { (error: Error?) in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }

        // Listen for global force stop
        if stopObserver == nil {
            stopObserver = NotificationCenter.default.addObserver(forName: CaptureStatusCenter.forceStopReplayKitNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Debounce repeated stop requests (UI or system churn)
                let now = Date()
                if now.timeIntervalSince(self.lastStopAt) < 0.8 || self.isStopping {
                    return
                }
                self.lastStopAt = now
                Task { await self.forceStop() }
            }
        }
    }

    func stop() async -> URL? {
        guard !isStopping else { return nil }
        isStopping = true
        let writer = self.assetWriter
        let recorder = RPScreenRecorder.shared()

        // Stop capture if active
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            recorder.stopCapture { error in
                if let error { print("[ReplayKit] stop error: \(error.localizedDescription)") }
                cont.resume()
            }
        }

        // Finalize writer safely
        if let writer = writer {
            switch writer.status {
            case .writing:
                audioInput?.markAsFinished()
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    writer.finishWriting { cont.resume() }
                }
            case .unknown, .failed, .cancelled, .completed:
                writer.cancelWriting()
            @unknown default:
                writer.cancelWriting()
            }
        }

        self.isRecording = false
        self.isActive = false
        CaptureStatusCenter.shared.isReplayKitActive = false
        let url = self.outputURL
        self.assetWriter = nil
        self.audioInput = nil
        self.sessionStarted = false
        self.outputURL = nil
        isStopping = false
        return url
    }

    func forceStop() async {
        if isStopping { return }
        isStopping = true
        let writer = self.assetWriter
        let recorder = RPScreenRecorder.shared()
        if recorder.isRecording {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                recorder.stopCapture { _ in cont.resume() }
            }
        }

        if let writer = writer {
            switch writer.status {
            case .writing:
                audioInput?.markAsFinished()
                writer.cancelWriting()
            default:
                writer.cancelWriting()
            }
        }

        self.isRecording = false
        self.isActive = false
        CaptureStatusCenter.shared.isReplayKitActive = false
        self.assetWriter = nil
        self.audioInput = nil
        self.sessionStarted = false
        self.outputURL = nil
        isStopping = false
        print("[ReplayKit] forceStop completed.")
    }
#else
    func start() async throws { throw NSError(domain: "ReplayKit", code: -100, userInfo: [NSLocalizedDescriptionKey: "ReplayKit not available"]) }
    func stop() async -> URL? { nil }
    func forceStop() async {}
#endif
}


