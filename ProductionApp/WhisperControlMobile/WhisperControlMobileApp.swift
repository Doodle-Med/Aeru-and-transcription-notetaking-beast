import SwiftUI

@main
struct WhisperControlMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "waveform")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("WhisperControl Mobile")
                .font(.title)
            Text("Audio Transcription App")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
