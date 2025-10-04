import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

protocol LiveTranscriptionSessionDelegate: AnyObject {
    func liveSession(didUpdateETA secondsRemaining: TimeInterval)
    func liveSession(didEmitPartial segments: [TranscriptionSegment])
    func liveSessionDidComplete(final result: TranscriptionResult)
    func liveSession(didError error: Error)
}

@MainActor
final class LiveTranscriptionSession {
    struct Config {
        let windowSeconds: TimeInterval
        let hopSeconds: TimeInterval
        static let `default` = Config(windowSeconds: 12.0, hopSeconds: 3.0)
    }

    weak var delegate: LiveTranscriptionSessionDelegate?

    private let config: Config
    private let engineFactory: () -> TranscriptionEngine
    private let fileManager = FileManager.default

    // Rolling buffer store
    private var rollingBuffers: [AVAudioPCMBuffer] = []
    private var rollingDuration: TimeInterval = 0

    // Control
    private var workerTask: Task<Void, Never>?
    private var isRunning: Bool = false
    private var lastEmittedEndTime: TimeInterval = 0

    init(config: Config = .default, engineFactory: @escaping () -> TranscriptionEngine) {
        self.config = config
        self.engineFactory = engineFactory
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastEmittedEndTime = 0
    }

    func stop() {
        isRunning = false
        workerTask?.cancel()
        workerTask = nil
        rollingBuffers.removeAll()
        rollingDuration = 0
    }

    /// Feed normalized 16kHz mono buffers
    func ingest(buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        rollingBuffers.append(buffer)
        rollingDuration += duration(of: buffer)

        // Start worker if not running and we have at least one window worth
        if workerTask == nil, rollingDuration >= config.windowSeconds {
            workerTask = Task { [weak self] in
                await self?.processLoop()
            }
        }
    }

    private func processLoop() async {
        while isRunning {
            let seconds = min(config.windowSeconds, rollingDuration)
            if seconds > 0 {
                if let wavURL = try? buildWindowedWAV(seconds: seconds) {
                    do {
                        let engine = engineFactory()
                        let preserve = UserDefaults.standard.bool(forKey: "showTimestamps")
                        let settings = TranscriptionSettings(
                            modelPath: fileManager.temporaryDirectory,
                            language: nil,
                            translate: false,
                            temperature: 0.0,
                            beamSize: 1,
                            bestOf: 1,
                            suppressRegex: nil,
                            initialPrompt: nil,
                            vad: true,
                            diarize: false,
                            durationEstimate: seconds,
                            preferredTask: "transcribe",
                            preserveTimestamps: preserve
                        )
                        let result = try await engine.transcribe(audioURL: wavURL, settings: settings)
                        delegate?.liveSession(didEmitPartial: result.segments)
                        let eta = max(0, (rollingDuration - seconds) * 2.0)
                        delegate?.liveSession(didUpdateETA: eta)
                    } catch {
                        delegate?.liveSession(didError: error)
                    }
                }
            }
            // Wait hop interval before next window; do not mutate buffers (sliding window over tail)
            try? await Task.sleep(nanoseconds: UInt64(config.hopSeconds * 1_000_000_000))
        }
    }

    // MARK: - Audio utils

    private func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }

    // dropFront no longer needed; we keep a sliding window over the tail

    private func buildWindowedWAV(seconds: TimeInterval) throws -> URL {
        // Concatenate buffers from the tail until we reach 'seconds'
        var collected: [AVAudioPCMBuffer] = []
        var acc: TimeInterval = 0
        for buffer in rollingBuffers.reversed() {
            collected.insert(buffer, at: 0)
            acc += duration(of: buffer)
            if acc >= seconds { break }
        }
        guard let format = collected.first?.format else {
            throw NSError(domain: "LiveSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "No buffers"])
        }

        let tempDir = fileManager.temporaryDirectory
        let url = tempDir.appendingPathComponent("live-window-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        for b in collected {
            try file.write(from: b)
        }

        return url
    }
}
