import SwiftUI
import AVFoundation

struct AudioRecorderView: View {
    @EnvironmentObject var jobManager: JobManager
    @EnvironmentObject var settings: AppSettings
    @StateObject private var recorder = AudioRecorder()
    @Environment(\.dismiss) private var dismiss
    @State private var amplitudes: [Double] = Array(repeating: 0.0, count: 80)
    @State private var vadActive = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text(countdownTitle)
                        .font(.headline)
                        .transition(.opacity)
                    Text(countdownSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                .padding(.top, 32)

                if !settings.allowBackgroundRecording && countdown != nil {
                    Label("Recording stops when you leave the app.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .padding(10)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal)
                }

                WaveformView(amplitudes: amplitudes)
                    .frame(height: 140)
                    .padding(.horizontal)
                    .overlay(alignment: .center) {
                        if let countdown {
                            Text("\(countdown)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(40)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                                .transition(.scale)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: amplitudes)
                    .animation(.spring(), value: countdown)

                HStack(spacing: 12) {
                    Label(formatDuration(recorder.duration), systemImage: "timer")
                        .font(.title2)
                        .monospacedDigit()
                    Spacer()
                    Label(vadActive ? "Listening" : "Quiet", systemImage: vadActive ? "waveform" : "waveform.slash")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(vadActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundColor(vadActive ? .blue : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: vadActive)
                }
                .padding(.horizontal)

                Spacer()

                HStack(spacing: 40) {
                    Button(role: .cancel) {
                        cancelCountdownIfNeeded()
                        recorder.cancelRecording()
                        NotifyToastManager.shared.show("Recording discarded", icon: "xmark", style: .warning)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task {
                            do {
                                cancelCountdownIfNeeded()
                                if let url = try await recorder.stopRecording() {
                                    await jobManager.addJob(audioURL: url, filename: "Recording-\(Date().formatted(.dateTime.hour().minute().second()))")
                                    NotifyToastManager.shared.show("Added recording to queue", icon: "mic.fill", style: .success)
                                    dismiss()
                                }
                            } catch {
                                HapticGenerator.error()
                                NotifyToastManager.shared.show("Failed to stop recording", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    } label: {
                        Image(systemName: recorder.state == .recording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 84))
                            .foregroundColor(.red)
                            .modifier(SymbolEffectModifier(isRecording: recorder.state == .recording))
                    }
                    .disabled(recorder.state != .recording || countdown != nil)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Recorder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cancelCountdownIfNeeded()
                        recorder.cancelRecording()
                        dismiss()
                    }
                }
            }
            .task {
                await beginRecordingFlow()
            }
            .onDisappear {
                cancelCountdownIfNeeded()
            }
        }
    }

    private func beginRecordingFlow() async {
        if settings.countInEnabled {
            await runCountdown(seconds: settings.countInSeconds)
        }
        await startRecorder()
    }

    private func runCountdown(seconds: Int) async {
        await MainActor.run {
            countdown = seconds
        }
        countdownTask = Task {
            var remaining = seconds
            while remaining > 0 && !Task.isCancelled {
                HapticGenerator.impact(style: .rigid)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
                await MainActor.run {
                    countdown = remaining
                }
            }
            await MainActor.run {
                countdown = nil
            }
        }
        await countdownTask?.value
    }

    private func cancelCountdownIfNeeded() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func startRecorder() async {
        do {
            try await recorder.startRecording(allowBackground: settings.allowBackgroundRecording)
            HapticGenerator.impact()
            for await amplitude in recorder.waveformPublisher.values {
                amplitudes.removeFirst()
                amplitudes.append(amplitude)
                vadActive = amplitude > 0.05
            }
        } catch {
            HapticGenerator.error()
            NotifyToastManager.shared.show("Microphone access failed", icon: "mic.slash", style: .error)
            dismiss()
        }
    }

    private var countdownTitle: String {
        if let countdown { return countdown > 0 ? "Starting in…" : "Recording" }
        return "Speak naturally"
    }

    private var countdownSubtitle: String {
        if let countdown {
            return countdown > 0 ? "Release to cancel before we begin." : "We’ll normalize audio automatically before sending it to your model."
        }
        return "We’ll normalize audio automatically before sending it to your chosen model."
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}

private struct WaveformView: View {
    let amplitudes: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(amplitudes.count)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(amplitudes.enumerated()), id: \.offset) { _, amplitude in
                    Capsule()
                        .fill(LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: width, height: max(8, CGFloat(amplitude) * proxy.size.height))
                        .animation(.easeOut(duration: 0.15), value: amplitude)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

struct AudioRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        AudioRecorderView()
            .environmentObject(JobManager(jobStore: JobStore(), settings: AppSettings(), modelManager: ModelDownloadManager()))
    }
}

struct SymbolEffectModifier: ViewModifier {
    let isRecording: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .symbolEffect(.pulse.byLayer, options: isRecording ? .repeating : .nonRepeating)
        } else {
            content
        }
    }
}
