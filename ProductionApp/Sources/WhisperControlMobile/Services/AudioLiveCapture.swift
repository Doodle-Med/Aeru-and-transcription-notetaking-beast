import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
import Combine

#if canImport(AVFoundation)
@MainActor
final class AudioLiveCapture: ObservableObject {
    struct Config {
        let sampleRate: Double
        let channels: AVAudioChannelCount
        static let `default` = Config(sampleRate: 16_000, channels: 1)
    }

    enum CaptureError: Error { case setupFailed, converterCreationFailed }

    private let config: Config
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private let notificationCenter = NotificationCenter.default

    private let bufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    var bufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> { bufferSubject.eraseToAnyPublisher() }

    init(config: Config = .default) {
        self.config = config
    }

    func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let voiceProcessingEnabled = UserDefaults.standard.bool(forKey: "voiceProcessingEnabled")
        // Use modern options: allowBluetoothHFP replaces deprecated allowBluetooth
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if #available(iOS 17.0, *) { options.insert(.allowBluetoothHFP) }
        #if targetEnvironment(simulator)
        if voiceProcessingEnabled {
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        } else {
            try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        try? session.setPreferredSampleRate(44100) // Use standard sample rate in simulator
        try? session.setPreferredIOBufferDuration(0.01) // Smaller buffer for lower latency
        #else
        if voiceProcessingEnabled {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        } else {
            try session.setCategory(.record, mode: .measurement, options: options)
        }
        try session.setPreferredSampleRate(config.sampleRate)
        try session.setPreferredIOBufferDuration(0.01) // Smaller buffer for lower latency
        #endif
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Validate and create a proper audio format for the simulator
        let rawInputFormat = inputNode.inputFormat(forBus: 0)
        let inputFormat: AVAudioFormat
        
        #if targetEnvironment(simulator)
        // Simulator workaround: create a standard format if input format is invalid
        if rawInputFormat.sampleRate == 0 || rawInputFormat.channelCount == 0 {
            inputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            print("[LIVE] Using fallback input format for simulator: 44.1kHz stereo")
        } else {
            inputFormat = rawInputFormat
        }
        #else
        inputFormat = rawInputFormat
        #endif
        
        self.inputFormat = inputFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: config.sampleRate,
            channels: config.channels,
            interleaved: false
        ) else {
            print("[LIVE] failed to create output format")
            throw CaptureError.setupFailed
        }
        self.outputFormat = outputFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("[LIVE] failed to create converter from format \(inputFormat) to \(outputFormat)")
            throw CaptureError.converterCreationFailed
        }
        self.converter = converter

        let bufferCapacity: AVAudioFrameCount = 4096
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferCapacity, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Compute an output capacity based on sample-rate ratio to avoid drift/over-alloc
            let inFrames = Int(buffer.frameLength)
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let estOut = Int(Double(inFrames) * ratio) + 256
            let outCapacity = AVAudioFrameCount(max(1024, min(8192, estOut)))
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return }

            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            var error: NSError?
            self.converter?.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                print("[LIVE] converter error: \(error.localizedDescription)")
                self.rebuildConverter()
                return
            }
            guard outputBuffer.frameLength > 0 else { return }

            AudioProcessing.normalize(outputBuffer)
            self.bufferSubject.send(outputBuffer)
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        attachObservers()
        print("[LIVE] capture started sr=\(config.sampleRate) channels=\(config.channels)")
    }

    func stop() {
        detachObservers()
        if let engine = audioEngine {
            if engine.inputNode.numberOfInputs > 0 {
                engine.inputNode.removeTap(onBus: 0)
            }
            engine.stop()
        }
        audioEngine = nil
        converter = nil
        inputFormat = nil
        outputFormat = nil
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    private func rebuildConverter() {
        guard let inputFormat, let outputFormat else { return }
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
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
        configurationObserver = notificationCenter.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.restartCapturePipeline()
            }
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
        if let token = configurationObserver {
            notificationCenter.removeObserver(token)
            configurationObserver = nil
        }
#endif
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override, .noSuitableRouteForCategory:
            rebuildConverter()
            if let engine = audioEngine, !engine.isRunning {
                try? engine.start()
            }
        default:
            break
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            rebuildConverter()
            try? audioEngine?.start()
        }
    }

    private func restartCapturePipeline() {
        stop()
        do {
            try start()
        } catch {
            print("[LIVE] failed to restart capture after audio reset: \(error.localizedDescription)")
        }
    }
}
#else
@MainActor
final class AudioLiveCapture: ObservableObject {
    struct Config { let sampleRate: Double; let channels: UInt32; static let `default` = Config(sampleRate: 16_000, channels: 1) }
    enum CaptureError: Error { case unsupported }
    var bufferPublisher: AnyPublisher<Never, Never> { Empty().eraseToAnyPublisher() }
    init(config: Config = .default) {}
    func start() throws { throw CaptureError.unsupported }
    func stop() {}
}
#endif
