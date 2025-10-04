import SwiftUI

struct LiveTranscriptionView: View {
    @StateObject private var liveManager = LiveTranscriptionManager()
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var modelManager: ModelDownloadManager
    @EnvironmentObject var jobManager: JobManager
    @State private var showingSettings = false
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    // Status indicator
                    HStack {
                        Circle()
                            .fill(liveManager.isStreaming ? .green : .gray)
                            .frame(width: 12, height: 12)
                        Text(liveManager.isStreaming ? "Live" : "Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Transcription text
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !liveManager.finalText.isEmpty {
                                Text("Final:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(liveManager.finalText)
                                    .font(.body)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                            
                            if !liveManager.partialText.isEmpty {
                                Text("Live:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(liveManager.partialText)
                                    .font(.body)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            if liveManager.finalText.isEmpty && liveManager.partialText.isEmpty {
                                Text("Start live transcription to see text here")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Error message
                    if let error = liveManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Control buttons
                    HStack(spacing: 20) {
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        if liveManager.isStreaming {
                            Button("Stop") {
                                StorageManager.logUserAction("Live Transcription Stop", details: "Backend: \(liveManager.backend.rawValue)")
                                liveManager.stop()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            // Only show Save button when NOT streaming (after stop)
                            Button(action: {
                                Task { @MainActor in
                                    guard liveManager.canSaveNow() else { 
                                        NotifyToastManager.shared.show("Please wait before saving again", icon: "clock", style: .warning)
                                        return 
                                    }
                                    isProcessing = true
                                    StorageManager.logUserAction("Live Transcription Save", details: "Backend: \(liveManager.backend.rawValue), Text length: \(liveManager.finalText.count + liveManager.partialText.count)")
                                    StorageManager.appendToDiagnosticsLog("[LIVE] Manual save invoked")
                                    
                                    // Get the text to save (prefer final over partial)
                                    let text = liveManager.finalText.isEmpty ? liveManager.partialText : liveManager.finalText
                                    
                                    // Get the audio file if available
                                    let audioURL = liveManager.finalizeLiveFileForSaving()
                                    
                                    if let audioURL = audioURL {
                                        // Save with audio - use simple filename
                                        let backendName = liveManager.backend == .appleNative ? "apple" : liveManager.backend.rawValue
                                        let simpleName = JobManager.generateSimpleFilename(backend: backendName)
                                        StorageManager.appendToDiagnosticsLog("[LIVE] Saving with audio: \(simpleName)")
                                        _ = await jobManager.addCompletedLiveItem(audioURL: audioURL, displayFilename: simpleName, text: text)
                                        StorageManager.logUserAction("Live Transcription Save Success", details: "Saved with audio: \(simpleName)")
                                        NotifyToastManager.shared.show("Saved transcription with audio", icon: "waveform", style: .success)
                                        liveManager.cleanupAfterSave()
                                    } else if !text.isEmpty {
                                        // Save text only - use simple filename
                                        let backendName = liveManager.backend == .appleNative ? "apple" : liveManager.backend.rawValue
                                        let simpleName = JobManager.generateSimpleFilename(backend: backendName)
                                        let textURL = StorageManager.makeRecordingURL(filename: "\(simpleName).txt")
                                        do { 
                                        try text.data(using: .utf8)?.write(to: textURL)
                                        StorageManager.appendToDiagnosticsLog("[LIVE] Saved text only: \(simpleName).txt")
                                        StorageManager.logUserAction("Live Transcription Save Success", details: "Saved text only: \(simpleName)")
                                        NotifyToastManager.shared.show("Saved transcription text", icon: "doc", style: .success)
                                        liveManager.cleanupAfterSave()
                                    } catch {
                                        StorageManager.logError(error, context: "Live Transcription Save Text")
                                        StorageManager.appendToDiagnosticsLog("[LIVE] Failed to save text: \(error.localizedDescription)")
                                        NotifyToastManager.shared.show("Failed to save text", icon: "exclamationmark.triangle", style: .error)
                                    }
                                } else {
                                    StorageManager.logUserAction("Live Transcription Save", details: "Failed - No content to save")
                                    NotifyToastManager.shared.show("No content to save", icon: "exclamationmark.triangle", style: .warning)
                                }
                                    
                                    isProcessing = false
                                }
                            }) {
                                Label("Save", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(liveManager.finalText.isEmpty && liveManager.partialText.isEmpty)
                        }
 
                        if !liveManager.isStreaming {
                            Button("Start") {
                                Task {
                                    isProcessing = true
                                    StorageManager.logUserAction("Live Transcription Start", details: "Backend: \(settings.liveTranscriptionBackend.rawValue)")
                                    await liveManager.start(settings: settings, modelManager: modelManager)
                                    isProcessing = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Processing overlay
                if isProcessing {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView("Processing…")
                            .progressViewStyle(.circular)
                        Text("Please wait")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
            }
            .navigationTitle("Live Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSettings) {
                NavigationView {
                    LiveTranscriptionSettingsView()
                        .environmentObject(settings)
                        .environmentObject(modelManager)
                }
            }
        }
    }
}

struct LiveTranscriptionSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var modelManager: ModelDownloadManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section("Backend") {
                Picker("Backend", selection: $settings.liveTranscriptionBackend) {
                    Text("Apple Native").tag(LiveTranscriptionBackend.appleNative)
                    Text("Whisper Tiny").tag(LiveTranscriptionBackend.whisperTiny)
                    Text("Whisper Base").tag(LiveTranscriptionBackend.whisperBase)
                }
                .pickerStyle(.segmented)
            }
            
            Section("Model Status") {
                if let modelID = settings.liveTranscriptionBackend.requiredModelID,
                   let model = modelManager.models.first(where: { $0.id == modelID }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("No model required for Apple Native")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Live Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    LiveTranscriptionView()
        .environmentObject(LiveTranscriptionManager())
        .environmentObject(AppSettings())
        .environmentObject(ModelDownloadManager())
}
