//
//  ContextWindowManager.swift
//  WhisperControlMobile
//
//  Context window recovery mechanism ported from AeRU
//

import Foundation
import FoundationModels

class ContextWindowManager {
    
    /// Creates a new session with condensed history when context window is exceeded
    static func createCondensedSession(from previousSession: LanguageModelSession) -> LanguageModelSession {
        let allEntries = previousSession.transcript
        var condensedEntries = [Transcript.Entry]()
        
        // Always keep the first entry
        if let firstEntry = allEntries.first {
            condensedEntries.append(firstEntry)
        }
        
        // If there are multiple entries, keep the last one too
        if allEntries.count > 1, let lastEntry = allEntries.last {
            condensedEntries.append(lastEntry)
        }
        
        // Create condensed transcript
        let condensedTranscript = Transcript(entries: condensedEntries)
        let newSession = LanguageModelSession(transcript: condensedTranscript)
        
        print("🔄 [ContextWindow] Created condensed session with \(condensedEntries.count) entries from \(allEntries.count) original entries")
        
        return newSession
    }
    
    /// Handles context window exceeded error with automatic retry
    static func handleContextWindowError<T>(
        error: Error,
        previousSession: LanguageModelSession,
        retryBlock: () async throws -> T
    ) async throws -> T {
        if case .exceededContextWindowSize = error as? LanguageModelSession.GenerationError {
            
            print("⚠️ [ContextWindow] Context window exceeded, creating condensed session")
            
            let condensedSession = createCondensedSession(from: previousSession)
            
            // Retry with condensed session
            do {
                return try await retryBlock()
            } catch {
                // If retry also fails, throw the original error
                throw error
            }
        } else {
            // Not a context window error, rethrow
            throw error
        }
    }
    
    /// Creates a recovery message for context window issues
    static func createRecoveryMessage() -> String {
        return "I've condensed the conversation history to continue. Previous context has been summarized to fit within the model's limits."
    }
}
