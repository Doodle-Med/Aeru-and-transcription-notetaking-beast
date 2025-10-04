import Foundation

/// Manages storage cleanup policies for app data
/// Separates critical data (Documents) from cache (Caches/tmp)
enum StorageCleanupManager {
    
    /// Storage location classifications
    enum StorageLocation {
        case documents      // User data, backed up, never auto-deleted
        case caches        // Temporary, system can purge
        case temporary     // Truly temporary, cleaned on launch
        
        var directory: URL {
            let fm = FileManager.default
            switch self {
            case .documents:
                return fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            case .caches:
                return fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            case .temporary:
                return fm.temporaryDirectory
            }
        }
    }
    
    /// Cleanup policy for different data types
    struct CleanupPolicy {
        let maxAge: TimeInterval?       // Max age before deletion (nil = never delete by age)
        let maxTotalSize: Int64?        // Max total size in bytes (nil = unlimited)
        let location: StorageLocation
        
        static let transcripts = CleanupPolicy(
            maxAge: nil,                 // Keep forever
            maxTotalSize: nil,
            location: .documents
        )
        
        static let preparedAudio = CleanupPolicy(
            maxAge: 7 * 24 * 60 * 60,   // 7 days
            maxTotalSize: 500 * 1024 * 1024,  // 500MB
            location: .caches
        )
        
        static let originalRecordings = CleanupPolicy(
            maxAge: 30 * 24 * 60 * 60,  // 30 days
            maxTotalSize: 1024 * 1024 * 1024,  // 1GB
            location: .documents
        )
        
        static let temporaryFiles = CleanupPolicy(
            maxAge: 24 * 60 * 60,       // 1 day
            maxTotalSize: nil,
            location: .temporary
        )
    }
    
    /// Clean storage according to policy
    static func performCleanup(policy: CleanupPolicy, in directory: URL) {
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            AppLogger.log("[CLEANUP] Failed to enumerate \(directory.lastPathComponent)", category: AppLogger.storage, level: .error)
            return
        }
        
        var files: [(url: URL, date: Date, size: Int64)] = []
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = resourceValues.contentModificationDate,
                  let size = resourceValues.fileSize else {
                continue
            }
            
            files.append((fileURL, modDate, Int64(size)))
        }
        
        var deletedCount = 0
        var deletedBytes: Int64 = 0
        
        // Age-based cleanup
        if let maxAge = policy.maxAge {
            let cutoffDate = Date().addingTimeInterval(-maxAge)
            let oldFiles = files.filter { $0.date < cutoffDate }
            
            for file in oldFiles {
                do {
                    try fm.removeItem(at: file.url)
                    deletedCount += 1
                    deletedBytes += file.size
                    AppLogger.log("[CLEANUP] Deleted old file: \(file.url.lastPathComponent) (age: \(Date().timeIntervalSince(file.date) / 86400) days)", category: AppLogger.storage, level: .debug)
                } catch {
                    AppLogger.log("[CLEANUP] Failed to delete \(file.url.lastPathComponent): \(error)", category: AppLogger.storage, level: .error)
                }
            }
            
            // Remove deleted files from list
            files.removeAll { file in oldFiles.contains(where: { $0.url == file.url }) }
        }
        
        // Size-based cleanup (delete oldest files first until under limit)
        if let maxSize = policy.maxTotalSize {
            let totalSize = files.reduce(0) { $0 + $1.size }
            
            if totalSize > maxSize {
                let sortedByAge = files.sorted { $0.date < $1.date }
                var currentSize = totalSize
                
                for file in sortedByAge {
                    guard currentSize > maxSize else { break }
                    
                    do {
                        try fm.removeItem(at: file.url)
                        currentSize -= file.size
                        deletedCount += 1
                        deletedBytes += file.size
                        AppLogger.log("[CLEANUP] Deleted for size: \(file.url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)))", category: AppLogger.storage, level: .debug)
                    } catch {
                        AppLogger.log("[CLEANUP] Failed to delete \(file.url.lastPathComponent): \(error)", category: AppLogger.storage, level: .error)
                    }
                }
            }
        }
        
        if deletedCount > 0 {
            AppLogger.log("[CLEANUP] Cleaned \(directory.lastPathComponent): deleted \(deletedCount) files (\(ByteCountFormatter.string(fromByteCount: deletedBytes, countStyle: .file)))", category: AppLogger.storage, level: .info)
        }
    }
    
    /// Run all cleanup policies
    static func performAllCleanup() {
        AppLogger.log("[CLEANUP] Starting automatic cleanup", category: AppLogger.storage, level: .info)
        
        // Clean prepared audio (in caches)
        let preparedAudioDir = StorageManager.recordingsDirectory
        performCleanup(policy: .preparedAudio, in: preparedAudioDir)
        
        // Clean temporary files
        let tempDir = FileManager.default.temporaryDirectory
        performCleanup(policy: .temporaryFiles, in: tempDir)
        
        AppLogger.log("[CLEANUP] Automatic cleanup complete", category: AppLogger.storage, level: .info)
    }
    
    /// Get current storage usage breakdown
    static func getStorageUsage() -> StorageUsage {
        let fm = FileManager.default
        
        func directorySize(_ url: URL) -> Int64 {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }
            
            var totalSize: Int64 = 0
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
            return totalSize
        }
        
        return StorageUsage(
            documents: directorySize(StorageLocation.documents.directory),
            caches: directorySize(StorageLocation.caches.directory),
            temporary: directorySize(StorageLocation.temporary.directory),
            recordings: directorySize(StorageManager.recordingsDirectory),
            exports: directorySize(StorageManager.exportsDirectory)
        )
    }
}

struct StorageUsage {
    let documents: Int64
    let caches: Int64
    let temporary: Int64
    let recordings: Int64
    let exports: Int64
    
    var total: Int64 {
        documents + caches + temporary
    }
    
    var formatted: String {
        """
        Documents: \(ByteCountFormatter.string(fromByteCount: documents, countStyle: .file))
        Caches: \(ByteCountFormatter.string(fromByteCount: caches, countStyle: .file))
        Temporary: \(ByteCountFormatter.string(fromByteCount: temporary, countStyle: .file))
        Recordings: \(ByteCountFormatter.string(fromByteCount: recordings, countStyle: .file))
        Exports: \(ByteCountFormatter.string(fromByteCount: exports, countStyle: .file))
        Total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
        """
    }
}
