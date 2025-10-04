import SwiftUI
import Combine
import OrderedCollections

@MainActor
final class NotifyToastManager: ObservableObject {
    static let shared = NotifyToastManager()

    @Published private(set) var message: ToastMessage?
    private var messageQueue: OrderedDictionary<UUID, ToastMessage> = [:]
    private var isPresenting = false

    private init() {}

    func prepare() {
        // Future hook for analytics or log uploads
    }

    func show(_ message: String, icon: String = "info.circle", style: ToastMessage.Style = .info) {
        let toast = ToastMessage(text: message, icon: icon, style: style)
        let id = UUID()
        messageQueue[id] = toast
        AnalyticsTracker.shared.record(.toastPresented(style: style))
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard !isPresenting else { return }
        guard !messageQueue.isEmpty else {
            message = nil
            return
        }

        isPresenting = true
        let (id, nextMessage) = messageQueue.removeFirst()
        withAnimation { self.message = nextMessage }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { self.message = nil }
            _ = messageQueue.removeValue(forKey: id)
            isPresenting = false
            presentNextIfNeeded()
        }
    }
}

struct ToastMessage: Equatable {
    enum Style {
        case success, warning, error, info

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    let text: String
    let icon: String
    let style: Style
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.icon)
                .foregroundColor(.white)
            Text(message.text)
                .foregroundColor(.white)
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(message.style.color.opacity(0.9))
        .clipShape(Capsule())
        .shadow(radius: 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
