import Foundation

@MainActor
protocol StreamingEngineDelegate: AnyObject {
    func streamingEngine(didEmitPartial text: String)
    func streamingEngine(didEmitFinal text: String)
    func streamingEngine(didUpdateConfidence value: Float)
    func streamingEngineDidStop()
    func streamingEngine(didError error: Error)
    func streamingEngine(didStartAudioCapture url: URL)
}

@MainActor
protocol StreamingEngine: AnyObject {
    var delegate: StreamingEngineDelegate? { get set }
    func start(localeIdentifier: String?) async throws
    func stop()
}
