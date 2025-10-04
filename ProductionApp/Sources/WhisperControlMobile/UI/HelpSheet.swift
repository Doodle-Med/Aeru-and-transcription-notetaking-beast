import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Getting Started") {
                    Label("Download a Core ML model from Settings → Models", systemImage: "arrow.down.circle")
                    Label("Allow microphone access when prompted", systemImage: "mic.fill")
                    Label("Use count-in if you need a moment before speaking", systemImage: "timer")
                }

                Section("Troubleshooting") {
                    Label("Check Diagnostics Log for download/transcription issues", systemImage: "doc.text.magnifyingglass")
                    Label("Enable background recording if you need to switch apps", systemImage: "waveform")
                    Label("Cloud errors will appear as toasts with retry info", systemImage: "cloud")
                }

                Section("Resources") {
                    Link(destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!) {
                        Label("WhisperKit Documentation", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://platform.openai.com/docs/guides/speech-to-text")!) {
                        Label("OpenAI Whisper API", systemImage: "cloud")
                    }
                    Link(destination: URL(string: "https://ai.google.dev/docs")!) {
                        Label("Google Gemini Docs", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Quick Help")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
