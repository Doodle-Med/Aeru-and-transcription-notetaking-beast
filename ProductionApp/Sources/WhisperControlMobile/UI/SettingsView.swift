import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var modelManager: ModelDownloadManager
    @EnvironmentObject var jobManager: JobManager
    @State private var showDiagnosticsSheet = false
    @State private var showHelp = false
    @State private var showPrivacy = false
    @State private var showRAGManagement = false
    @State private var showAPISettings = false
    @StateObject private var replayKit = ReplayKitCaptureService()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    SummaryCard(settings: settings)
                    AnalyticsPanel()
                    ModelSelectionCard(settings: settings, modelManager: modelManager)
                    DarkModeSettingsCard(settings: settings)
                    TranscriptionSettingsCard(settings: settings)
                    RecorderSettingsCard(settings: settings)
                    CloudSettingsCard(settings: settings)
                    AdvancedSettingsCard(settings: settings)
                    ResetDefaultsCard(settings: settings)
                    Section(header: Text("RAG Database")) {
                        Button {
                            showRAGManagement = true
                        } label: {
                            Label("Manage RAG Database", systemImage: "brain.head.profile")
                        }
                    }
                    
                    Section(header: Text("API Integration")) {
                        Button {
                            showAPISettings = true
                        } label: {
                            Label("API Settings", systemImage: "network")
                        }
                    }
                    
                    Section(header: Text("Support")) {
                        Button {
                            showDiagnosticsSheet.toggle()
                        } label: {
                            Label("Diagnostics Log", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            showHelp = true
                        } label: {
                            Label("Quick Help", systemImage: "questionmark.circle")
                        }
                        Button {
                            showPrivacy = true
                        } label: {
                            Label("Privacy & Data", systemImage: "hand.raised")
                        }
                    }
                }
                .padding()
            }
            .background(Color.platformGroupedBackground)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { modelManager.refreshModelStatus() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            DiagnosticsView()
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySheet()
        }
        .sheet(isPresented: $showRAGManagement) {
            RAGManagementView()
        }
        .sheet(isPresented: $showAPISettings) {
            APISettingsView()
        }
    }
}

private struct CardBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.whisperCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.primary.opacity(0.05), radius: 6, x: 0, y: 3)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ModelSelectionCard: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelManager: ModelDownloadManager

    var body: some View {
        CardBackground {
            SectionHeader(title: "Models",
                          subtitle: "Choose the default model and manage on-device assets.")
                .padding(.bottom, 12)

            Picker("Default Model", selection: $settings.selectedModel) {
                ForEach(modelManager.models) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .padding(.bottom, 8)

            Toggle("Offline Mode", isOn: $settings.offlineMode)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                ForEach(modelManager.models) { model in
                    ModelRow(model: model, modelManager: modelManager)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    @ObservedObject var modelManager: ModelDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.notes ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if model.isDownloaded {
                    Label(model.isBundled ? "Bundled" : "Installed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if model.downloadURL != nil {
                    Button(action: { Task { try? await modelManager.downloadModel(model) } }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                } else {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
            }

            if let progress = modelManager.downloadProgress[model.id] {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 12) {
                InfoChip(icon: "shippingbox", text: model.format.rawValue.uppercased())
                InfoChip(icon: "internaldrive", text: model.size)
                InfoChip(icon: "globe", text: model.languageSupport.joined(separator: ", "))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

private struct InfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.quaternaryLabel))
        .clipShape(Capsule())
    }
}

private struct TranscriptionSettingsCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        CardBackground {
            SectionHeader(title: "Transcription",
                          subtitle: "Tune accuracy, speed, and output format preferences.")
                .padding(.bottom, 12)

            Toggle("Translate to English", isOn: $settings.translate)
            Toggle("Auto Language Detect", isOn: $settings.autoLanguageDetect)

            SettingSlider(title: "Temperature",
                           subtitle: "Controls randomness in decoding",
                           value: $settings.temperature,
                           range: 0...1,
                           step: 0.1)

            IntegerStepper(title: "Beam Size", subtitle: "Higher values improve quality at cost of speed", value: $settings.beamSize, range: 1...10)
            IntegerStepper(title: "Best Of", subtitle: "Number of candidates to sample", value: $settings.bestOf, range: 1...10)

            Toggle("Enable VAD", isOn: $settings.vadEnabled)
            Toggle("Enable Diarization", isOn: $settings.diarizeEnabled)
            Toggle("Show Timestamps", isOn: $settings.showTimestamps)
        }
    }
}

private struct RecorderSettingsCard: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var jobManager: JobManager
    @StateObject private var replayKit = ReplayKitCaptureService()

    var body: some View {
        CardBackground {
            SectionHeader(title: "Recorder",
                          subtitle: "Configure countdowns and capture behaviour before audio starts.")
                .padding(.bottom, 12)

            Toggle("Count-in before recording", isOn: $settings.countInEnabled)
                .padding(.bottom, 8)

            if settings.countInEnabled {
                Stepper(value: $settings.countInSeconds, in: 1...5) {
                    Text("Countdown: \(settings.countInSeconds) second\(settings.countInSeconds == 1 ? "" : "s")")
                }
            }

            Toggle("Allow background recording", isOn: $settings.allowBackgroundRecording)
                .padding(.top, 12)
                .toggleStyle(SwitchToggleStyle(tint: .purple))
                .help("Continues recording if the app goes into background. Requires Background Audio entitlement.")

            Toggle("Voice Processing (AEC/Noise Suppression)", isOn: $settings.voiceProcessingEnabled)
                .padding(.top, 8)
                .help("Uses Apple's voice processing I/O (.voiceChat). On supported iOS, may improve speech clarity.")

            Toggle("Capture audio during Apple Native live", isOn: $settings.captureNativeLiveAudio)
                .padding(.top, 8)
                .help("Saves a WAV alongside Apple Native live transcription for later processing.")

            Divider().padding(.vertical, 8)

            SectionHeader(title: "ReplayKit",
                          subtitle: "Capture system audio via broadcast or in-app recording.")
                .padding(.bottom, 8)

            #if targetEnvironment(simulator)
            Text("System Broadcast requires a real device. The Simulator does not support cross-app capture.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
            #endif

            Toggle("Enable ReplayKit Broadcast Extension", isOn: $settings.enableReplayKitBroadcast)
                .help("Adds a Broadcast Extension (system screen recording panel). Audio availability depends on app source and iOS policies.")

            if settings.enableReplayKitBroadcast {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Broadcast (cross‑app)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        ReplayKitPickerView(preferredExtensionBundleId: "com.josephhennig.whispercontrolmobile.broadcast")
                            .frame(width: 52, height: 52)
                        Text("Use Apple's Start/Stop panel to capture audio while using other apps.")
                            .font(.footnote)
                        Spacer()
                        NavigationLink {
                            BroadcastLiveTranscriptView()
                        } label: {
                            Label("Open Live Transcript", systemImage: "text.bubble")
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Toggle("Enable in-app ReplayKit screen record", isOn: $settings.enableReplayKitInAppRecord)
                .help("Start/stop screen recording inside the app. Saved file will be queued for transcription.")

            if settings.enableReplayKitInAppRecord {
                HStack(spacing: 12) {
                    Button(action: {
                        Task { @MainActor in
                            do {
                                try await replayKit.start()
                                NotifyToastManager.shared.show("ReplayKit recording started", icon: "record.circle", style: .info)
                                CaptureStatusCenter.shared.isReplayKitActive = true
                            } catch {
                                NotifyToastManager.shared.show("ReplayKit error: \(error.localizedDescription)", icon: "xmark.octagon", style: .error)
                            }
                        }
                    }) {
                        Label("Start Capture", systemImage: "record.circle")
                    }
                    .disabled(replayKit.isRecording)

                    Button(action: {
                        Task { @MainActor in
                            if let url = await replayKit.stop() {
                                NotifyToastManager.shared.show("Capture saved: \(url.lastPathComponent)", icon: "tray.and.arrow.down", style: .success)
                                _ = await jobManager.addJob(audioURL: url, filename: url.lastPathComponent)
                                CaptureStatusCenter.shared.isReplayKitActive = false
                            } else {
                                NotifyToastManager.shared.show("No capture to save", icon: "info.circle", style: .info)
                            }
                        }
                    }) {
                        Label("Stop & Add to Queue", systemImage: "stop.circle")
                    }
                    .disabled(!replayKit.isRecording)

                    Button(role: .destructive, action: {
                        Task { @MainActor in
                            await replayKit.forceStop()
                            NotifyToastManager.shared.show("ReplayKit force-stopped", icon: "exclamationmark.triangle", style: .warning)
                            CaptureStatusCenter.shared.isReplayKitActive = false
                        }
                    }) {
                        Label("Force Stop", systemImage: "xmark.circle")
                    }
                    .disabled(!replayKit.isActive)
                }
                .padding(.top, 4)

                // Semi-transparent status overlay row
                if replayKit.isActive {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Capturing system audio…")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "waveform")
                        Button("Stop") {
                            NotificationCenter.default.post(name: CaptureStatusCenter.forceStopReplayKitNotification, object: nil)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct SettingSlider: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f", value))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: { newValue in
                value = Double((newValue / step).rounded()) * step
            }), in: range)
        }
    }
}

private struct IntegerStepper: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Stepper(value: $value, in: range) {
                    Text("\(value)")
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct CloudSettingsCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        CardBackground {
            SectionHeader(title: "Cloud Offload",
                          subtitle: "Configure remote providers and automatic fallback policies.")
                .padding(.bottom, 12)

            Picker("Provider", selection: $settings.cloudProvider) {
                Text("OpenAI").tag("openai")
                Text("Gemini").tag("gemini")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                SecureField("OpenAI API Key", text: $settings.openAIAPIKey)
                    .disabled(settings.cloudProvider != "openai")
                    .opacity(settings.cloudProvider == "openai" ? 1 : 0.3)

                SecureField("Gemini API Key", text: $settings.geminiAPIKey)
                    .disabled(settings.cloudProvider != "gemini")
                    .opacity(settings.cloudProvider == "gemini" ? 1 : 0.3)
            }

            Toggle("Enable Cloud Fallback", isOn: $settings.enableCloudFallback)
                .disabled(settings.offlineMode)

            if settings.offlineMode {
                Text("Cloud fallback is disabled while Offline Mode is on.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct AdvancedSettingsCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        CardBackground {
            SectionHeader(title: "Advanced",
                          subtitle: "Optional decoding tweaks and prompts.")
                .padding(.bottom, 12)

            TextField("Suppress Regex", text: $settings.suppressRegex)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            TextField("Initial Prompt", text: $settings.initialPrompt, axis: .vertical)
                .lineLimit(2...4)
        }
    }
}

private struct ResetDefaultsCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        CardBackground {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reset")
                    .font(.headline)
                Text("Restore recommended defaults for all settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(role: .destructive) {
                    settings.resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}

private struct SummaryCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        CardBackground {
            SectionHeader(title: "Overview",
                          subtitle: "Snapshot of active configuration for quick review.")
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(icon: "cpu", label: "Model", value: settings.selectedModel)
                summaryRow(icon: "mic", label: "Recorder", value: settings.countInEnabled ? "Count-in \(settings.countInSeconds)s" : "Instant start")
                summaryRow(icon: "cloud", label: "Cloud", value: cloudSummary)
                summaryRow(icon: "character.cursor.ibeam", label: "Task", value: settings.preferredTask.capitalized)
            }
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }

    private var cloudSummary: String {
        if settings.offlineMode { return "Offline only" }
        let fallbackSuffix = settings.enableCloudFallback ? " + fallback" : ""
        switch settings.cloudProvider {
        case "openai":
            return settings.openAIAPIKey.isEmpty ? "OpenAI (key missing)" : "OpenAI" + fallbackSuffix
        case "gemini":
            return settings.geminiAPIKey.isEmpty ? "Gemini (key missing)" : "Gemini" + fallbackSuffix
        default:
            return "Local"
        }
    }
}

private struct DarkModeSettingsCard: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        CardBackground {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Appearance",
                    subtitle: "Choose your preferred color scheme"
                )
                
                VStack(spacing: 12) {
                    ForEach(DarkModeSetting.allCases, id: \.self) { mode in
                        Button(action: {
                            print("Setting dark mode to: \(mode.rawValue)")
                            withAnimation(.none) {
                                settings.darkMode = mode
                            }
                            print("Dark mode is now: \(settings.darkMode.rawValue)")
                        }) {
                            HStack {
                                Image(systemName: mode.icon)
                                    .foregroundColor(.primary)
                                    .frame(width: 20)
                                
                                Text(mode.displayName)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if settings.darkMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.darkMode == mode ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettings())
            .environmentObject(ModelDownloadManager())
    }
}

// MARK: - Inline RPSystemBroadcastPicker wrapper
import Foundation
#if canImport(ReplayKit)
import ReplayKit
#endif

struct ReplayKitPickerView: UIViewRepresentable {
    let preferredExtensionBundleId: String?

    func makeUIView(context: Context) -> UIView {
        #if canImport(ReplayKit)
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = preferredExtensionBundleId
        picker.showsMicrophoneButton = true
        return picker
        #else
        return UIView()
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        #if canImport(ReplayKit)
        (uiView as? RPSystemBroadcastPickerView)?.preferredExtension = preferredExtensionBundleId
        #endif
    }
}
