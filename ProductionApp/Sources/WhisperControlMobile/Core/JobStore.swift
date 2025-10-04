import Foundation
import Combine

@MainActor
class JobStore: ObservableObject {
    @Published private(set) var jobs: [TranscriptionJob] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let jobsFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) {
        if inMemory {
            jobsFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-test.json")
            try? FileManager.default.removeItem(at: jobsFileURL)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupport.appendingPathComponent("WhisperControlMobile")
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            jobsFileURL = appDirectory.appendingPathComponent("jobs.json")
        }

        loadJobs()
    }

    func addJob(_ job: TranscriptionJob) {
        jobs.append(job)
        saveJobs()
    }

    func updateJob(_ job: TranscriptionJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
            saveJobs()
        }
    }

    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        saveJobs()
    }

    func clearJobs() {
        jobs.removeAll()
        saveJobs()
    }

    private func saveJobs() {
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: jobsFileURL)
        } catch {
            print("Failed to save jobs: \(error)")
        }
    }

    private func loadJobs() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: jobsFileURL)
            jobs = try decoder.decode([TranscriptionJob].self, from: data)
        } catch {
            print("Failed to load jobs: \(error)")
            jobs = []
        }
    }

    // Computed properties for filtering
    var queuedJobs: [TranscriptionJob] {
        jobs.filter { $0.status == .queued }
    }

    var runningJobs: [TranscriptionJob] {
        jobs.filter { $0.status == .recording || $0.status == .transcribing }
    }

    var completedJobs: [TranscriptionJob] {
        jobs.filter { $0.status == .completed }
    }

    var failedJobs: [TranscriptionJob] {
        jobs.filter { $0.status == .failed }
    }
}
