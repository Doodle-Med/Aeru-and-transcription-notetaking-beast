import Combine
import Foundation

@MainActor
final class QueueViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []

    func bind(jobManager: JobManager, automation: AutomationState) {
        automation.update(.idle)

        jobManager.$jobs
            .sink { [automation] jobs in
                if jobs.contains(where: { $0.status == .transcribing || $0.status == .queued }) {
                    automation.update(.recordingStarted)
                }
                if jobs.contains(where: { $0.status == .completed }) {
                    automation.update(.jobCompleted)
                }
            }
            .store(in: &cancellables)
    }
}
