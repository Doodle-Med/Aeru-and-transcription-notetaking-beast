import SwiftUI
import Combine

struct MainTabView: View {
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "WMCHasCompletedOnboarding")
    @ObservedObject private var toastManager = NotifyToastManager.shared
    @State private var showHelp = false
    @State private var showPrivacy = false
    // Removed in-app splash overlay

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                QueueView()
                    .tabItem {
                        Label("Queue", systemImage: "list.bullet")
                    }

                DatabaseManagementView()
                    .tabItem {
                        Label("Database", systemImage: "externaldrive")
                    }

                AeruContainerView()
                    .tabItem {
                        Label("Aeru", systemImage: "bubble.left.and.bubble.right")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .onAppear {
                toastManager.prepare()
            }
            .overlay(alignment: .top) {
                if let message = toastManager.message {
                    ToastView(message: message)
                        .padding(.top, 40)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showHelp = true }) {
                        Image(systemName: "questionmark.circle")
                    }
                    Button(action: { showPrivacy = true }) {
                        Image(systemName: "hand.raised")
                    }
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpSheet()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacySheet()
            }

            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
            }

            // No in-app splash overlay
            CaptureHUD()
                .padding(.bottom, 18)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.spring(), value: toastManager.message)
    }
}

private struct CaptureHUD: View {
    @StateObject private var center = CaptureStatusCenter.shared
    var body: some View {
        Group {
            if center.isLiveStreaming || center.isReplayKitActive {
                HStack(spacing: 12) {
                    Image(systemName: center.isLiveStreaming ? "waveform" : "rectangle.on.rectangle.angled")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(center.isLiveStreaming ? "Live transcription running" : "ReplayKit capturing")
                            .font(.subheadline).bold().foregroundColor(.white)
                        Text("Tap Stop to end")
                            .font(.caption2).foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    if center.isLiveStreaming {
                        Button("Stop") {
                            NotificationCenter.default.post(name: CaptureStatusCenter.stopLiveNotification, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    if center.isReplayKitActive {
                        Button("Stop") {
                            NotificationCenter.default.post(name: CaptureStatusCenter.forceStopReplayKitNotification, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: center.isLiveStreaming)
        .animation(.spring(), value: center.isReplayKitActive)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
