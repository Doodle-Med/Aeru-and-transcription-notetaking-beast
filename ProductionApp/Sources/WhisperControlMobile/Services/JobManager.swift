import Foundation
import Combine

@MainActor
class JobManager: ObservableObject {
    @Published private(set) var jobs: [TranscriptionJob] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var currentJob: TranscriptionJob?
    @Published var isBusyOverlay = false

    private let jobStore: JobStore
    private let settings: AppSettings
    private let modelManager: ModelDownloadManager
    private var processingTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(jobStore: JobStore, settings: AppSettings, modelManager: ModelDownloadManager) {
        self.jobStore = jobStore
        self.settings = settings
        self.modelManager = modelManager

        StorageManager.createDirectoriesIfNeeded()

        // Mirror jobs from store so the UI updates immediately
        jobStore.$jobs
            .receive(on: DispatchQueue.main)
            .assign(to: &self.$jobs)

        // Initialize with current store value
        jobs = jobStore.jobs
        purgeOrphanedJobs()

        // Don't start processing immediately on startup to avoid crashes
        // if jobs.contains(where: { $0.status == .queued }) {
        //     startProcessing(reason: "initial-load")
        // }
    }

    @discardableResult
    func addJob(audioURL: URL, filename: String) async -> TranscriptionJob? {
        // keep UI responsive; no blocking overlay here
        StorageManager.cleanupRecordings(olderThan: 60 * 60 * 24 * 7)
        StorageManager.createDirectoriesIfNeeded()

        // Handle security scoped resources properly
        StorageManager.logSystemEvent("Audio File Import", details: "Starting import for: \(filename)")
        let hasAccess = audioURL.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("Audio File Import", details: "Security scoped access: \(hasAccess)")
        
        if !hasAccess {
            StorageManager.logSystemEvent("Audio File Import", details: "Security scoped access failed, attempting direct access")
            print("WARNING: Failed to access security scoped resource for audio file: \(filename)")
        }

            // Use original filename (sanitization was removed to simplify)
            let sanitizedFilename = filename
            StorageManager.logSystemEvent("Audio File Import", details: "Using filename: \(sanitizedFilename)")

        // Perform file I/O off the main actor
        let targetURL = StorageManager.makeRecordingURL(filename: sanitizedFilename)
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        if FileManager.default.fileExists(atPath: targetURL.path) {
                            try FileManager.default.removeItem(at: targetURL)
                        }
                        
                        // Try multiple approaches for file copying
                        do {
                            try FileManager.default.copyItem(at: audioURL, to: targetURL)
                            StorageManager.logSystemEvent("Audio File Import", details: "Direct copy successful")
                        } catch {
                            // Fallback: try reading data and writing
                            StorageManager.logSystemEvent("Audio File Import", details: "Direct copy failed, trying data approach: \(error.localizedDescription)")
                            let data = try Data(contentsOf: audioURL)
                            try data.write(to: targetURL)
                            StorageManager.logSystemEvent("Audio File Import", details: "Data approach successful")
                        }
                        
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } catch {
            StorageManager.logError(error, context: "Audio File Import")
            StorageManager.appendToDiagnosticsLog("Failed to stage recording: \(error.localizedDescription)")
            if hasAccess {
                audioURL.stopAccessingSecurityScopedResource()
            }
            return nil
        }
        
        // Release security scoped resource access
        if hasAccess {
            audioURL.stopAccessingSecurityScopedResource()
            StorageManager.logSystemEvent("Audio File Import", details: "Released security scoped access")
        }

        var job = TranscriptionJob(filename: sanitizedFilename, originalURL: targetURL)
        job.status = TranscriptionJob.Status.queued
        job.progress = 0.0
        job.stage = "preparing"
        jobs.append(job)
        jobStore.addJob(job)
        StorageManager.appendToDiagnosticsLog("Job queued for \(filename)")

        let prepared: PreparedAudioFile
        do {
            prepared = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PreparedAudioFile, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let p = try AudioProcessing.prepareForTranscription(originalURL: targetURL)
                        cont.resume(returning: p)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            job.originalURL = prepared.url
            job.duration = prepared.duration
            job.sourceURL = targetURL
            job.stage = "queued"
            updateJob(job)
            jobStore.updateJob(job)
            StorageManager.appendToDiagnosticsLog("Job prepared for \(filename) duration=\(prepared.duration)")
        } catch {
            StorageManager.appendToDiagnosticsLog("Audio preparation failed: \(error.localizedDescription)")
            var failedJob = job
            failedJob.status = TranscriptionJob.Status.failed
            failedJob.error = "Audio preparation failed: \(error.localizedDescription)"
            failedJob.stage = "error"
            updateJob(failedJob)
            // no blocking overlay
            return nil
        }

        // Start processing if not already running
        if !isProcessing || processingTask?.isCancelled == true {
            startProcessing(reason: "auto-start")
        }

        StorageManager.appendToDiagnosticsLog("Job ready for processing: \(filename) id=\(job.id)")
        // no blocking overlay
        return job
    }

    func cancelJob(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }

        var job = jobs[index]
        job.status = .cancelled
        job.error = "Cancelled by user"
        job.stage = "cancelled"

        jobs[index] = job
        jobStore.updateJob(job)
        StorageManager.appendToDiagnosticsLog("Job cancelled: \(job.filename)")
    }

    func retryJob(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }

        var job = jobs[index]

        if !FileManager.default.fileExists(atPath: job.originalURL.path) {
            job.status = .failed
            job.error = "Original recording missing"
            job.stage = "error"
            jobs[index] = job
            jobStore.updateJob(job)
            StorageManager.appendToDiagnosticsLog("Retry aborted – missing file for \(job.filename)")
            return
        }

        job.status = .queued
        job.progress = 0.0
        job.error = nil
        job.stage = "queued"

        jobs[index] = job
        jobStore.updateJob(job)

        // Move to front of queue if not already running
        if currentJob?.id != id {
            jobs.remove(at: index)
            jobs.insert(job, at: 0)
        }
        StorageManager.appendToDiagnosticsLog("Job retried: \(job.filename)")
        ensureProcessing(reason: "retry")
    }

    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        jobStore.removeJob(id: id)
        StorageManager.appendToDiagnosticsLog("Job removed: \(id)")
    }

    func ensureProcessing(reason: String = "manual") {
        guard jobs.contains(where: { $0.status == .queued }) else { return }
        startProcessing(reason: reason)
    }

    private func purgeOrphanedJobs() {
        var removed: [UUID] = []
        jobs.removeAll { job in
            if !FileManager.default.fileExists(atPath: job.originalURL.path) {
                removed.append(job.id)
                return true
            }
            return false
        }
        removed.forEach { jobStore.removeJob(id: $0) }
        if !removed.isEmpty {
            StorageManager.appendToDiagnosticsLog("Purged \(removed.count) orphaned jobs")
        }
    }

    private func startProcessing(reason: String) {
        if let task = processingTask, !task.isCancelled {
            StorageManager.appendToDiagnosticsLog("[JOBMANAGER] startProcessing request ignored (reason=\(reason)) - already running")
            return
        }

        StorageManager.appendToDiagnosticsLog("[JOBMANAGER] startProcessing invoked (reason=\(reason))")
        processingTask?.cancel()
        isProcessing = true

        processingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.processNextJob()
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            await MainActor.run {
                self.isProcessing = false
                StorageManager.appendToDiagnosticsLog("[JOBMANAGER] processing task ended")
            }
        }
    }

    private func processNextJob() async {
        guard let job = jobs.first(where: { $0.status == .queued }) else {
            return
        }

        // no blocking overlay
        currentJob = job
        var updatedJob = job
        updatedJob.status = .transcribing
        updatedJob.stage = "transcribing"
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = updatedJob
        }
        jobStore.updateJob(updatedJob)
        StorageManager.appendToDiagnosticsLog("Job started: \(job.filename)")

        do {
            // Get the selected model
            guard let model = modelManager.models.first(where: { $0.id == settings.selectedModel }) else {
                throw NSError(domain: "JobManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
            }

            // Ensure model is downloaded
            if !model.isDownloaded {
                try await modelManager.downloadModel(model)
            }

            guard let modelPath = modelManager.getLocalModelPath(for: model) else {
                throw NSError(domain: "JobManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not found locally"])
            }

            let engineResolution = resolveEngine(for: model)
            let context = EngineContext(
                modelDirectory: modelPath,
                preferredTask: settings.preferredTask,
                apiKey: engineResolution.remoteAPIKey
            )

            let durationEstimate = job.duration ?? AudioProcessing.duration(of: job.originalURL)

            let transcriptionSettings = TranscriptionSettings(
                modelPath: modelPath,
                language: settings.autoLanguageDetect ? nil : "en",
                translate: settings.translate,
                temperature: settings.temperature > 0 ? Float(settings.temperature) : nil,
                beamSize: settings.beamSize > 0 ? settings.beamSize : nil,
                bestOf: settings.bestOf > 0 ? settings.bestOf : nil,
                suppressRegex: settings.suppressRegex.isEmpty ? nil : settings.suppressRegex,
                initialPrompt: settings.initialPrompt.isEmpty ? nil : settings.initialPrompt,
                vad: settings.vadEnabled,
                diarize: settings.diarizeEnabled,
                durationEstimate: durationEstimate,
                preferredTask: settings.preferredTask,
                preserveTimestamps: settings.showTimestamps
            )

            // Perform transcription with fallback if enabled
            let result = try await performTranscription(
                preferred: engineResolution.type,
                context: context,
                settings: transcriptionSettings,
                audioURL: job.originalURL,
                allowFallback: engineResolution.allowFallback,
                progress: { progress in
                    Task { @MainActor in
                        updatedJob.progress = max(updatedJob.progress, min(progress, 0.95))
                        updatedJob.stage = self.stageName(for: engineResolution.type)
                        if let index = self.jobs.firstIndex(where: { $0.id == updatedJob.id }) {
                            self.jobs[index] = updatedJob
                        }
                        self.jobStore.updateJob(updatedJob)
                    }
                },
                stageUpdate: { stage in
                    Task { @MainActor in
                        updatedJob.stage = stage
                        if let index = self.jobs.firstIndex(where: { $0.id == updatedJob.id }) {
                            self.jobs[index] = updatedJob
                        }
                        self.jobStore.updateJob(updatedJob)
                    }
                }
            )

            updatedJob.status = .completed
            updatedJob.progress = 1.0
            updatedJob.result = result
            updatedJob.stage = "completed"
            if let index = jobs.firstIndex(where: { $0.id == updatedJob.id }) {
                jobs[index] = updatedJob
            }
            jobStore.updateJob(updatedJob)
            StorageManager.appendToDiagnosticsLog("Job completed: \(job.filename)")
            AnalyticsTracker.shared.record(.jobCompleted(modelID: model.id, duration: result.duration))
            
        // Index in RAG system (off main actor)
        Task.detached(priority: .utility) { [job = updatedJob] in
            await self.indexJobInRAG(job)
        }

        } catch {
            updatedJob.status = .failed
            updatedJob.error = error.localizedDescription
            updatedJob.stage = "error"
            if let index = jobs.firstIndex(where: { $0.id == updatedJob.id }) {
                jobs[index] = updatedJob
            }
            jobStore.updateJob(updatedJob)
            StorageManager.appendToDiagnosticsLog("Job failed: \(error.localizedDescription)")
            AnalyticsTracker.shared.record(.jobFailed(modelID: settings.selectedModel, reason: error.localizedDescription))
        }

        currentJob = nil
        // no blocking overlay
    }

    private func updateJob(_ job: TranscriptionJob) {
        // Update the local jobs array first to trigger immediate UI updates
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        }
        // Also update the store for persistence
        jobStore.updateJob(job)
    }

    // MARK: - Filename Generation
    
    static func generateSimpleFilename(backend: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "\(timestamp)_\(backend)"
    }
    
    // MARK: - Live: add a completed item directly (no re-transcribe)
    @discardableResult
    func addCompletedLiveItem(audioURL: URL, displayFilename: String, text: String) async -> TranscriptionJob? {
        StorageManager.createDirectoriesIfNeeded()

        // Calculate duration from the ORIGINAL live file before any copying
        let durationOpt = AudioProcessing.duration(of: audioURL)
        let duration = durationOpt ?? 0
        StorageManager.appendToDiagnosticsLog("[LIVE] Calculated duration from original live file: \(String(format: "%.2f", duration))s")
        
        // Stage audio into library
        let targetURL = StorageManager.makeRecordingURL(filename: displayFilename)
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: audioURL, to: targetURL)
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] failed to finalize completed item: \(error.localizedDescription)")
            return nil
        }

        var job = TranscriptionJob(filename: displayFilename, originalURL: targetURL)
        job.status = .completed
        job.progress = 1.0
        job.stage = "completed"
        job.duration = durationOpt
        
        // Create proper segments for Apple Native (split by sentences/words for better structure)
        let segments = createSegmentsFromText(text, duration: duration)
        job.result = TranscriptionResult(text: text, segments: segments, language: nil, duration: duration)

        jobs.append(job)
        jobStore.addJob(job)
        StorageManager.appendToDiagnosticsLog("[LIVE] completed item added: \(displayFilename) dur=\(String(format: "%.2f", duration))s with \(segments.count) segments")
        
        // Create export files (txt, json, vtt, srt) like CoreML does
        await createExportFiles(for: job)
        
        // Index in RAG system (off main actor)
        Task.detached(priority: .utility) { [job] in
            await self.indexJobInRAG(job)
        }
        
        return job
    }
    
    // Create segments from Apple Native text (split by sentences for better structure)
    private func createSegmentsFromText(_ text: String, duration: TimeInterval) -> [TranscriptionSegment] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        if sentences.isEmpty {
            // Fallback: single segment
            return [TranscriptionSegment(start: 0, end: duration, text: text)]
        }
        
        var segments: [TranscriptionSegment] = []
        let segmentDuration = duration / Double(sentences.count)
        
        for (index, sentence) in sentences.enumerated() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let start = Double(index) * segmentDuration
                let end = min(start + segmentDuration, duration)
                segments.append(TranscriptionSegment(start: start, end: end, text: trimmed))
            }
        }
        
        return segments.isEmpty ? [TranscriptionSegment(start: 0, end: duration, text: text)] : segments
    }
    
    // Create export files (txt, json, vtt, srt) for the job
    private func createExportFiles(for job: TranscriptionJob) async {
        guard let result = job.result else { return }
        
        let baseName = job.filename.replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: ".").first ?? "transcript"
        
        let exportService = ExportService()
        
        // Create txt file
        do {
            let txtPayload = try exportService.export(result: result, format: .text, filename: baseName)
            let txtURL = StorageManager.makeRecordingURL(filename: "\(baseName).txt")
            try txtPayload.data.write(to: txtURL)
            StorageManager.appendToDiagnosticsLog("[LIVE] Created txt export: \(txtURL.lastPathComponent)")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to create txt export: \(error.localizedDescription)")
        }
        
        // Create json file
        do {
            let jsonPayload = try exportService.export(result: result, format: .json, filename: baseName)
            let jsonURL = StorageManager.makeRecordingURL(filename: "\(baseName).json")
            try jsonPayload.data.write(to: jsonURL)
            StorageManager.appendToDiagnosticsLog("[LIVE] Created json export: \(jsonURL.lastPathComponent)")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to create json export: \(error.localizedDescription)")
        }
        
        // Create srt file
        do {
            let srtPayload = try exportService.export(result: result, format: .srt, filename: baseName)
            let srtURL = StorageManager.makeRecordingURL(filename: "\(baseName).srt")
            try srtPayload.data.write(to: srtURL)
            StorageManager.appendToDiagnosticsLog("[LIVE] Created srt export: \(srtURL.lastPathComponent)")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to create srt export: \(error.localizedDescription)")
        }
        
        // Create vtt file
        do {
            let vttPayload = try exportService.export(result: result, format: .vtt, filename: baseName)
            let vttURL = StorageManager.makeRecordingURL(filename: "\(baseName).vtt")
            try vttPayload.data.write(to: vttURL)
            StorageManager.appendToDiagnosticsLog("[LIVE] Created vtt export: \(vttURL.lastPathComponent)")
        } catch {
            StorageManager.appendToDiagnosticsLog("[LIVE] Failed to create vtt export: \(error.localizedDescription)")
        }
    }
    
    func addCompletedJob(_ job: TranscriptionJob) {
        jobs.append(job)
        jobStore.addJob(job)
        
        // Index in RAG system
        Task {
            await indexJobInRAG(job)
        }
    }
    
    private func indexJobInRAG(_ job: TranscriptionJob) async {
        guard let result = job.result else { return }
        
        let metadata: [String: Any] = [
            "filename": job.filename,
            "duration": job.duration ?? 0,
            "timestamp": job.createdAt,
            "jobId": job.id.uuidString
        ]
        
        await LocalRAGService.shared.indexTranscript(result.text, metadata: metadata)
        
        // Use new AeruRAGModel for transcript indexing
        StorageManager.logSystemEvent("RAG Indexing", details: "Starting indexing for job: \(job.filename)")
        let ragModel = AeruRAGModel(collectionName: "whisper_transcripts")
        await ragModel.indexTranscriptionJob(job)
        StorageManager.logSystemEvent("RAG Indexing", details: "Completed indexing for job: \(job.filename)")
    }

    private func performTranscription(
        preferred: TranscriptionEngineType,
        context: EngineContext,
        settings: TranscriptionSettings,
        audioURL: URL,
        allowFallback: Bool,
        progress: @escaping (Double) -> Void,
        stageUpdate: @escaping (String) -> Void
    ) async throws -> TranscriptionResult {
        stageUpdate(stageName(for: preferred))
        do {
            return try await transcribe(using: preferred, context: context, settings: settings, audioURL: audioURL, progress: progress)
        } catch let error {
            guard allowFallback, preferred != .local else {
                throw error
            }

            StorageManager.appendToDiagnosticsLog("Cloud transcription failed (\(preferred)); falling back: \(error.localizedDescription)")
            AnalyticsTracker.shared.record(.cloudFallback(provider: providerName(for: preferred)))
            stageUpdate("fallback")
            let fallbackContext = EngineContext(modelDirectory: context.modelDirectory, preferredTask: context.preferredTask, apiKey: nil)
            return try await transcribe(using: .local, context: fallbackContext, settings: settings, audioURL: audioURL, progress: progress)
        }
    }

    private func transcribe(
        using type: TranscriptionEngineType,
        context: EngineContext,
        settings: TranscriptionSettings,
        audioURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        let engine = try await TranscriptionEngineFactory.createEngine(type: type, context: context)
        engine.progressHandler = progress
        return try await engine.transcribe(audioURL: audioURL, settings: settings)
    }

    private func resolveEngine(for model: WhisperModel) -> (type: TranscriptionEngineType, remoteAPIKey: String?, allowFallback: Bool) {
        if settings.offlineMode {
            return (.local, nil, false)
        }

        switch settings.cloudProvider {
        case "openai":
            guard !settings.openAIAPIKey.isEmpty else {
                return (.local, nil, false)
            }
            return (.openai, settings.openAIAPIKey, settings.enableCloudFallback)
        case "gemini":
            guard !settings.geminiAPIKey.isEmpty else {
                return (.local, nil, false)
            }
            return (.gemini, settings.geminiAPIKey, settings.enableCloudFallback)
        default:
            return (.local, nil, false)
        }
    }

    private func stageName(for type: TranscriptionEngineType) -> String {
        switch type {
        case .local: return "local"
        case .openai: return "cloud-openai"
        case .gemini: return "cloud-gemini"
        }
    }

    private func providerName(for type: TranscriptionEngineType) -> String {
        switch type {
        case .local: return "Local"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    deinit {
        processingTask?.cancel()
    }
}

// MARK: - Live Save Helper
@MainActor
enum LiveSaveHelper {
    static func saveFinalTranscription(text: String, audioURL: URL?) async {
        let safeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeText.isEmpty || audioURL != nil else {
            NotifyToastManager.shared.show("Nothing to save", icon: "exclamationmark.triangle", style: .warning)
            StorageManager.appendToDiagnosticsLog("[LIVE] save ignored (empty)")
            return
        }

        var savedParts: [String] = []
        if !safeText.isEmpty {
            let filename = "Live-\(Date().ISO8601Format()).txt"
            let url = StorageManager.makeRecordingURL(filename: filename)
            do {
                try safeText.data(using: .utf8)?.write(to: url)
                savedParts.append("text")
                StorageManager.appendToDiagnosticsLog("[LIVE] saved text to \(url.lastPathComponent)")
            } catch {
                StorageManager.appendToDiagnosticsLog("[LIVE] failed to save text: \(error.localizedDescription)")
            }
        }

        if let audio = audioURL {
            let dest = StorageManager.makeRecordingURL(filename: "Live-\(Date().ISO8601Format()).wav")
            do {
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: audio, to: dest)
                savedParts.append("audio")
                StorageManager.appendToDiagnosticsLog("[LIVE] saved audio to \(dest.lastPathComponent)")
            } catch {
                StorageManager.appendToDiagnosticsLog("[LIVE] failed to save audio: \(error.localizedDescription)")
            }
        }

        if !savedParts.isEmpty {
            NotifyToastManager.shared.show("Saved live \(savedParts.joined(separator: ", "))", icon: "tray.and.arrow.down", style: .success)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Sanitizes filename to prevent file system issues with special characters and spaces
    private static func sanitizeFilename(_ filename: String) -> String {
        // Replace problematic characters with safe alternatives
        let sanitized = filename
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "@", with: "at")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure filename is not empty and has a reasonable length
        let finalFilename = sanitized.isEmpty ? "audio_file" : String(sanitized.prefix(100))
        
        // Add back the file extension if it was removed
        if let originalExtension = filename.components(separatedBy: ".").last,
           !originalExtension.isEmpty && originalExtension.count <= 10 {
            return "\(finalFilename).\(originalExtension)"
        }
        
        return finalFilename
    }
}
