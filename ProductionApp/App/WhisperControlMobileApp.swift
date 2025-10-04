import SwiftUI

@main
struct WhisperControlMobileApp: App {
    @StateObject private var jobStore = JobStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var modelManager = ModelDownloadManager()
    @StateObject private var jobManager: JobManager
    @StateObject private var liveTranscriptionManager = LiveTranscriptionManager()
    @StateObject private var audioPlaybackService = AudioPlaybackService()

    private var colorScheme: ColorScheme? {
        switch settings.darkMode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    init() {
        // Ensure captureNativeLiveAudio is set to true by default for AppleStreamingEngine
        if UserDefaults.standard.object(forKey: "captureNativeLiveAudio") == nil {
            UserDefaults.standard.set(true, forKey: "captureNativeLiveAudio")
        }
        
        let jobStore = JobStore()
        let settings = AppSettings()
        let modelManager = ModelDownloadManager()
        _jobManager = StateObject(wrappedValue: JobManager(
            jobStore: jobStore,
            settings: settings,
            modelManager: modelManager
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(jobStore)
                .environmentObject(settings)
                .environmentObject(modelManager)
                .environmentObject(jobManager)
                .environmentObject(liveTranscriptionManager)
                .environmentObject(audioPlaybackService)
                .preferredColorScheme(colorScheme)
        }
    }
}