import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(title: "Transcribe Anywhere", subtitle: "Record directly in the app or import audio files from Files.", systemImage: "waveform.circle"),
        OnboardingStep(title: "Pick Your Whisper", subtitle: "Download Core ML models for offline use or configure cloud APIs when you need extra accuracy.", systemImage: "cpu"),
        OnboardingStep(title: "Diagnostics Included", subtitle: "Track downloads, exports, and transcription issues from the Diagnostics pane.", systemImage: "doc.text.magnifyingglass"),
        OnboardingStep(title: "Privacy Forward", subtitle: "Recordings stay on your device unless you explicitly enable cloud offload.", systemImage: "hand.raised"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $step) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    OnboardingPage(step: item, isLast: index == steps.count - 1) {
                        advance()
                    }
                    .tag(index)
                }
            }
            #if os(macOS)
            .tabViewStyle(DefaultTabViewStyle())
            #else
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            #endif

            Button("Skip") {
                finish()
            }
            .padding()
        }
        .background(Color.platformSecondaryBackground)
    }

    private func advance() {
        if step >= steps.count - 1 {
            finish()
        } else {
            step += 1
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "WMCHasCompletedOnboarding")
        isPresented = false
    }
}

private struct OnboardingPage: View {
    let step: OnboardingStep
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(systemName: step.systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundColor(.accentColor)
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2)
                    .bold()
                Text(step.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Spacer()

            Button(action: action) {
                Text(isLast ? "Get Started" : "Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Button(action: finish) {
                Text("Skip onboarding")
            }
            .padding(.bottom, 32)
        }
        .padding()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "WMCHasCompletedOnboarding")
    }
}

struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isPresented: .constant(true))
    }
}
