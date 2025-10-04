import SwiftUI

struct UniversalExportButton: View {
    let filename: String
    private let resultProvider: () -> TranscriptionResult?
    private let plainTextProvider: () -> String?
    private let displayStyle: DisplayStyle

    enum DisplayStyle {
        case label
        case icon
        case text(String)
    }

    init(filename: String,
         result: @escaping () -> TranscriptionResult?,
         plainText: @escaping () -> String?,
         displayStyle: DisplayStyle = .label) {
        self.filename = filename
        self.resultProvider = result
        self.plainTextProvider = plainText
        self.displayStyle = displayStyle
    }

    var body: some View {
        let result = resultProvider()
        let fallbackText = plainTextProvider() ?? result?.text
        let normalizedText = normalized(fallbackText)

        return Menu {
            if let normalizedText {
                Button {
                    ExportCoordinator.shared.copyToClipboard(normalizedText)
                    NotifyToastManager.shared.show("Copied transcript", icon: "doc.on.doc", style: .success)
                } label: {
                    Label("Copy All Text", systemImage: "doc.on.doc")
                }

                Button {
                    Task { @MainActor in
                        do {
                            try await ExportCoordinator.shared.share(text: normalizedText, suggestedFilename: filenameWithExtension("txt"))
                            NotifyToastManager.shared.show("Shared text", icon: "square.and.arrow.up", style: .success)
                        } catch {
                            NotifyToastManager.shared.show("Share failed: \(error.localizedDescription)", icon: "xmark.octagon", style: .error)
                        }
                    }
                } label: {
                    Label("Share as Text", systemImage: "square.and.arrow.up")
                }
            }

            if let result {
                if normalizedText != nil {
                    Divider()
                }
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button {
                        Task { @MainActor in
                            await share(result: result, as: format)
                        }
                    } label: {
                        Label("Export as \(format.displayName)", systemImage: iconName(for: format))
                    }
                }
            }
        } label: {
            menuLabel()
        }
        .accessibilityIdentifier("universal_export_button")
        .disabled(result == nil && normalizedText == nil)
    }

    @ViewBuilder
    private func menuLabel() -> some View {
        switch displayStyle {
        case .label:
            Label("Export", systemImage: "square.and.arrow.up")
        case .icon:
            Image(systemName: "square.and.arrow.up")
        case .text(let value):
            Text(value)
        }
    }

    private func share(result: TranscriptionResult, as format: ExportFormat) async {
        do {
            try await ExportCoordinator.shared.share(result: result, format: format, filename: filename)
            NotifyToastManager.shared.show("Shared as \(format.displayName)", icon: "square.and.arrow.up", style: .success)
        } catch {
            NotifyToastManager.shared.show("Export failed: \(error.localizedDescription)", icon: "xmark.octagon", style: .error)
        }
    }

    private func iconName(for format: ExportFormat) -> String {
        switch format {
        case .text:
            return "doc.plaintext"
        case .json:
            return "curlybraces.square"
        case .srt:
            return "subtitle"
        case .vtt:
            return "waveform"
        }
    }

    private func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func filenameWithExtension(_ ext: String) -> String {
        if filename.lowercased().hasSuffix(".\(ext)") { return filename }
        return "\(filename).\(ext)"
    }
}
