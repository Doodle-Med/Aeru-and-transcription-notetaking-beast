import Foundation

struct ModelManifestEntry: Codable, Equatable {
    let modelID: String
    let checksum: String?
    let format: WhisperModel.Format
    let whisperKitVersion: String?
    let lastUpdated: Date

    init(modelID: String, checksum: String?, format: WhisperModel.Format, whisperKitVersion: String?) {
        self.modelID = modelID
        self.checksum = checksum
        self.format = format
        self.whisperKitVersion = whisperKitVersion
        self.lastUpdated = Date()
    }
}

struct ModelManifest: Codable {
    var version: Int
    var entries: [ModelManifestEntry]

    static let currentVersion = 1

    init(version: Int = ModelManifest.currentVersion, entries: [ModelManifestEntry] = []) {
        self.version = version
        self.entries = entries
    }
}

@MainActor
final class ModelManifestStore {
    private let manifestURL: URL
    private var manifest: ModelManifest

    init(directory: URL) {
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        self.manifest = ModelManifestStore.loadManifest(at: manifestURL)
    }

    private static func loadManifest(at url: URL) -> ModelManifest {
        guard let data = try? Data(contentsOf: url) else {
            return ModelManifest()
        }

        do {
            let decoded = try JSONDecoder().decode(ModelManifest.self, from: data)
            return decoded
        } catch {
            print("[ModelManifestStore] Failed to decode manifest: \(error)")
            return ModelManifest()
        }
    }

    func entry(for modelID: String) -> ModelManifestEntry? {
        manifest.entries.first { $0.modelID == modelID }
    }

    func upsertEntry(for model: WhisperModel, checksumOverride: String? = nil, whisperKitVersion: String?) {
        let entry = ModelManifestEntry(
            modelID: model.id,
            checksum: checksumOverride ?? model.checksum,
            format: model.format,
            whisperKitVersion: whisperKitVersion
        )

        if let index = manifest.entries.firstIndex(where: { $0.modelID == model.id }) {
            manifest.entries[index] = entry
        } else {
            manifest.entries.append(entry)
        }

        persist()
    }

    func removeEntry(modelID: String) {
        manifest.entries.removeAll { $0.modelID == modelID }
        persist()
    }

    func purgeObsoleteEntries(availableModels: [WhisperModel]) -> [ModelManifestEntry] {
        let availableIDs = Set(availableModels.map { $0.id })
        let obsolete = manifest.entries.filter { !availableIDs.contains($0.modelID) }

        if !obsolete.isEmpty {
            manifest.entries.removeAll { entry in obsolete.contains(where: { $0.modelID == entry.modelID }) }
            persist()
        }
        return obsolete
    }

    func entriesWithMismatchedChecksums(availableModels: [WhisperModel]) -> [ModelManifestEntry] {
        let lookup = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.id, $0) })
        return manifest.entries.filter { entry in
            guard let model = lookup[entry.modelID] else { return false }
            return entry.checksum != model.checksum
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            print("[ModelManifestStore] Persist failure: \(error)")
        }
    }
}

