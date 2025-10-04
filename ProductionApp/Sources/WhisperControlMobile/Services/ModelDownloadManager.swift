import Foundation
import Combine
import CryptoKit
import ZIPFoundation

@MainActor
protocol ModelDownloadManaging: ObservableObject {
    var models: [WhisperModel] { get set }
    var downloadProgress: [String: Double] { get }
    var downloadError: [String: String] { get }

    func refreshModelStatus()
    func downloadModel(_ model: WhisperModel) async throws
    func deleteModel(_ model: WhisperModel) throws
    func getLocalModelPath(for model: WhisperModel) -> URL?
}

@MainActor
class ModelDownloadManager: ObservableObject, ModelDownloadManaging {
    @Published var models: [WhisperModel] = WhisperModel.models
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadError: [String: String] = [:]

    private let modelsDirectory: URL
    private let manifestStore: ModelManifestStore
    private let whisperKitVersion: String?
    private let session: URLSession

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("WhisperControlMobile")
        modelsDirectory = appDirectory.appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        manifestStore = ModelManifestStore(directory: modelsDirectory)
        whisperKitVersion = Bundle.main.object(forInfoDictionaryKey: "WhisperKitVersion") as? String

        let configuration = URLSessionConfiguration.default
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration)

        // Ensure bundled models are marked installed
        primeBundledModelState()
        refreshModelStatus()
    }

    private func primeBundledModelState() {
        models = models.map { model in
            guard let bundleURL = bundledResourceURL(for: model) else { return model }
            var bundled = model
            bundled.isDownloaded = true
            manifestStore.upsertEntry(
                for: bundled,
                checksumOverride: bundleChecksum(for: bundleURL),
                whisperKitVersion: whisperKitVersion
            )
            return bundled
        }
    }

    func downloadModel(_ model: WhisperModel) async throws {
        if model.isBundled || model.downloadURL == nil {
            StorageManager.appendToDiagnosticsLog("Model \(model.id) is bundled; skipping download")
            updateModelDownloadedState(modelID: model.id, downloaded: true)
            return
        }

        guard !model.isDownloaded else { return }
        guard let downloadURL = model.downloadURL, let remoteURL = URL(string: downloadURL) else {
            throw NSError(domain: "ModelDownloadManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "Model \(model.displayName) is bundled with the app and does not need downloading."])
        }

        let destination = modelsDirectory.appendingPathComponent(model.name)
        let downloadTask = DownloadTask(sourceURL: remoteURL, destination: destination, session: session)

        downloadProgress[model.id] = 0.0
        downloadError[model.id] = nil

        do {
            try await downloadTask.execute(progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[model.id] = progress
                }
            }, stateHandler: { state in
                StorageManager.appendToDiagnosticsLog("Model download \(model.id) state: \(state)")
            })

            try await verifyChecksumIfNeeded(for: model, at: destination)

            if model.requiresUnzip {
                try await unpackArchive(at: destination)
            }

            updateModelDownloadedState(modelID: model.id, downloaded: true)
            manifestStore.upsertEntry(for: model, whisperKitVersion: whisperKitVersion)
            downloadProgress[model.id] = nil
            NotifyToastManager.shared.show("Model \(model.displayName) ready", icon: "checkmark.circle", style: .success)
            AnalyticsTracker.shared.record(.modelDownloaded(modelID: model.id))
        } catch {
            downloadError[model.id] = error.localizedDescription
            updateModelDownloadedState(modelID: model.id, downloaded: false)
            NotifyToastManager.shared.show("Model \(model.displayName) failed: \(error.localizedDescription)", icon: "exclamationmark.triangle", style: .error)
            AnalyticsTracker.shared.record(.modelDownloadFailed(modelID: model.id, reason: error.localizedDescription))
            throw error
        }
    }

    func deleteModel(_ model: WhisperModel) throws {
        guard !model.isBundled else { return }

        let modelPath = modelsDirectory.appendingPathComponent(model.name)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        if model.requiresUnzip {
            let extracted = modelsDirectory.appendingPathComponent(model.name.replacingOccurrences(of: ".zip", with: "").replacingOccurrences(of: ".mlpackage", with: ""))
            if FileManager.default.fileExists(atPath: extracted.path) {
                try FileManager.default.removeItem(at: extracted)
            }
        }

        updateModelDownloadedState(modelID: model.id, downloaded: false)
        manifestStore.removeEntry(modelID: model.id)
    }

    @MainActor
    func refreshModelStatus() {
        _ = manifestStore.purgeObsoleteEntries(availableModels: models)
        let mismatchEntries = manifestStore.entriesWithMismatchedChecksums(availableModels: models)
        let mismatchedIDs = Set(mismatchEntries.map { $0.modelID })

        models = models.map { model in
            if let bundleURL = bundledResourceURL(for: model) {
                var bundled = model
                bundled.isDownloaded = true
                manifestStore.upsertEntry(
                    for: bundled,
                    checksumOverride: bundleChecksum(for: bundleURL),
                    whisperKitVersion: whisperKitVersion
                )
                return bundled
            }

            var updated = model
            let modelPath = modelsDirectory.appendingPathComponent(model.name)
            if FileManager.default.fileExists(atPath: modelPath.path) {
                if mismatchedIDs.contains(model.id) {
                    try? FileManager.default.removeItem(at: modelPath)
                    manifestStore.removeEntry(modelID: model.id)
                    updated.isDownloaded = false
                } else {
                    updated.isDownloaded = true
                }
            } else if model.requiresUnzip {
                let extracted = modelsDirectory.appendingPathComponent(model.name.replacingOccurrences(of: ".zip", with: "").replacingOccurrences(of: ".mlpackage", with: ""))
                if mismatchedIDs.contains(model.id) {
                    try? FileManager.default.removeItem(at: extracted)
                    manifestStore.removeEntry(modelID: model.id)
                    updated.isDownloaded = false
                } else {
                    updated.isDownloaded = FileManager.default.fileExists(atPath: extracted.path)
                }
            } else {
                updated.isDownloaded = false
            }
            return updated
        }
    }

    func getLocalModelPath(for model: WhisperModel) -> URL? {
        print("🔍 [ModelDownloadManager] Getting local model path for: \(model.name)")
        print("🔍 [ModelDownloadManager] Model isBundled: \(model.isBundled)")
        print("🔍 [ModelDownloadManager] bundledResourceSubpath: \(model.bundledResourceSubpath ?? "nil")")
        
        if let bundledURL = bundledResourceURL(for: model) {
            print("✅ [ModelDownloadManager] Found bundled model at: \(bundledURL.path)")
            return bundledURL
        }

        if model.requiresUnzip {
            let dirName = model.name
                .replacingOccurrences(of: ".zip", with: "")
                .replacingOccurrences(of: ".mlpackage", with: "")
            let extractedPath = modelsDirectory.appendingPathComponent(dirName)
            let exists = FileManager.default.fileExists(atPath: extractedPath.path)
            print("🔍 [ModelDownloadManager] Checking extracted path: \(extractedPath.path) - exists: \(exists)")
            return exists ? extractedPath : nil
        }

        let modelPath = modelsDirectory.appendingPathComponent(model.name)
        let exists = FileManager.default.fileExists(atPath: modelPath.path)
        print("🔍 [ModelDownloadManager] Checking model path: \(modelPath.path) - exists: \(exists)")
        return exists ? modelPath : nil
    }

    private func bundledResourceURL(for model: WhisperModel) -> URL? {
        guard let subpath = model.bundledResourceSubpath else { 
            print("❌ [ModelDownloadManager] No bundledResourceSubpath for model: \(model.name)")
            return nil 
        }
        // Prefer compiled Core ML outputs placed by the build script under App/Models
        let candidates = ["App/Models/\(subpath)", subpath]
        guard let base = Bundle.main.resourceURL else { 
            print("❌ [ModelDownloadManager] Bundle.main.resourceURL is nil")
            return nil 
        }
        print("🔍 [ModelDownloadManager] Bundle base URL: \(base.path)")
        print("🔍 [ModelDownloadManager] Checking candidates: \(candidates)")
        
        for candidate in candidates {
            let url = base.appendingPathComponent(candidate)
            print("🔍 [ModelDownloadManager] Checking candidate: \(url.path)")
            if FileManager.default.fileExists(atPath: url.path) {
                print("✅ [ModelDownloadManager] Found directory: \(url.path)")
                // For bundled models, we need to return the directory containing the model components
                // (AudioEncoder.mlmodelc, MelSpectrogram.mlmodelc, TextDecoder.mlmodelc, etc.)
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    // Check if this directory contains the expected model components
                    let audioEncoder = url.appendingPathComponent("AudioEncoder.mlmodelc")
                    let melSpectrogram = url.appendingPathComponent("MelSpectrogram.mlmodelc")
                    let textDecoder = url.appendingPathComponent("TextDecoder.mlmodelc")
                    
                    let hasAudioEncoder = FileManager.default.fileExists(atPath: audioEncoder.path)
                    let hasMelSpectrogram = FileManager.default.fileExists(atPath: melSpectrogram.path)
                    let hasTextDecoder = FileManager.default.fileExists(atPath: textDecoder.path)
                    
                    print("🔍 [ModelDownloadManager] Components check:")
                    print("  - AudioEncoder.mlmodelc: \(hasAudioEncoder)")
                    print("  - MelSpectrogram.mlmodelc: \(hasMelSpectrogram)")
                    print("  - TextDecoder.mlmodelc: \(hasTextDecoder)")
                    
                    if hasAudioEncoder && hasMelSpectrogram && hasTextDecoder {
                        print("✅ [ModelDownloadManager] All required components found")
                        return url
                    }
                }
                return url
            }
        }
        print("❌ [ModelDownloadManager] No bundled resource found for model: \(model.name)")
        return nil
    }

    private func bundleChecksum(for url: URL) -> String? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                // For bundled model directories, compute checksum of the entire directory
                // This includes all the .mlmodelc files and config files
                return try computeSHA256ForDirectory(at: url)
            } else {
                return try computeSHA256(forFileAt: url)
            }
        } catch {
            StorageManager.appendToDiagnosticsLog("[ModelDownloadManager] Failed to compute bundled checksum for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func verifyChecksumIfNeeded(for model: WhisperModel, at url: URL) async throws {
        guard
            !model.isBundled,
            let checksum = model.checksum,
            checksum.starts(with: "sha256:")
        else { return }
        let expected = checksum.replacingOccurrences(of: "sha256:", with: "")

        let computed = try await Task.detached(priority: .utility) {
            try computeSHA256(forFileAt: url)
        }.value

        guard computed == expected else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(
                domain: "ModelDownloadManager",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Checksum mismatch for model \(model.displayName). Expected \(expected) but found \(computed)."
                ]
            )
        }
    }

    private func unpackArchive(at url: URL) async throws {
        let destinationDir = url.deletingPathExtension()
        if FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.removeItem(at: destinationDir)
        }

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw NSError(
                domain: "ModelDownloadManager",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unable to read archive \(url.lastPathComponent): \(error.localizedDescription)"
                ]
            )
        }

        do {
            for entry in archive {
                let entryDestination = destinationDir.appendingPathComponent(entry.path)
                let parentDirectory = entryDestination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

                if entry.type == .directory {
                    try FileManager.default.createDirectory(at: entryDestination, withIntermediateDirectories: true)
                } else {
                    _ = try archive.extract(entry, to: entryDestination)
                }
            }
        } catch {
            throw NSError(domain: "ModelDownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to unpack \(url.lastPathComponent): \(error.localizedDescription)"])
        }

        try FileManager.default.removeItem(at: url)
    }

    private func updateModelDownloadedState(modelID: String, downloaded: Bool) {
        models = models.map { model in
            guard model.id == modelID else { return model }
            var updated = model
            updated.isDownloaded = downloaded
            return updated
        }
    }
}

private class DownloadTask {
    let sourceURL: URL
    let destination: URL
    private var downloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    private let session: URLSession

    init(sourceURL: URL, destination: URL, session: URLSession) {
        self.sourceURL = sourceURL
        self.destination = destination
        self.session = session
    }

    func execute(progressHandler: @escaping (Double) -> Void, stateHandler: @escaping (String) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (URL?, URLResponse?, Error?) -> Void = { tempURL, response, error in
                if let error = error {
                    if let urlError = error as? URLError, urlError.code == .cancelled, let resume = self.resumeData {
                        self.resumeData = resume
                        stateHandler("cancelled")
                        continuation.resume(throwing: error)
                        return
                    }
                    stateHandler("failed")
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL = tempURL else {
                    stateHandler("failed")
                    continuation.resume(throwing: NSError(domain: "DownloadTask", code: -1, userInfo: [NSLocalizedDescriptionKey: "No temporary file URL"]))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let message: String
                    if httpResponse.statusCode == 401 {
                        message = "Model download requires authentication (HTTP 401). Add a valid Hugging Face token in Settings or download the file manually."
                    } else {
                        message = "Model download failed with HTTP status \(httpResponse.statusCode)."
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                    stateHandler("failed")
                    continuation.resume(throwing: NSError(domain: "ModelDownloadManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: self.destination.path) {
                        try FileManager.default.removeItem(at: self.destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: self.destination)
                    stateHandler("completed")
                    continuation.resume()
                } catch {
                    stateHandler("failed")
                    continuation.resume(throwing: error)
                }
            }

            if let resumeData = resumeData {
                downloadTask = session.downloadTask(withResumeData: resumeData, completionHandler: completion)
                stateHandler("resumed")
            } else {
                downloadTask = session.downloadTask(with: sourceURL, completionHandler: completion)
                stateHandler("started")
            }

            downloadTask?.resume()

            Task.detached {
                while let task = self.downloadTask {
                    let bytes = task.countOfBytesReceived
                    let total = task.countOfBytesExpectedToReceive
                    if total > 0 {
                        let progress = Double(bytes) / Double(total)
                        progressHandler(progress)
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }

    func cancel() {
        downloadTask?.cancel(byProducingResumeData: { data in
            self.resumeData = data
        })
    }
}

private func computeSHA256(forFileAt url: URL) throws -> String {
    guard let stream = InputStream(url: url) else {
        throw NSError(domain: "ModelDownloadManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unable to open file for checksum validation."])
    }
    stream.open()
    defer { stream.close() }

    var hasher = SHA256()
    let bufferSize = 1_048_576
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            throw stream.streamError ?? NSError(domain: "ModelDownloadManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to read file while computing checksum."])
        }
        if read == 0 { break }
        let chunk = Data(buffer.prefix(read))
        hasher.update(data: chunk)
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func computeSHA256ForDirectory(at rootURL: URL) throws -> String {
    var fileURLs: [URL] = []
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

    while let item = enumerator?.nextObject() as? URL {
        let values = try item.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true { continue }
        if item.lastPathComponent == ".DS_Store" { continue }
        fileURLs.append(item)
    }

    // Sort deterministically by path relative to root
    let sorted = fileURLs.sorted { a, b in
        let ar = a.path.replacingOccurrences(of: rootURL.path, with: "")
        let br = b.path.replacingOccurrences(of: rootURL.path, with: "")
        return ar < br
    }

    var hasher = SHA256()
    for file in sorted {
        let relativePath = file.path.replacingOccurrences(of: rootURL.path, with: "")
        if let relData = relativePath.data(using: .utf8) {
            hasher.update(data: relData)
        }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        hasher.update(data: data)
    }
    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}
