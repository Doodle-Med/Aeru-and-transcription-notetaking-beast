
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var url: URL?

    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?
    private var tickTimer: Timer?
    #endif

    func load(url: URL) {
        self.url = url
        #if canImport(AVFoundation)
        stop()
        do {
            let data = try Data(contentsOf: url)
            player = try AVAudioPlayer(data: data)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
        } catch {
            print("[PLAYBACK] load failed: \(error.localizedDescription)")
        }
        #endif
    }

    func play() {
        #if canImport(AVFoundation)
        guard let player else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PLAYBACK] session error: \(error.localizedDescription)")
        }
        #endif
        player.play()
        isPlaying = true
        startTick()
        #endif
    }

    func pause() {
        #if canImport(AVFoundation)
        player?.pause()
        isPlaying = false
        stopTick()
        #endif
    }

    func stop() {
        #if canImport(AVFoundation)
        player?.stop()
        player = nil
        isPlaying = false
        stopTick()
        currentTime = 0
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) } catch {}
        #endif
        #endif
    }

    func seek(to time: TimeInterval) {
        #if canImport(AVFoundation)
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        #endif
    }

    #if canImport(AVFoundation)
    private func startTick() {
        stopTick()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = self.player?.currentTime ?? 0
                if let p = self.player, !p.isPlaying {
                    self.isPlaying = false
                    self.stopTick()
                }
            }
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
    #endif
}


