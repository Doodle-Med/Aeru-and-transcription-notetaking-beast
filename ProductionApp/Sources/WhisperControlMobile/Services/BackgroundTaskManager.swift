import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages background task execution within iOS 30-second limit
/// Handles graceful degradation when app moves to background
@MainActor
final class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()
    
    @Published private(set) var isInBackground = false
    @Published private(set) var remainingBackgroundTime: TimeInterval = 0
    
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var backgroundTimeCheckTask: Task<Void, Never>?
    
    private init() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        setupNotifications()
        #endif
    }
    
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        isInBackground = true
        AppLogger.log("[BACKGROUND] App entered background", category: AppLogger.job, level: .info)
    }
    
    @objc private func appWillEnterForeground() {
        isInBackground = false
        endBackgroundTask()
        AppLogger.log("[BACKGROUND] App returning to foreground", category: AppLogger.job, level: .info)
    }
    #endif
    
    /// Begin background task with automatic expiration handling
    /// Returns false if background tasks not available (macOS) or already running
    func beginBackgroundTask(name: String = "Transcription") -> Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        guard backgroundTaskID == .invalid else {
            AppLogger.log("[BACKGROUND] Task already running", category: AppLogger.job, level: .debug)
            return false
        }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.handleExpiration()
            }
        }
        
        guard backgroundTaskID != .invalid else {
            AppLogger.log("[BACKGROUND] Failed to start background task", category: AppLogger.job, level: .error)
            return false
        }
        
        AppLogger.log("[BACKGROUND] Started background task: \(name)", category: AppLogger.job, level: .info)
        startBackgroundTimeMonitoring()
        return true
        #else
        return false  // macOS doesn't need background tasks
        #endif
    }
    
    /// End background task and cleanup
    func endBackgroundTask() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        guard backgroundTaskID != .invalid else { return }
        
        backgroundTimeCheckTask?.cancel()
        backgroundTimeCheckTask = nil
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        remainingBackgroundTime = 0
        
        AppLogger.log("[BACKGROUND] Ended background task", category: AppLogger.job, level: .info)
        #endif
    }
    
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    private func startBackgroundTimeMonitoring() {
        backgroundTimeCheckTask?.cancel()
        
        backgroundTimeCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    guard let self else { return }
                    self.remainingBackgroundTime = UIApplication.shared.backgroundTimeRemaining
                    
                    // Warn when approaching expiration
                    if self.remainingBackgroundTime < 5 && self.remainingBackgroundTime > 0 {
                        AppLogger.log("[BACKGROUND] Time remaining: \(String(format: "%.1fs", self.remainingBackgroundTime))", category: AppLogger.job, level: .info)
                    }
                }
            }
        }
    }
    
    private func handleExpiration() {
        AppLogger.log("[BACKGROUND] Task expiring - cleanup initiated", category: AppLogger.job, level: .info)
        
        // Post notification for JobManager to pause processing
        NotificationCenter.default.post(name: .backgroundTaskExpiring, object: nil)
        
        endBackgroundTask()
    }
    #endif
    
}

extension Notification.Name {
    static let backgroundTaskExpiring = Notification.Name("BackgroundTaskExpiring")
}
