import SwiftUI

struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Recording Data") {
                    Label("Audio stays on device unless you export or enable cloud offload.", systemImage: "lock")
                    Label("Temporary files are stored under Application Support/Recordings and auto-cleaned after 7 days.", systemImage: "externaldrive")
                }

                Section("Cloud Providers") {
                    Label("OpenAI/Gemini receive audio only when you enable them and provide an API key.", systemImage: "cloud")
                    Label("Responses are stored in the job queue for your review and can be deleted at any time.", systemImage: "trash")
                }

                Section("Diagnostics") {
                    Label("Diagnostics log contains timestamps and high-level event messages (no audio).", systemImage: "doc.text.magnifyingglass")
                    Label("You can clear or share the log from Settings or the queue toolbar.", systemImage: "arrow.uturn.backward")
                }

                Section("Background Mode") {
                    Label("Background recording keeps the session active if you switch apps, but audio remains local.", systemImage: "waveform")
                    Label("Disable background mode if you prefer the recorder to pause when the app leaves the foreground.", systemImage: "pause")
                }
            }
            .navigationTitle("Privacy & Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
