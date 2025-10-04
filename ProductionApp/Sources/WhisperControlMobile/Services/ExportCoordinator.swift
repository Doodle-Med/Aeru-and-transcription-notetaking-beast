import Foundation
import UIKit

@MainActor
final class ExportCoordinator {
    static let shared = ExportCoordinator()
    private init() {}

    private let exportService = ExportService()

    func share(result: TranscriptionResult, format: ExportFormat, filename: String) async throws {
        let payload = try exportService.export(result: result, format: format)
        let tempURL = try writeTempFile(payload: payload, baseName: filename)

        let controller = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .saveToCameraRoll]

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            throw NSError(domain: "ExportCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to find root view controller for sharing"])
        }

        await MainActor.run {
            root.present(controller, animated: true)
        }
    }

    private func writeTempFile(payload: ExportPayload, baseName: String) throws -> URL {
        let sanitized = baseName.replacingOccurrences(of: " ", with: "_")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension(payload.filename.split(separator: ".").last.map(String.init) ?? "txt")

        try payload.data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}

