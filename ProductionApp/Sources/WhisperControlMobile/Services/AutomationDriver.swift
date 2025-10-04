import Foundation
import Combine

#if DEBUG
@MainActor
final class AutomationDriver {
    static let shared = AutomationDriver()
    private var started = false

    func kickoff(settings: AppSettings, modelManager: ModelDownloadManager, jobManager: JobManager) {
        guard !started else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--auto-run") else { return }
        started = true

        let modelID = value(for: "--auto-model-id", in: arguments) ?? settings.selectedModel
        let inputName = value(for: "--auto-audio-filename", in: arguments) ?? "input.wav"
        let exportRaw = value(for: "--auto-export", in: arguments) ?? "srt"
        let provider = value(for: "--auto-provider", in: arguments)
        let batchRaw = value(for: "--auto-batch", in: arguments)
        let openAIKey = value(for: "--auto-openai-key", in: arguments)
        let geminiKey = value(for: "--auto-gemini-key", in: arguments)
        let recordSecondsRaw = value(for: "--auto-record-seconds", in: arguments)
        let shouldExit = arguments.contains("--auto-exit")

        Task { @MainActor in
            StorageManager.appendToDiagnosticsLog("[AUTO] starting")

            modelManager.refreshModelStatus()
            if let model = modelManager.models.first(where: { $0.id == modelID }), !model.isDownloaded {
                do {
                    try await modelManager.downloadModel(model)
                } catch {
                    StorageManager.appendToDiagnosticsLog("[AUTO] model download failed: \(error.localizedDescription)")
                    started = false
                    return
                }
            }

            await configureSettings(
                settings,
                selectedModel: modelID,
                provider: provider,
                openAIKey: openAIKey,
                geminiKey: geminiKey
            )

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? StorageManager.appSupportDirectory
            var observations: [UUID: URL] = [:]
            let exportFormat = ExportFormat(rawValue: exportRaw) ?? .srt
            let exportService = ExportService()

            if let secsRaw = recordSecondsRaw, let secs = Int(secsRaw), secs > 0 {
                StorageManager.appendToDiagnosticsLog("[AUTO] recording for \(secs)s")
                let recorder = AudioRecorder()
                do {
                    try await recorder.startRecording(allowBackground: false)
                    try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
                    let maybeURL = try await recorder.stopRecording()
                    guard let url = maybeURL else {
                        StorageManager.appendToDiagnosticsLog("[AUTO] recorder did not produce a file")
                        started = false
                        return
                    }
                    let name = url.lastPathComponent
                    if let job = await jobManager.addJob(audioURL: url, filename: name) {
                        observations[job.id] = documents.appendingPathComponent("output-\(job.id.uuidString).\(exportFormat.rawValue)")
                        StorageManager.appendToDiagnosticsLog("[AUTO] enqueued recorded file \(name)")
                    } else {
                        StorageManager.appendToDiagnosticsLog("[AUTO] failed to enqueue recorded file \(name)")
                    }
                } catch {
                    StorageManager.appendToDiagnosticsLog("[AUTO] recording failed: \(error.localizedDescription)")
                    started = false
                    return
                }
            } else {
                let filenames = makeBatch(from: batchRaw ?? inputName)
                for name in filenames {
                    let inputURL = documents.appendingPathComponent(name)
                    guard FileManager.default.fileExists(atPath: inputURL.path) else {
                        StorageManager.appendToDiagnosticsLog("[AUTO] missing input: \(inputURL.path)")
                        continue
                    }
                    StorageManager.appendToDiagnosticsLog("[AUTO] enqueuing job for \(name)")
                    guard let job = await jobManager.addJob(audioURL: inputURL, filename: name) else {
                        StorageManager.appendToDiagnosticsLog("[AUTO] failed to enqueue job for \(name)")
                        continue
                    }
                    observations[job.id] = documents.appendingPathComponent("output-\(job.id.uuidString).\(exportFormat.rawValue)")
                }
            }

            guard !observations.isEmpty else {
                StorageManager.appendToDiagnosticsLog("[AUTO] no jobs queued; aborting run")
                started = false
                return
            }

            jobManager.ensureProcessing(reason: "automation")

            for (jobID, outputURL) in observations {
                guard let finalJob = await waitForJobCompletion(id: jobID, jobManager: jobManager, timeout: 600) else {
                    StorageManager.appendToDiagnosticsLog("[AUTO] timeout waiting for job \(jobID.uuidString)")
                    continue
                }

                switch finalJob.status {
                case .completed:
                    guard let result = finalJob.result else {
                        StorageManager.appendToDiagnosticsLog("[AUTO] job \(jobID.uuidString) completed without result")
                        continue
                    }
                    do {
                        let payload = try exportService.export(result: result, format: exportFormat, filename: "output")
                        try payload.data.write(to: outputURL, options: .atomic)
                        StorageManager.appendToDiagnosticsLog("[AUTO] job \(jobID.uuidString) succeeded -> \(outputURL.lastPathComponent)")
                    } catch {
                        StorageManager.appendToDiagnosticsLog("[AUTO] job \(jobID.uuidString) export failed: \(error.localizedDescription)")
                    }
                case .failed:
                    let reason = finalJob.error ?? "unknown error"
                    StorageManager.appendToDiagnosticsLog("[AUTO] job \(jobID.uuidString) failed: \(reason)")
                default:
                    StorageManager.appendToDiagnosticsLog("[AUTO] job \(jobID.uuidString) ended with unexpected status \(finalJob.status.rawValue)")
                }
            }

            started = false
            if shouldExit {
                exit(0)
            }
        }
    }

    private func value(for key: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        return value.hasPrefix("--") ? nil : value
    }

    private func configureSettings(
        _ settings: AppSettings,
        selectedModel: String,
        provider: String?,
        openAIKey: String?,
        geminiKey: String?
    ) async {
        if settings.selectedModel != selectedModel {
            StorageManager.appendToDiagnosticsLog("[AUTO] switching selected model from \(settings.selectedModel) to \(selectedModel)")
            settings.selectedModel = selectedModel
        }

        guard let provider else { return }
        switch provider.lowercased() {
        case "openai":
            settings.cloudProvider = "openai"
            if let openAIKey, !openAIKey.isEmpty {
                settings.openAIAPIKey = openAIKey
                StorageManager.appendToDiagnosticsLog("[AUTO] configured OpenAI provider")
            }
        case "gemini":
            settings.cloudProvider = "gemini"
            if let geminiKey, !geminiKey.isEmpty {
                settings.geminiAPIKey = geminiKey
                StorageManager.appendToDiagnosticsLog("[AUTO] configured Gemini provider")
            }
        case "none":
            settings.cloudProvider = "none"
        default:
            StorageManager.appendToDiagnosticsLog("[AUTO] unknown provider \(provider); leaving settings unchanged")
        }
    }

    private func waitForJobCompletion(id: UUID, jobManager: JobManager, timeout: TimeInterval) async -> TranscriptionJob? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let timeoutTask = Task<TranscriptionJob?, Never> {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            StorageManager.appendToDiagnosticsLog("[AUTO] observer timed out after \(timeout)s")
            return nil
        }

        let stream = AsyncStream<[TranscriptionJob]> { continuation in
            let cancellable = jobManager.$jobs.sink { jobs in
                continuation.yield(jobs)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }

        for await snapshot in stream {
            guard let job = snapshot.first(where: { $0.id == id }) else { continue }

            if let data = try? encoder.encode(job),
               let json = String(data: data, encoding: .utf8) {
                StorageManager.appendToDiagnosticsLog("[AUTO] job update: \(json)")
            } else {
                StorageManager.appendToDiagnosticsLog("[AUTO] job update status=\(job.status.rawValue) stage=\(job.stage ?? "-") progress=\(job.progress)")
            }

            if job.status == .completed || job.status == .failed {
                timeoutTask.cancel()
                return job
            }

            if Task.isCancelled {
                timeoutTask.cancel()
                return nil
            }
        }

        let timeoutResult = await timeoutTask.value
        return timeoutResult
    }

    private func makeBatch(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
#endif
