import Foundation

@MainActor
final class StreamingDelegateProxy: StreamingEngineDelegate {
    let onPartial: (String) -> Void
    let onFinal: (String) -> Void
    let onConfidence: (Float) -> Void
    let onStop: () -> Void
    let onError: (Error) -> Void
    let onAudioCaptureStarted: (URL) -> Void

    init(onPartial: @escaping (String) -> Void,
         onFinal: @escaping (String) -> Void,
         onConfidence: @escaping (Float) -> Void,
         onStop: @escaping () -> Void,
         onError: @escaping (Error) -> Void,
         onAudioCaptureStarted: @escaping (URL) -> Void) {
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onConfidence = onConfidence
        self.onStop = onStop
        self.onError = onError
        self.onAudioCaptureStarted = onAudioCaptureStarted
    }

    func streamingEngine(didEmitPartial text: String) { onPartial(text) }
    func streamingEngine(didEmitFinal text: String) { onFinal(text) }
    func streamingEngine(didUpdateConfidence value: Float) { onConfidence(value) }
    func streamingEngineDidStop() { onStop() }
    func streamingEngine(didError error: Error) { onError(error) }
    func streamingEngine(didStartAudioCapture url: URL) { onAudioCaptureStarted(url) }
}

