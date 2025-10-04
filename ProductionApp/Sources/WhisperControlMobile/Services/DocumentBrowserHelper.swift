import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Helper for document export and sharing
/// Provides native iOS document browser integration
enum DocumentBrowserHelper {
    
    /// Export options for transcript files
    struct ExportOptions {
        let includeAudio: Bool
        let formats: Set<ExportFormat>
        
        static let transcriptOnly = ExportOptions(includeAudio: false, formats: [.txt, .json])
        static let complete = ExportOptions(includeAudio: true, formats: [.txt, .json, .srt, .vtt])
    }
    
    enum ExportFormat: String, CaseIterable {
        case txt
        case json
        case srt
        case vtt
        case wav
        
        var fileExtension: String {
            rawValue
        }
        
        #if canImport(UniformTypeIdentifiers)
        @available(iOS 14.0, macOS 11.0, *)
        var uti: UTType {
            switch self {
            case .txt: return .plainText
            case .json: return .json
            case .srt: return UTType(filenameExtension: "srt") ?? .text
            case .vtt: return UTType(filenameExtension: "vtt") ?? .text
            case .wav: return .wav
            }
        }
        #endif
    }
    
    #if canImport(UIKit)
    /// Present share sheet for exporting files
    @MainActor
    static func share(urls: [URL], from viewController: UIViewController?) {
        guard !urls.isEmpty else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: urls,
            applicationActivities: nil
        )
        
        // iPad support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController?.view
            popover.sourceRect = viewController?.view.bounds ?? .zero
        }
        
        viewController?.present(activityVC, animated: true)
        AppLogger.log("[EXPORT] Share sheet presented with \(urls.count) files", category: AppLogger.storage, level: .info)
    }
    
    /// Copy file to user-accessible location (Files app integration)
    @MainActor
    static func exportToFiles(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard url.startAccessingSecurityScopedResource() else {
            completion(.failure(NSError(domain: "DocumentBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access file"])))
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportsDir = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
            
            let destURL = exportsDir.appendingPathComponent(url.lastPathComponent)
            
            // Remove existing if present
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            
            try FileManager.default.copyItem(at: url, to: destURL)
            
            AppLogger.log("[EXPORT] File exported to Files app: \(destURL.lastPathComponent)", category: AppLogger.storage, level: .info)
            completion(.success(destURL))
        } catch {
            AppLogger.log("[EXPORT] Failed to export to Files app: \(error)", category: AppLogger.storage, level: .error)
            completion(.failure(error))
        }
    }
    
    /// Create a zipped bundle of multiple files
    static func createZipBundle(files: [URL], outputName: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("\(outputName).zip")
        
        // Remove existing zip
        try? FileManager.default.removeItem(at: zipURL)
        
        // Note: For production, use a proper zip library like ZIPFoundation
        // This is a placeholder that would require external dependency
        // For now, we'll just create a directory
        let bundleDir = tempDir.appendingPathComponent(outputName, isDirectory: true)
        try? FileManager.default.removeItem(at: bundleDir)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        
        for file in files {
            let destURL = bundleDir.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destURL)
        }
        
        AppLogger.log("[EXPORT] Created bundle with \(files.count) files at \(bundleDir.lastPathComponent)", category: AppLogger.storage, level: .info)
        return bundleDir
    }
    #endif
    
    /// Get shareable URLs for a transcription job
    static func getExportURLs(for job: TranscriptionJob, options: ExportOptions) -> [URL] {
        var urls: [URL] = []
        
        // Add transcript files based on formats
        if let result = job.result {
            let baseName = job.filename.replacingOccurrences(of: " ", with: "_")
                .components(separatedBy: ".").first ?? "transcript"
            
            if options.formats.contains(.txt), let txtURL = createTextExport(result: result, baseName: baseName) {
                urls.append(txtURL)
            }
            
            if options.formats.contains(.json), let jsonURL = createJSONExport(result: result, baseName: baseName) {
                urls.append(jsonURL)
            }
            
            if options.formats.contains(.srt), let srtURL = createSRTExport(result: result, baseName: baseName) {
                urls.append(srtURL)
            }
            
            if options.formats.contains(.vtt), let vttURL = createVTTExport(result: result, baseName: baseName) {
                urls.append(vttURL)
            }
        }
        
        // Add audio if requested
        if options.includeAudio {
            if FileManager.default.fileExists(atPath: job.originalURL.path) {
                urls.append(job.originalURL)
            }
        }
        
        return urls
    }
    
    // MARK: - Export Helpers
    
    private static func createTextExport(result: TranscriptionResult, baseName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(baseName).txt")
        
        let text = result.segments.map { segment in
            if let speaker = segment.speaker {
                return "[\(speaker)] \(segment.text)"
            }
            return segment.text
        }.joined(separator: "\n")
        
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private static func createJSONExport(result: TranscriptionResult, baseName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(baseName).json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(result) else { return nil }
        try? data.write(to: url)
        return url
    }
    
    private static func createSRTExport(result: TranscriptionResult, baseName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(baseName).srt")
        
        var srtContent = ""
        for (index, segment) in result.segments.enumerated() {
            let startTime = formatSRTTime(segment.start)
            let endTime = formatSRTTime(segment.end)
            
            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            if let speaker = segment.speaker {
                srtContent += "[\(speaker)] "
            }
            srtContent += "\(segment.text)\n\n"
        }
        
        try? srtContent.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private static func createVTTExport(result: TranscriptionResult, baseName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(baseName).vtt")
        
        var vttContent = "WEBVTT\n\n"
        for segment in result.segments {
            let startTime = formatVTTTime(segment.start)
            let endTime = formatVTTTime(segment.end)
            
            vttContent += "\(startTime) --> \(endTime)\n"
            if let speaker = segment.speaker {
                vttContent += "<v \(speaker)>"
            }
            vttContent += "\(segment.text)\n\n"
        }
        
        try? vttContent.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
    
    private static func formatVTTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}
