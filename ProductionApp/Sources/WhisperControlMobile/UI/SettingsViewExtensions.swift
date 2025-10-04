import SwiftUI

/// UI polish extensions for Settings view
/// Provides better grouping and Mac adaptations
extension SettingsView {
    
    /// Grouped settings sections with better visual organization
    struct SettingsGroup<Content: View>: View {
        let title: String
        let icon: String?
        let content: Content
        
        init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.icon = icon
            self.content = content()
        }
        
        var body: some View {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(.accentColor)
                    }
                    Text(title)
                        .font(.headline)
                }
                .padding(.bottom, 4)
                
                content
                    .padding(.leading, icon != nil ? 24 : 0)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            #else
            Section {
                content
            } header: {
                if let icon = icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            #endif
        }
    }
    
    /// Platform-adaptive picker
    struct AdaptivePicker<SelectionValue: Hashable, Content: View>: View {
        let title: String
        @Binding var selection: SelectionValue
        let content: Content
        
        init(
            _ title: String,
            selection: Binding<SelectionValue>,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self._selection = selection
            self.content = content()
        }
        
        var body: some View {
            #if os(macOS)
            HStack {
                Text(title)
                Spacer()
                Picker("", selection: $selection) {
                    content
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            #else
            Picker(title, selection: $selection) {
                content
            }
            #endif
        }
    }
    
    /// Storage usage indicator
    struct StorageUsageView: View {
        let usage: StorageUsage
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage Usage")
                    .font(.headline)
                
                usageRow(label: "Recordings", bytes: usage.recordings, color: .blue)
                usageRow(label: "Exports", bytes: usage.exports, color: .green)
                usageRow(label: "Cache", bytes: usage.caches, color: .orange)
                
                Divider()
                
                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: usage.total, countStyle: .file))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        
        private func usageRow(label: String, bytes: Int64, color: Color) -> some View {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .foregroundColor(.primary)
            }
        }
    }
    
    /// Cleanup controls
    struct CleanupControls: View {
        let onCleanupCache: () -> Void
        let onCleanupAll: () -> Void
        
        var body: some View {
            VStack(spacing: 12) {
                Button(action: onCleanupCache) {
                    Label("Clean Cache", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive, action: onCleanupAll) {
                    Label("Clean All Temporary Files", systemImage: "trash.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#if os(macOS)
/// Mac-specific keyboard shortcuts for Settings
extension View {
    func settingsKeyboardShortcuts() -> some View {
        self
            .keyboardShortcut(",", modifiers: .command) // Cmd+, opens settings (standard)
    }
}
#endif
