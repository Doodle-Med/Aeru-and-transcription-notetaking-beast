import SwiftUI

struct TranscriptDetailView: View {
    let job: TranscriptionJob
    @State private var expandedSegments: Bool = false
    // Temporarily disabled until the playback service is fully wired into the project target
    // @StateObject private var player = AudioPlaybackService()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Divider()
                    // audioPlaybackSection
                    Divider()
                    summary
                    if let result = job.result {
                        segmentSection(result: result)
                    }
                }
                .padding()
            }
            .navigationTitle(job.filename)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Hook up export actions here if desired
                        Button("Export") {
                            // TODO: Implement export functionality
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = job.createdAt as Date? {
                Text(date.formatted(date: .long, time: .shortened))
                    .font(.headline)
            }
            if let duration = job.duration {
                Text("Duration: \(formatDuration(duration))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let stage = job.stage {
                Text("Stage: \(stage.capitalized)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.title3)
                .bold()
            if let text = job.result?.text {
                Text(text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                Text("No transcript has been generated yet.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func segmentSection(result: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segments")
                    .font(.title3)
                    .bold()
                Spacer()
                Button(expandedSegments ? "Collapse" : "Expand") {
                    withAnimation {
                        expandedSegments.toggle()
                    }
                }
                .font(.caption)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(formatDuration(segment.start)) - \(formatDuration(segment.end))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(segment.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxHeight: expandedSegments ? .infinity : 200)
            .clipped()
            if !expandedSegments {
                Text("Tap Expand to view all segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /*
    private var audioPlaybackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Playback")
                .font(.title3)
                .bold()
            
            if let audioURL = job.originalURL ?? job.sourceURL {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button(action: {
                            if player.url != audioURL { 
                                player.load(url: audioURL) 
                            }
                            player.isPlaying ? player.pause() : player.play()
                        }) {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                        .accessibilityIdentifier("transcript_playback_button")
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(formatDuration(player.currentTime)) / \(formatDuration(player.duration))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            
                            Slider(value: Binding(
                                get: { player.duration > 0 ? player.currentTime / max(player.duration, 0.0001) : 0 },
                                set: { player.seek(to: $0 * max(player.duration, 0.0001)) }
                            ))
                            .accessibilityIdentifier("transcript_playback_slider")
                        }
                    }
                    
                    if player.duration > 0 {
                        HStack {
                            Text("Duration: \(formatDuration(player.duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if player.isPlaying {
                                Text("Playing...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear {
                    if player.url != audioURL {
                        player.load(url: audioURL)
                    }
                }
            } else {
                Text("No audio file available for playback")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    */

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}
