import SwiftUI

struct BroadcastLiveTranscriptView: View {
    @StateObject private var store = BroadcastTranscriptStore.shared
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Transcript (Broadcast)")
                    .font(.headline)
                Spacer()
                if store.isActive {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Circle()
                            .fill(.gray)
                            .frame(width: 8, height: 8)
                        Text("Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let sessionStartTime = store.sessionStartTime {
                HStack {
                    Text("Session started: \(sessionStartTime, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Duration: \(formatDuration(since: sessionStartTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.lines.isEmpty {
                        Text("No transcript available yet. Start a broadcast session to see live transcription.")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(store.lines.indices, id: \.self) { idx in
                            Text(store.lines[idx])
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            
            HStack {
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: CaptureStatusCenter.forceStopReplayKitNotification, object: nil)
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!store.isActive)
                
                Spacer()
                
                Button {
                    saveCurrent()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(store.lines.isEmpty)
            }
        }
        .padding()
        .onAppear { store.startPolling() }
        .onDisappear { store.stop() }
        .alert("Save Result", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveMessage)
        }
    }

    private func saveCurrent() {
        guard !store.lines.isEmpty else { return }
        
        let timestamp = Date().ISO8601Format()
        let text = store.lines.joined(separator: "\n")
        
        // Save transcript
        let transcriptFilename = "Broadcast-\(timestamp).txt"
        let transcriptURL = StorageManager.makeRecordingURL(filename: transcriptFilename)
        
        // Save audio if available
        var audioFilename: String?
        var audioURL: URL?
        if let audioData = getBroadcastAudioData() {
            audioFilename = "Broadcast-\(timestamp).wav"
            audioURL = StorageManager.makeRecordingURL(filename: audioFilename!)
        }
        
        do {
            // Save transcript
            try text.data(using: .utf8)?.write(to: transcriptURL)
            
            // Save audio if available
            if let audioData = getBroadcastAudioData(), let audioURL = audioURL {
                try audioData.write(to: audioURL)
            }
            
            let audioMessage = audioFilename != nil ? " and audio (\(audioFilename!))" : ""
            saveMessage = "Transcript saved successfully to \(transcriptFilename)\(audioMessage)\n\nFiles saved to Documents/Recordings folder."
            showingSaveAlert = true
            
            StorageManager.appendToDiagnosticsLog("Saved broadcast transcript to \(transcriptFilename)")
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
            showingSaveAlert = true
            StorageManager.appendToDiagnosticsLog("Failed to save broadcast transcript: \(error)")
        }
    }
    
    private func getBroadcastAudioData() -> Data? {
        guard let audioURL = AppGroupConstants.containerURL()?.appendingPathComponent("broadcast/live_audio.wav") else { return nil }
        return try? Data(contentsOf: audioURL)
    }
    
    private func formatDuration(since startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


