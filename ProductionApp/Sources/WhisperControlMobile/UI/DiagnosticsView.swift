import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = StorageManager.readDiagnosticsLog()
    @State private var copied = false

    var body: some View {
        NavigationView {
            ScrollView {
                if logContent.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView("No Diagnostics Yet", systemImage: "doc.text.magnifyingglass", description: Text("Logs from downloads, transcription attempts, and errors will appear here for troubleshooting."))
                            .padding()
                    } else {
                        VStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No Diagnostics Yet")
                                .font(.headline)
                            Text("Logs from downloads, transcription attempts, and errors will appear here for troubleshooting.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                } else {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(action: clear) {
                        Image(systemName: "trash")
                    }
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark.circle" : "doc.on.doc")
                    }
                    .disabled(logContent.isEmpty)
                    ShareLink(item: logContent, preview: SharePreview("Diagnostics Log")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(logContent.isEmpty)
                }
            }
        }
    }

    private func refresh() {
        logContent = StorageManager.readDiagnosticsLog()
        copied = false
    }

    private func clear() {
        StorageManager.clearDiagnosticsLog()
        logContent = ""
        copied = false
    }

    private func copy() {
        StorageManager.copyDiagnosticsToClipboard()
        copied = true
    }
}
