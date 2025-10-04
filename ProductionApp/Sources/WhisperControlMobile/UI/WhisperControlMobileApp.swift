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
        case .auto:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    init() {
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
                .onChange(of: settings.darkMode) { newValue in
                    print("Dark mode changed to: \(newValue.rawValue)")
                    print("Color scheme will be: \(colorScheme?.description ?? "nil")")
                }
                .id("main-view-\(settings.darkMode.rawValue)")
                .onAppear {
                    if ProcessInfo.processInfo.environment["WCM_AUTOMATION"] == "1" {
                        Task { @MainActor in
                            AutomationDriver.shared.kickoff(
                                settings: settings,
                                modelManager: modelManager,
                                jobManager: jobManager
                            )
                        }
                    }
                }
        }
    }
}