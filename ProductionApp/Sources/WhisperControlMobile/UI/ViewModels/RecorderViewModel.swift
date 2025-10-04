import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    private weak var jobManager: JobManager?
    private weak var settings: AppSettings?
    private weak var automation: AutomationState?

    func bind(jobManager: JobManager, settings: AppSettings, automation: AutomationState) {
        self.jobManager = jobManager
        self.settings = settings
        self.automation = automation
    }

    func notifyPresented() {
        automation?.update(.recorderPresented)
    }

    func notifyDismissed() {
        automation?.update(.recorderDismissed)
    }

    func notifyRecordingStarted() {
        automation?.update(.recordingStarted)
    }

    func notifyRecordingStopped() {
        automation?.update(.recordingStopped)
    }

    func notifyJobQueued() {
        automation?.update(.jobQueued)
    }

    var liveTranscribeEnabled: Bool {
        settings?.liveTranscribeEnabled ?? false
    }
}
