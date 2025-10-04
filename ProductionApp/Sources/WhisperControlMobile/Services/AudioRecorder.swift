import Foundation
import AVFoundation
import Combine
#if canImport(AVAudioApplication)
import AVAudioApplication
#endif

@MainActor
class AudioRecorder: ObservableObject {
    enum AudioRecorderError: Error {
        case formatCreationFailed
        case converterCreationFailed
    }

    enum RecordingState: Equatable {
        case idle
        case recording
        case stopping
        case error(Error)
        
        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording), (.stopping, .stopping):
                return true
            case (.error, .error):
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var duration: TimeInterval = 0.0
    @Published private(set) var outputURL: URL?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var startTime: Date?
	private var tapInstalled: Bool = false
    private let waveformSubject = PassthroughSubject<Double, Never>()
    var waveformPublisher: AnyPublisher<Double, Never> {
        waveformSubject.eraseToAnyPublisher()
    }

    init() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    print("Microphone permission denied")
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    print("Microphone permission denied")
                }
            }
        }
    }

    func startRecording(allowBackground: Bool = false) async throws {
        guard state == .idle else { return }

        let audioSession = AVAudioSession.sharedInstance()

        // Standardized session: optionally enable Apple's voice processing
        let voiceProcessingEnabled = UserDefaults.standard.bool(forKey: "voiceProcessingEnabled")
        #if targetEnvironment(simulator)
        if voiceProcessingEnabled {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat)
        } else {
            try audioSession.setCategory(.record, mode: .measurement)
        }
        #else
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if allowBackground { options.insert(.mixWithOthers) }
        if voiceProcessingEnabled {
            if #available(iOS 15.0, *) {
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            } else {
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            }
        } else {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: options)
        }
        #endif
        try? audioSession.setPreferredSampleRate(44100)
        try? audioSession.setPreferredIOBufferDuration(0.02)
        if audioSession.isInputAvailable {
            try? audioSession.setPreferredInputNumberOfChannels(1)
        }
        try audioSession.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        // We will write in the hardware-provided format to avoid converters in simulator
        let fileFormat = inputFormat

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording-\(UUID().uuidString).wav")
        let audioFile = try AVAudioFile(forWriting: fileURL, settings: fileFormat.settings)

        let bufferCapacity: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferCapacity, format: inputFormat) { [weak self] buffer, _ in
			guard let self else { return }
            do {
                let peak = self.peakLevel(from: buffer)
				Task { @MainActor in
					self.waveformSubject.send(peak)
				}
                try audioFile.write(from: buffer)
			} catch {
				print("Error writing audio: \(error)")
			}
		}
		self.tapInstalled = true

        try engine.start()
        self.audioEngine = engine
        self.audioFile = audioFile
        self.outputURL = fileURL
        self.startTime = Date()
        self.state = .recording

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.duration = Date().timeIntervalSince(startTime)
        }
    }

    func stopRecording() async throws -> URL? {
        guard state == .recording else { return outputURL }

        state = .stopping

        timer?.invalidate()
        timer = nil

        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil

        if #available(iOS 18.0, *) {
            audioFile?.close()
        }
		audioFile = nil

		// Deactivate audio session to avoid conflicts with subsequent playback/transcription
		#if os(iOS)
		try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
		#endif

        state = .idle
        duration = 0.0

        return outputURL
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil

        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil

        if #available(iOS 18.0, *) {
            audioFile?.close()
        }
		audioFile = nil

		// Deactivate audio session and clean up
		#if os(iOS)
		try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
		#endif

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }

        state = .idle
        duration = 0.0
        outputURL = nil
    }

    deinit {
        // Note: Cannot access @Published state from deinit due to actor isolation
        // The recording will be cleaned up when the object is deallocated
    }

    private func peakLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return 0.0 }

        let samples = channelData[0]
        var maxSample: Float = 0
        for i in 0..<frameLength {
            maxSample = max(maxSample, fabsf(samples[i]))
        }
        return Double(maxSample)
    }
}
