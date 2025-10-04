import Foundation

extension StorageManager {
    /// Result of resolving a security-scoped bookmark
    struct SecurityScopedAccess {
        let url: URL
        let securityScoped: Bool
    }
    
    /// Resolves a security-scoped bookmark to access file imported via document picker
    static func resolveSecurityScopedURL(from bookmarkData: Data) -> SecurityScopedAccess? {
        var isStale = false
        
        #if targetEnvironment(macCatalyst)
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        guard !isStale else {
            AppLogger.log("Security-scoped bookmark is stale", category: AppLogger.storage, level: .error)
            return nil
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            AppLogger.log("Failed to access security-scoped resource", category: AppLogger.storage, level: .error)
            return nil
        }
        
        return SecurityScopedAccess(url: url, securityScoped: true)
        
        #else
        // iOS document picker URLs don't require security-scoped access
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        return SecurityScopedAccess(url: url, securityScoped: false)
        #endif
    }
    
    /// Releases security-scoped resource access (Mac Catalyst only)
    static func releaseSecurityScopedURL(_ url: URL, securityScoped: Bool) {
        #if targetEnvironment(macCatalyst)
        if securityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        #endif
    }
}
