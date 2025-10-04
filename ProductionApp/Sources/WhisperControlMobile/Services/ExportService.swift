import Foundation
import ZIPFoundation

struct ExportPayload {
    let data: Data
    let filename: String
    let mimeType: String
}

final class ExportService {
    func export(result: TranscriptionResult, format: ExportFormat, filename: String = "transcript") throws -> ExportPayload {
        let content: Data
        switch format {
        case .text:
            content = exportAsText(result).data(using: .utf8) ?? Data()
        case .json:
            content = try exportAsJSON(result)
        case .srt:
            content = exportAsSRT(result).data(using: .utf8) ?? Data()
        case .vtt:
            content = exportAsVTT(result).data(using: .utf8) ?? Data()
        }

        return ExportPayload(data: content, filename: "\(filename).\(format.rawValue)", mimeType: format.mimeType)
    }

    func archive(jobs: [TranscriptionJob], to url: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let archive = try Archive(url: url, accessMode: .create)

        for job in jobs {
            guard let result = job.result else { continue }
            let exportFormats: [ExportFormat] = [.text, .json]
            for format in exportFormats {
                let payload = try export(result: result, format: format, filename: job.filename)
                try archive.addEntry(with: "\(job.filename)/\(payload.filename)", type: .file, uncompressedSize: Int64(payload.data.count), compressionMethod: .deflate) { position, size in
                    let lowerBound = Int(position)
                    let upperBound = min(lowerBound + Int(size), payload.data.count)
                    return payload.data.subdata(in: lowerBound..<upperBound)
                }
            }
        }

        return url
    }

    private func exportAsText(_ result: TranscriptionResult) -> String {
        return result.segments.map { $0.text }.joined(separator: " ")
    }

    private func exportAsJSON(_ result: TranscriptionResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(result)
    }

    private func exportAsSRT(_ result: TranscriptionResult) -> String {
        var lines: [String] = []

        for (index, segment) in result.segments.enumerated() {
            let startTime = formatTime(segment.start)
            let endTime = formatTime(segment.end)
            let text = segment.text

            lines.append("\(index + 1)")
            lines.append("\(startTime) --> \(endTime)")
            lines.append(text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func exportAsVTT(_ result: TranscriptionResult) -> String {
        var lines: [String] = []
        lines.append("WEBVTT")
        lines.append("")

        for segment in result.segments {
            let startTime = formatTimeVTT(segment.start)
            let endTime = formatTimeVTT(segment.end)
            let text = segment.text

            lines.append("\(startTime) --> \(endTime)")
            lines.append(text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }

    private func formatTimeVTT(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, milliseconds)
    }
}
