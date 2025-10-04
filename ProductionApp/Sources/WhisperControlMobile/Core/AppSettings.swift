import Foundation
import Combine

enum DarkModeSetting: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    @Published var selectedModel: String { didSet { persist() } }
    @Published var temperature: Double { didSet { persist() } }
    @Published var beamSize: Int { didSet { persist() } }
    @Published var bestOf: Int { didSet { persist() } }
    @Published var translate: Bool { didSet { persist() } }
    @Published var suppressRegex: String { didSet { persist() } }
    @Published var initialPrompt: String { didSet { persist() } }
    @Published var cloudProvider: String { didSet { persist() } }
    @Published var openAIAPIKey: String { didSet { persist() } }
    @Published var geminiAPIKey: String { didSet { persist() } }
    @Published var enableCloudFallback: Bool { didSet { persist() } }
    @Published var vadEnabled: Bool { didSet { persist() } }
    @Published var diarizeEnabled: Bool { didSet { persist() } }
    @Published var autoLanguageDetect: Bool { didSet { persist() } }
    @Published var showTimestamps: Bool { didSet { persist() } }
    @Published var preferredTask: String { didSet { persist() } }
    @Published var countInEnabled: Bool { didSet { persist() } }
    @Published var countInSeconds: Int { didSet { persist() } }
    @Published var allowBackgroundRecording: Bool { didSet { persist() } }
    @Published var offlineMode: Bool { didSet { persist() } }
    @Published var liveTranscriptionBackend: LiveTranscriptionBackend { didSet { persist() } }
    @Published var darkMode: DarkModeSetting { didSet { persist() } }
    @Published var voiceProcessingEnabled: Bool { didSet { persist() } }
    @Published var captureNativeLiveAudio: Bool { didSet { persist() } }
    @Published var enableReplayKitBroadcast: Bool { didSet { persist() } }
    @Published var enableReplayKitInAppRecord: Bool { didSet { persist() } }

    init() {
        let defaults = UserDefaults.standard
        let defaultModelID = "openai-whisper-small-en-coreml"
        let storedModelID = defaults.string(forKey: Key.selectedModel.rawValue)
        let availableModelIDs = Set(WhisperModel.models.map { $0.id })
        if let storedModelID, availableModelIDs.contains(storedModelID) {
            self.selectedModel = storedModelID
        } else {
            self.selectedModel = defaultModelID
        }
        self.temperature = defaults.double(forKey: Key.temperature.rawValue)
        self.beamSize = defaults.value(forKey: Key.beamSize.rawValue) as? Int ?? 5
        self.bestOf = defaults.value(forKey: Key.bestOf.rawValue) as? Int ?? 5
        self.translate = defaults.bool(forKey: Key.translate.rawValue)
        self.suppressRegex = defaults.string(forKey: Key.suppressRegex.rawValue) ?? ""
        self.initialPrompt = defaults.string(forKey: Key.initialPrompt.rawValue) ?? ""
        self.cloudProvider = defaults.string(forKey: Key.cloudProvider.rawValue) ?? "openai"
        self.openAIAPIKey = defaults.string(forKey: Key.openAIAPIKey.rawValue) ?? ""
        self.geminiAPIKey = defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? ""
        self.enableCloudFallback = defaults.bool(forKey: Key.enableCloudFallback.rawValue)
        self.vadEnabled = defaults.bool(forKey: Key.vadEnabled.rawValue)
        self.diarizeEnabled = defaults.bool(forKey: Key.diarizeEnabled.rawValue)
        self.autoLanguageDetect = defaults.bool(forKey: Key.autoLanguageDetect.rawValue)
        self.showTimestamps = defaults.bool(forKey: Key.showTimestamps.rawValue)
        self.preferredTask = defaults.string(forKey: Key.preferredTask.rawValue) ?? "transcribe"
        self.offlineMode = defaults.bool(forKey: Key.offlineMode.rawValue)
        self.liveTranscriptionBackend = LiveTranscriptionBackend(rawValue: defaults.string(forKey: Key.liveTranscriptionBackend.rawValue) ?? "appleNative") ?? .appleNative
        self.darkMode = DarkModeSetting(rawValue: defaults.string(forKey: Key.darkMode.rawValue) ?? "auto") ?? .auto
        self.voiceProcessingEnabled = defaults.bool(forKey: Key.voiceProcessingEnabled.rawValue)
        self.captureNativeLiveAudio = defaults.object(forKey: Key.captureNativeLiveAudio.rawValue) != nil ? defaults.bool(forKey: Key.captureNativeLiveAudio.rawValue) : true
        if defaults.object(forKey: Key.enableReplayKitBroadcast.rawValue) == nil {
            defaults.set(false, forKey: Key.enableReplayKitBroadcast.rawValue)
        }
        if defaults.object(forKey: Key.enableReplayKitInAppRecord.rawValue) == nil {
            defaults.set(false, forKey: Key.enableReplayKitInAppRecord.rawValue)
        }
        self.enableReplayKitBroadcast = defaults.bool(forKey: Key.enableReplayKitBroadcast.rawValue)
        self.enableReplayKitInAppRecord = defaults.bool(forKey: Key.enableReplayKitInAppRecord.rawValue)
        if defaults.object(forKey: Key.countInEnabled.rawValue) == nil {
            defaults.set(true, forKey: Key.countInEnabled.rawValue)
        }
        self.countInEnabled = defaults.bool(forKey: Key.countInEnabled.rawValue)
        let storedCountIn = defaults.integer(forKey: Key.countInSeconds.rawValue)
        self.countInSeconds = storedCountIn > 0 ? storedCountIn : 3
        if defaults.object(forKey: Key.allowBackgroundRecording.rawValue) == nil {
            defaults.set(false, forKey: Key.allowBackgroundRecording.rawValue)
        }
        self.allowBackgroundRecording = defaults.bool(forKey: Key.allowBackgroundRecording.rawValue)
        
        // Ensure the simple key is also set for services after all properties are initialized
        UserDefaults.standard.set(self.captureNativeLiveAudio, forKey: "captureNativeLiveAudio")
        UserDefaults.standard.set(self.captureNativeLiveAudio, forKey: Key.captureNativeLiveAudio.rawValue)
    }

    // Reset to defaults
    func resetToDefaults() {
        selectedModel = "openai-whisper-small-en-coreml"
        temperature = 0.0
        beamSize = 5
        bestOf = 5
        translate = false
        suppressRegex = ""
        initialPrompt = ""
        cloudProvider = "openai"
        openAIAPIKey = ""
        geminiAPIKey = ""
        enableCloudFallback = false
        vadEnabled = false
        diarizeEnabled = false
        autoLanguageDetect = true
        showTimestamps = true
        preferredTask = "transcribe"
        countInEnabled = true
        countInSeconds = 3
        allowBackgroundRecording = false
        liveTranscriptionBackend = .appleNative
        darkMode = .auto
        voiceProcessingEnabled = false
        captureNativeLiveAudio = true
        enableReplayKitBroadcast = false
        enableReplayKitInAppRecord = false
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(selectedModel, forKey: Key.selectedModel.rawValue)
        defaults.set(temperature, forKey: Key.temperature.rawValue)
        defaults.set(beamSize, forKey: Key.beamSize.rawValue)
        defaults.set(bestOf, forKey: Key.bestOf.rawValue)
        defaults.set(translate, forKey: Key.translate.rawValue)
        defaults.set(suppressRegex, forKey: Key.suppressRegex.rawValue)
        defaults.set(initialPrompt, forKey: Key.initialPrompt.rawValue)
        defaults.set(cloudProvider, forKey: Key.cloudProvider.rawValue)
        defaults.set(openAIAPIKey, forKey: Key.openAIAPIKey.rawValue)
        defaults.set(geminiAPIKey, forKey: Key.geminiAPIKey.rawValue)
        defaults.set(enableCloudFallback, forKey: Key.enableCloudFallback.rawValue)
        defaults.set(vadEnabled, forKey: Key.vadEnabled.rawValue)
        defaults.set(diarizeEnabled, forKey: Key.diarizeEnabled.rawValue)
        defaults.set(autoLanguageDetect, forKey: Key.autoLanguageDetect.rawValue)
        defaults.set(showTimestamps, forKey: Key.showTimestamps.rawValue)
        defaults.set(preferredTask, forKey: Key.preferredTask.rawValue)
        defaults.set(offlineMode, forKey: Key.offlineMode.rawValue)
        defaults.set(liveTranscriptionBackend.rawValue, forKey: Key.liveTranscriptionBackend.rawValue)
        defaults.set(darkMode.rawValue, forKey: Key.darkMode.rawValue)
        defaults.set(voiceProcessingEnabled, forKey: Key.voiceProcessingEnabled.rawValue)
        defaults.set(captureNativeLiveAudio, forKey: Key.captureNativeLiveAudio.rawValue)
        defaults.set(enableReplayKitBroadcast, forKey: Key.enableReplayKitBroadcast.rawValue)
        defaults.set(enableReplayKitInAppRecord, forKey: Key.enableReplayKitInAppRecord.rawValue)
        defaults.set(countInEnabled, forKey: Key.countInEnabled.rawValue)
        defaults.set(countInSeconds, forKey: Key.countInSeconds.rawValue)
        defaults.set(allowBackgroundRecording, forKey: Key.allowBackgroundRecording.rawValue)
        // Mirror a subset to simple keys consumed by services
        UserDefaults.standard.set(voiceProcessingEnabled, forKey: "voiceProcessingEnabled")
        UserDefaults.standard.set(captureNativeLiveAudio, forKey: "captureNativeLiveAudio")
        UserDefaults.standard.set(enableReplayKitBroadcast, forKey: "enableReplayKitBroadcast")
        UserDefaults.standard.set(enableReplayKitInAppRecord, forKey: "enableReplayKitInAppRecord")
        UserDefaults.standard.set(showTimestamps, forKey: "showTimestamps")
    }

    private enum Key: String {
        case selectedModel
        case temperature
        case beamSize
        case bestOf
        case translate
        case suppressRegex
        case initialPrompt
        case cloudProvider
        case openAIAPIKey
        case geminiAPIKey
        case enableCloudFallback
        case vadEnabled
        case diarizeEnabled
        case autoLanguageDetect
        case showTimestamps
        case preferredTask
        case offlineMode
        case liveTranscriptionBackend
        case darkMode
        case voiceProcessingEnabled
        case captureNativeLiveAudio
        case enableReplayKitBroadcast
        case enableReplayKitInAppRecord
        case countInEnabled
        case countInSeconds
        case allowBackgroundRecording
    }
}
