import SwiftUI

struct AnalyticsPanel: View {
    @ObservedObject var tracker: AnalyticsTracker = .shared

    var body: some View {
        PanelContainer {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Diagnostics", subtitle: "Recent activity across jobs, downloads, and toasts.")

                metricsGrid
                recentEvents
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
            MetricCell(title: "Jobs Completed", value: tracker.metrics.jobsCompleted, systemIcon: "checkmark.circle.fill", color: .green)
            MetricCell(title: "Jobs Failed", value: tracker.metrics.jobsFailed, systemIcon: "xmark.octagon.fill", color: .red)
            MetricCell(title: "Model Downloads", value: tracker.metrics.modelDownloads, systemIcon: "arrow.down.circle.fill", color: .blue)
            MetricCell(title: "Cloud Fallbacks", value: tracker.metrics.cloudFallbacks, systemIcon: "cloud.fill", color: .purple)
        }
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)

            if tracker.recentEvents.isEmpty {
                #if os(macOS)
                Text("No recent analytics")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                #else
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No recent analytics",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Complete a transcription or download a model to populate activity.")
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .imageScale(.large)
                            .foregroundColor(.secondary)
                        Text("No recent analytics")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Complete a transcription or download a model to populate activity.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
                #endif
            } else {
                ForEach(tracker.recentEvents.suffix(6)) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "dot.radiowaves.up.forward")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.event.description)
                                .font(.subheadline)
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.platformSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

private struct PanelContainer<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.platformSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    }
}

private struct PanelHeader: View {
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

private struct MetricCell: View {
    let title: String
    let value: Int
    let systemIcon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemIcon)
                .labelStyle(.titleAndIcon)
                .foregroundColor(color)
                .font(.subheadline)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
