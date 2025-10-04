import SwiftUI
import AVFoundation
import UIKit

struct QueueView: View {
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var jobManager: JobManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var modelManager: ModelDownloadManager
    @State private var showRecorder = false
    @State private var showFilePicker = false
    @State private var showSettingsSheet = false
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var showDiagnostics = false
    @State private var searchText = ""
    @State private var selectedTag: LibraryTag? = nil
    @State private var selectedJobs: Set<UUID> = []
    @State private var showLibrary = false
    @State private var showHelp = false
    @State private var detailJob: TranscriptionJob?
    @State private var showLiveTranscription = false
    @State private var isImporting = false

    // Library sorting & date filtering
    private enum LibrarySort: String, CaseIterable, Identifiable {
        case dateNewest = "Date: Newest"
        case dateOldest = "Date: Oldest"
        case durationAsc = "Duration: Shortest"
        case durationDesc = "Duration: Longest"
        case typeAZ = "Type: A→Z"
        case typeZA = "Type: Z→A"
        var id: String { rawValue }
    }
    @State private var librarySort: LibrarySort = .dateNewest
    @State private var fromDate: Date? = nil
    @State private var toDate: Date? = nil

    private var queuedJobsQueue: [TranscriptionJob] {
        jobManager.jobs.filter { $0.status == .queued }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeJobsQueue: [TranscriptionJob] {
        jobManager.jobs.filter { $0.status == .transcribing || $0.status == .recording }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var failedJobsQueue: [TranscriptionJob] {
        jobManager.jobs.filter { $0.status == .failed }
    }

    private var filteredJobs: [TranscriptionJob] {
        // Completed only
        var items = jobManager.jobs.filter { job in
            guard job.status == .completed else { return false }
            let matchesSearch = searchText.isEmpty || job.filename.lowercased().contains(searchText.lowercased()) || (job.result?.text.lowercased().contains(searchText.lowercased()) ?? false)
            let matchesTag = selectedTag?.matches(job: job) ?? true
            // Date range
            let matchesFrom = fromDate.map { job.createdAt >= $0 } ?? true
            let matchesTo = toDate.map { job.createdAt <= $0 } ?? true
            return matchesSearch && matchesTag && matchesFrom && matchesTo
        }

        // Sort
        switch librarySort {
        case .dateNewest:
            items.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            items.sort { $0.createdAt < $1.createdAt }
        case .durationAsc:
            items.sort { ($0.duration ?? 0) < ($1.duration ?? 0) }
        case .durationDesc:
            items.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .typeAZ:
            items.sort { ($0.stage ?? "").localizedCaseInsensitiveCompare($1.stage ?? "") == .orderedAscending }
        case .typeZA:
            items.sort { ($0.stage ?? "").localizedCaseInsensitiveCompare($1.stage ?? "") == .orderedDescending }
        }
        return items
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 16) {
                    Picker("View", selection: $showLibrary.animation()) {
                        Text("Queue").tag(false)
                        Text("Library").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if showLibrary {
                        libraryView
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        queueView
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .navigationTitle(showLibrary ? "Transcription Library" : "Transcription Queue")

                // Removed global blocking overlay per user feedback
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { showSettingsSheet.toggle() }) {
                        Image(systemName: "gearshape.fill")
                    }
                    Button(action: { showDiagnostics = true }) {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if showLibrary {
                        EditButton()
                    }
                    Menu {
                        Button {
                            showRecorder = true
                        } label: {
                            Label("Record Audio", systemImage: "mic.fill")
                        }

                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Import Files", systemImage: "tray.and.arrow.down")
                        }
                        
                        Button {
                            showLiveTranscription = true
                        } label: {
                            Label("Live Transcription", systemImage: "waveform")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Add to queue")
                }
            }
            .sheet(isPresented: $showRecorder) {
                AudioRecorderView()
                    .environmentObject(jobManager)
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(modelManager)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .sheet(isPresented: $showHelp) {
                HelpSheet()
            }
            .sheet(isPresented: $showLiveTranscription) {
                LiveTranscriptionView()
                    .environmentObject(settings)
                    .environmentObject(modelManager)
            }
            .sheet(item: $detailJob) { job in
                TranscriptDetailView(job: job)
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    isImporting = true
                    Task {
                        for url in urls {
                            await enqueue(url: url)
                        }
                        await MainActor.run { isImporting = false }
                    }
                case .failure(let error):
                    alertMessage = "File import error: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: showRecorder) { newValue in
                if newValue {
                    enableRecordingSession()
                }
            }
        }
        .animation(.spring(), value: jobManager.jobs.count)
    }

    private func enableRecordingSession() {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker]
        if #available(iOS 17.0, *) {
            options.insert(.allowBluetoothHFP)
        }
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: options)
        try? session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func enqueue(url: URL) async {
        await jobManager.addJob(audioURL: url, filename: url.lastPathComponent)
        NotifyToastManager.shared.show("Added \(url.lastPathComponent) to queue", icon: "plus.circle", style: .info)
    }

    private func retry(job: TranscriptionJob) async {
        jobManager.retryJob(id: job.id)
        NotifyToastManager.shared.show("Retrying \(job.filename)", icon: "arrow.counterclockwise", style: .info)
    }

    private func delete(job: TranscriptionJob) {
        jobManager.removeJob(id: job.id)
        NotifyToastManager.shared.show("Deleted \(job.filename)", icon: "trash", style: .warning)
    }

    private func export(job: TranscriptionJob, format: ExportFormat) async {
        guard let result = job.result else { return }

        do {
            try await ExportCoordinator.shared.share(result: result, format: format, filename: job.filename)
            NotifyToastManager.shared.show("Shared \(job.filename) as \(format.displayName)", icon: "square.and.arrow.up", style: .success)
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            NotifyToastManager.shared.show("Export failed: \(error.localizedDescription)", icon: "xmark.octagon", style: .error)
            showErrorAlert = true
        }
    }

    private var queueView: some View {
        VStack(spacing: 16) {
            QueueSummaryBar(queued: queuedJobsQueue.count,
                             active: activeJobsQueue.count,
                             completed: jobManager.jobs.filter { $0.status == .completed }.count)
                .padding(.horizontal)

            QueueActionBar(
                recordAction: { showRecorder = true },
                importAction: { showFilePicker = true },
                liveTranscriptionAction: { showLiveTranscription = true }
            )
            .padding(.horizontal)

            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Importing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if jobManager.jobs.isEmpty {
                QueueEmptyState(recordAction: { showRecorder.toggle() }, importAction: { showFilePicker.toggle() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                List {
                    if !queuedJobsQueue.isEmpty {
                        Section("Queued") {
                            ForEach(queuedJobsQueue) { job in
                                JobRow(job: job, onRetry: {
                                    Task { await retry(job: job) }
                                }, onShare: { format in
                                    Task { await export(job: job, format: format) }
                                }, onDelete: {
                                    delete(job: job)
                                }, onTap: {
                                    detailJob = job
                                })
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    if !activeJobsQueue.isEmpty {
                        Section("In Progress") {
                            ForEach(activeJobsQueue) { job in
                                JobRow(job: job, onRetry: {}, onShare: { _ in }, onDelete: {
                                    delete(job: job)
                                }, onTap: {
                                    detailJob = job
                                })
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    let completedJobs = jobManager.jobs.filter { $0.status == .completed }
                        .sorted { $0.createdAt > $1.createdAt }
                    if !completedJobs.isEmpty {
                        Section("Last Completed") {
                            ForEach(completedJobs.prefix(5)) { job in
                                JobRow(job: job, onRetry: {}, onShare: { format in
                                    Task { await export(job: job, format: format) }
                                }, onDelete: {
                                    delete(job: job)
                                }, onTap: {
                                    detailJob = job
                                })
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            if completedJobs.count > 5 {
                                Button("View Library") {
                                    withAnimation { showLibrary = true }
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !failedJobsQueue.isEmpty {
                        Section("Failed") {
                            ForEach(failedJobsQueue) { job in
                                JobRow(job: job, onRetry: {
                                    Task { await retry(job: job) }
                                }, onShare: { _ in }, onDelete: {
                                    delete(job: job)
                                }, onTap: {
                                    detailJob = job
                                })
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .transition(.opacity)
            }
        }
    }

    private var libraryView: some View {
        VStack(spacing: 16) {
            LibraryFilterBar(searchText: $searchText, selectedTag: $selectedTag)
                .padding(.horizontal)

            // Controls row for Library filters
            HStack(spacing: 12) {
                Menu {
                    Picker("Sort", selection: $librarySort) {
                        ForEach(LibrarySort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                } label: {
                    Label(librarySort.rawValue, systemImage: "arrow.up.arrow.down")
                }

                // From date
                DatePicker(
                    "From",
                    selection: Binding<Date>(
                        get: { fromDate ?? Date.distantPast },
                        set: { fromDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()

                // To date
                DatePicker(
                    "To",
                    selection: Binding<Date>(
                        get: { toDate ?? Date.distantFuture },
                        set: { toDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()

                if fromDate != nil || toDate != nil {
                    Button {
                        fromDate = nil; toDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear date filters")
                }
                Spacer()
            }
            .padding(.horizontal)

            if filteredJobs.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView("No completed jobs", systemImage: "archivebox", description: Text("Transcribe something first, then return to manage history."))
                        .padding()
                } else {
                    VStack {
                        Image(systemName: "archivebox")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No completed jobs")
                            .font(.headline)
                        Text("Transcribe something first, then return to manage history.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 0) {
                    // Action buttons bar - moved from bottom toolbar
                    libraryActionBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    
                    List(selection: $selectedJobs) {
                        ForEach(filteredJobs) { job in
                            LibraryRow(job: job)
                                .tag(job.id)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.bottom, 80) // Add bottom padding to avoid navigation overlap
                }
            }
        }
    }

    // New action bar view - moved from bottom toolbar to avoid navigation overlap
    private var libraryActionBar: some View {
        HStack(spacing: 12) {
            Button("Export Selected") {
                Task { await exportSelectedJobs() }
            }
            .disabled(selectedJobs.isEmpty)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()

            Menu("Actions") {
                Button("Select All") {
                    selectedJobs = Set(filteredJobs.map { $0.id })
                }
                Button("Deselect All") {
                    selectedJobs.removeAll()
                }
                Button("Delete Selected", role: .destructive) {
                    deleteSelectedJobs()
                }
                Button("Share Diagnostics") {
                    showDiagnostics = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // Selection count indicator
            if !selectedJobs.isEmpty {
                Text("\(selectedJobs.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func exportSelectedJobs() async {
        let jobsToExport = filteredJobs.filter { selectedJobs.contains($0.id) }
        guard !jobsToExport.isEmpty else { return }

        let filename = "transcripts-\(Date().formatted(.dateTime.year().month().day().hour().minute()))"
        let archiveURL = StorageManager.exportsDirectory.appendingPathComponent(filename).appendingPathExtension("zip")

        do {
            let outputURL = try ExportService().archive(jobs: jobsToExport, to: archiveURL)
            let activity = UIActivityViewController(activityItems: [outputURL], applicationActivities: nil)
            activity.excludedActivityTypes = [.assignToContact, .addToReadingList]
            if let presenter = UIApplication.shared.topViewController() {
                await MainActor.run {
                    presenter.present(activity, animated: true)
                }
            }
            NotifyToastManager.shared.show("Exported \(jobsToExport.count) jobs", icon: "folder.zip", style: .success)
            selectedJobs.removeAll()
        } catch {
            NotifyToastManager.shared.show("Bulk export failed: \(error.localizedDescription)", icon: "xmark.octagon", style: .error)
        }
    }

    private func deleteSelectedJobs() {
        guard !selectedJobs.isEmpty else { return }
        selectedJobs.forEach { jobManager.removeJob(id: $0) }
        let count = selectedJobs.count
        selectedJobs.removeAll()
        NotifyToastManager.shared.show("Deleted \(count) jobs", icon: "trash", style: .warning)
    }
}

private enum LibraryTag: String, CaseIterable {
    case local = "Local"
    case cloud = "Cloud"
    case fallback = "Fallback"

    func matches(job: TranscriptionJob) -> Bool {
        switch self {
        case .local:
            return job.stage == "completed" || job.stage == "transcribing"
        case .cloud:
            return job.stage == "cloud-openai" || job.stage == "cloud-gemini"
        case .fallback:
            return job.stage == "fallback"
        }
    }
}

private struct LibraryFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedTag: LibraryTag?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search transcripts", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "All", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(LibraryTag.allCases, id: \.rawValue) { tag in
                        FilterChip(label: tag.rawValue, isSelected: selectedTag == tag) {
                            selectedTag = tag
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct QueueActionBar: View {
    let recordAction: () -> Void
    let importAction: () -> Void
    let liveTranscriptionAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: recordAction) {
                Label("Record", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(action: importAction) {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.bordered)
            
            Button(action: liveTranscriptionAction) {
                Label("Live", systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Spacer()
        }
    }
}

private struct LibraryRow: View {
    let job: TranscriptionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.filename)
                        .font(.headline)
                    Text(job.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let stage = job.stage {
                    StageBadge(stage: stage)
                }
            }

            if let duration = job.duration {
                Text("Duration: \(formatDuration(duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let text = job.result?.text {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}

private struct JobRow: View {
    let job: TranscriptionJob
    let onRetry: () -> Void
    let onShare: (ExportFormat) -> Void
    let onDelete: () -> Void
    var onTap: (() -> Void)? = nil

    @State private var isExpanded = false
    @StateObject private var audioPlayback = AudioPlaybackService()
    @State private var isLoadingAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.filename)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(job.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let stage = job.stage {
                        StageBadge(stage: stage)
                    }
                }
                Spacer()
                StatusBadge(status: job.status)
            }
            .padding(.bottom, 6)

            if job.status == .transcribing || job.status == .recording {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .animation(.easeInOut(duration: 0.3), value: job.progress)
            }

            if let error = job.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let result = job.result {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.text)
                        .font(.subheadline)
                        .lineLimit(isExpanded ? nil : 2)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                isExpanded.toggle()
                            }
                        }
                    
                    HStack {
                        if let duration = job.duration {
                            Text("Duration: \(formatDuration(duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Audio playback button
                        Button(action: {
                            if audioPlayback.url == job.originalURL {
                                if audioPlayback.isPlaying {
                                    audioPlayback.pause()
                                } else {
                                    audioPlayback.play()
                                }
                            } else {
                                isLoadingAudio = true
                                audioPlayback.load(url: job.originalURL)
                                // Poll briefly until duration becomes available, then clear spinner and play
                                Task { @MainActor in
                                    let deadline = Date().addingTimeInterval(1.0)
                                    while Date() < deadline {
                                        try? await Task.sleep(nanoseconds: 50_000_000)
                                        if audioPlayback.duration > 0 {
                                            break
                                        }
                                    }
                                    isLoadingAudio = false
                                    audioPlayback.play()
                                }
                            }
                        }) {
                            if isLoadingAudio && audioPlayback.url != job.originalURL {
                                ProgressView().scaleEffect(0.9)
                            } else {
                                Image(systemName: audioPlayback.url == job.originalURL && audioPlayback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                            }
                        }
                        .buttonStyle(.plain)

                        // Seek slider with time labels
                        if audioPlayback.url == job.originalURL {
                            VStack(alignment: .leading, spacing: 2) {
                                Slider(value: Binding(
                                    get: {
                                        audioPlayback.duration > 0 ? audioPlayback.currentTime / max(audioPlayback.duration, 0.0001) : 0
                                    },
                                    set: { newVal in
                                        let t = newVal * max(audioPlayback.duration, 0.0001)
                                        audioPlayback.seek(to: t)
                                    }
                                ))
                                HStack {
                                    Text(formatDuration(audioPlayback.currentTime))
                                        .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatDuration(audioPlayback.duration))
                                        .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                                }
                            }
                            .frame(minWidth: 140)
                        }
                    }
                }
            }

            HStack {
                if job.status == .failed {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }

                Spacer()

                if job.status == .completed {
                    Menu("Export") {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Button(format.displayName) {
                                onShare(format)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .animation(.spring(), value: job.status)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            if job.status == .failed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct StatusBadge: View {
    let status: TranscriptionJob.Status

    var body: some View {
        Text(statusText)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var statusText: String { status.rawValue.capitalized }

    private var color: Color {
        switch status {
        case .queued: return .orange
        case .recording, .transcribing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

private struct StageBadge: View {
    let stage: String

    var body: some View {
        Label(stageDescription(stage), systemImage: stageIcon(stage))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stageColor(stage).opacity(0.15))
            .foregroundColor(stageColor(stage))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: stage)
    }
}

private func stageDescription(_ stage: String) -> String {
    switch stage {
    case "preparing": return "Preparing audio"
    case "queued": return "Queued"
    case "transcribing": return "Transcribing"
    case "cloud-openai": return "Uploading to OpenAI"
    case "cloud-gemini": return "Uploading to Gemini"
    case "fallback": return "On-device fallback"
    case "completed": return "Completed"
    case "cancelled": return "Cancelled"
    case "error": return "Error"
    default: return stage.capitalized
    }
}

private func stageIcon(_ stage: String) -> String {
    switch stage {
    case "preparing": return "waveform"
    case "queued": return "clock"
    case "transcribing": return "text.magnifyingglass"
    case "cloud-openai", "cloud-gemini": return "cloud"
    case "fallback": return "aqi.medium"
    case "completed": return "checkmark.circle"
    case "cancelled": return "xmark.circle"
    case "error": return "exclamationmark.triangle"
    default: return "info.circle"
    }
}

private func stageColor(_ stage: String) -> Color {
    switch stage {
    case "preparing": return .purple
    case "queued": return .orange
    case "transcribing": return .blue
    case "cloud-openai": return .teal
    case "cloud-gemini": return .indigo
    case "fallback": return .pink
    case "completed": return .green
    case "cancelled": return .gray
    case "error": return .red
    default: return .gray
    }
}

private struct QueueSummaryBar: View {
    let queued: Int
    let active: Int
    let completed: Int

    var body: some View {
        HStack(spacing: 12) {
            SummaryPill(title: "Queued", count: queued, color: .orange)
            SummaryPill(title: "Active", count: active, color: .blue)
            SummaryPill(title: "Done", count: completed, color: .green)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QueueEmptyState: View {
    let recordAction: () -> Void
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundColor(.blue)
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            Text("No transcriptions yet")
                .font(.title3)
                .bold()
            Text("Record something or import audio to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button(action: recordAction) {
                    Label("Record", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: importAction) {
                    Label("Import", systemImage: "folder.fill.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct QueueView_Previews: PreviewProvider {
    static var previews: some View {
        QueueView()
            .environmentObject(JobStore())
            .environmentObject(AppSettings())
            .environmentObject(ModelDownloadManager())
            .environmentObject(JobManager(jobStore: JobStore(), settings: AppSettings(), modelManager: ModelDownloadManager()))
    }
}
