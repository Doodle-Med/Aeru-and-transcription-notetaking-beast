//
//  AeruLLMIntegration.swift
//  WhisperControlMobile
//
//  Integration layer between WhisperControlMobile and AeRU LLM system
//

import Foundation
import FoundationModels

@available(iOS 26.0, *)
class AeruLLMIntegration: ObservableObject {
    
    // RAG - managed per chat session using our new AeruRAGModel
    private var ragModels: [String: AeruRAGModel] = [:]
    
    // LLM Sessions - managed per chat session
    private var sessions: [String: LanguageModelSession] = [:]
    
    // LLM Generation
    @Published var userLLMQuery: String = ""
    @Published var userLLMResponse: String?
    
    // Chat session management
    @Published var chatMessages: [ChatMessage] = []
    private var currentSessionId: String?
    private let databaseManager = DatabaseManager.shared
    
    // LLM isResponding property
    @Published var isResponding: Bool = false
    
    // Web search property
    @Published var isWebSearching: Bool = false
    
    private func updateIsResponding() {
        Task { @MainActor in
            guard let currentSessionId = currentSessionId,
                  let session = sessions[currentSessionId] else {
                isResponding = false
                return
            }
            isResponding = session.isResponding
        }
    }
    
    private let encoder = JSONEncoder()
    
    private func newSession(previousSession: LanguageModelSession) -> LanguageModelSession {
        return ContextWindowManager.createCondensedSession(from: previousSession)
    }
    
    // Switch to a different session
    func switchToSession(_ session: ChatSession) {
        currentSessionId = session.id
        // Update responding state for the new session
        updateIsResponding()
    }
    
    // Get or create RAG model for current session
    private func getRagForSession(_ sessionId: String, collectionName: String) -> AeruRAGModel {
        if let existingRAG = ragModels[sessionId] {
            return existingRAG
        }
        
        let newRAG = AeruRAGModel(collectionName: collectionName)
        ragModels[sessionId] = newRAG
        return newRAG
    }
    
    // Get or create LanguageModelSession for current session
    private func getSessionForChat(_ sessionId: String) -> LanguageModelSession {
        if let existingSession = sessions[sessionId] {
            return existingSession
        }
        
        // Load transcript from database if it exists
        if let savedTranscript = loadTranscript(for: sessionId) {
            let newSession = LanguageModelSession(transcript: savedTranscript)
            sessions[sessionId] = newSession
            print("📚 [AeruLLM] Loading transcript for session: \(sessionId)")
            return newSession
        } else {
            // Create new session if no saved transcript
            let newSession = LanguageModelSession()
            sessions[sessionId] = newSession
            print("📚 [AeruLLM] Creating new session: \(sessionId)")
            return newSession
        }
    }
    
    func processDocument(url: URL, for session: ChatSession) async -> Bool {
        StorageManager.logUserAction("PDF Processing Started", details: "File: \(url.lastPathComponent)")
        
        // Try to access security scoped resource
        let hasAccess = url.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("Security Scoped Resource", details: "Access result: \(hasAccess)")
        
        if !hasAccess {
            StorageManager.logSystemEvent("Security Scoped Resource", details: "Failed to access, attempting direct access")
            print("WARNING: Failed to access security scoped resource, attempting direct access")
        }
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
                StorageManager.logSystemEvent("Security Scoped Resource", details: "Released access")
            }
        }
        
        let extractStartTime = Date()
        guard let extractedText = EnhancedDocumentProcessor.extractTextFromPDF(at: url) else {
            StorageManager.logUserAction("PDF Processing Failed", details: "Text extraction failed for \(url.lastPathComponent)")
            StorageManager.logError(NSError(domain: "PDF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Text extraction failed"]), context: "PDF Processing")
            print("ERROR: Failed to extract text from PDF at: \(url.path)")
            return false
        }
        
        let extractDuration = Date().timeIntervalSince(extractStartTime)
        StorageManager.logPerformance("PDF Text Extraction", duration: extractDuration, details: "Extracted \(extractedText.count) characters")
        
        let originalFileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = originalFileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let uniqueFileName = "\(baseName)_\(UUID().uuidString).\(fileExtension)"
        
        // Save document to local storage
        let data = extractedText.data(using: String.Encoding.utf8) ?? Data()
        guard let savedURL = EnhancedDocumentProcessor.saveDocumentToLocalStorage(data, fileName: uniqueFileName) else {
            StorageManager.logUserAction("PDF Processing Failed", details: "Failed to save document locally")
            return false
        }
        
        // Save to database
        _ = databaseManager.saveDocument(
            sessionId: session.id,
            name: originalFileName,
            path: savedURL.path,
            type: "PDF"
        )
        
        // Process document into RAG with original filename
        await processDocumentToRAG(content: extractedText, filename: originalFileName, for: session)
        
        StorageManager.logUserAction("PDF Processing Success", details: "File: \(originalFileName), Duration: \(String(format: "%.2f", extractDuration))s")
        return true
    }
    
    private func processDocumentToRAG(content: String, filename: String, for session: ChatSession) async {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()
        
        let chunks = EnhancedDocumentProcessor.chunkText(content, maxChunkSize: 800, overlapTokens: 50)
        
        // Process chunks concurrently for better performance with duplicate prevention
        await withTaskGroup(of: Void.self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    // Check for duplicates before adding
                    let chunkHash = chunk.hashValue
                    let metadata = [
                        "filename": filename,
                        "original_filename": filename,
                        "chunk_index": index,
                        "total_chunks": chunks.count,
                        "session_id": session.id,
                        "content_hash": chunkHash
                    ]
                    
                    // Only add if not duplicate
                    await rag.addEntryWithMetadata(chunk, metadata: metadata)
                    StorageManager.logSystemEvent("RAG Processing", details: "Processed chunk \(index + 1)/\(chunks.count) for \(filename)")
                }
            }
        }
        
        print("SUCCESS: [AeruLLM] Processed document \(filename) with \(chunks.count) chunks")
    }
    
    // Intelligent query routing method
    func queryIntelligently(_ query: String, for session: ChatSession, sessionManager: ChatSessionManager, useWebSearch: Bool = false) async throws {
        if useWebSearch {
            // Set web search flag
            await MainActor.run {
                isWebSearching = true
            }
            
            // Perform web search
            // TODO: Implement web search functionality
            print("INFO: [AeruLLM] Web search requested for: \(query)")
            
            // Clear web search flag
            await MainActor.run {
                isWebSearching = false
            }
        } else {
            // Use RAG-based query
            try await queryLLM(query, for: session, sessionManager: sessionManager)
        }
    }
    
    func queryLLM(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = nil
        userLLMQuery = UIQuery
        // Clear web search results when using RAG (webSearchResults not available in this context)
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        await MainActor.run {
            chatMessages.append(userMessage)
        }
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()
        await rag.findLLMNeighbors(for: userLLMQuery)
        
        let contextItems = rag.neighbors.map { "- \($0.0)" }.joined(separator: "\n")
        let prompt = """
                    You are a helpful assistant that answers questions based on the provided context from uploaded documents and knowledge base.
                    
                    Context:
                    \(contextItems)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based primarily on the information provided in the context above
                    2. If the context contains relevant information from uploaded documents, prioritize that
                    3. If the context doesn't contain enough information, say so clearly
                    4. Be concise and accurate
                    
                    Answer:
                    """
        
        let session = getSessionForChat(chatSession.id)
        
        do {
            let responseStream = session.streamResponse(to: prompt)
            updateIsResponding()
            var fullResponse = ""
            for try await partialStream in responseStream {
                let content = partialStream.content
                await MainActor.run {
                    userLLMResponse = content
                }
                fullResponse = content
            }
            
            // Clear streaming response first to prevent duplicate display
            await MainActor.run {
                userLLMResponse = nil
            }
            updateIsResponding()
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
            // Save transcript after successful response
            saveTranscript(session.transcript, sessionId: sessionId)
            
            // Generate title after successful response if this is the first message
            if isFirstMessage && chatSession.title.isEmpty {
                print("📚 [AeruLLM] Generating title from AI response. Session ID: \(chatSession.id)")
                let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                print("📚 [AeruLLM] Generated title: '\(generatedTitle)'")
                sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                print("📚 [AeruLLM] Title update completed")
            }
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Handle context window exceeded with automatic recovery
            let newSessionInstance = newSession(previousSession: session)
            sessions[chatSession.id] = newSessionInstance
            
            // Retry with new session
            do {
                let responseStream = newSessionInstance.streamResponse(to: prompt)
                updateIsResponding()
                var fullResponse = ""
                for try await partialStream in responseStream {
                    let content = partialStream.content
                    await MainActor.run {
                        userLLMResponse = content
                    }
                    fullResponse = content
                }
                
                // Clear streaming response first to prevent duplicate display
                await MainActor.run {
                    userLLMResponse = nil
                }
                updateIsResponding()
                
                // Save assistant message with recovery notice
                let recoveryMessage = ContextWindowManager.createRecoveryMessage()
                let fullResponseWithNotice = "\(recoveryMessage)\n\n\(fullResponse)"
                let assistantMessage = ChatMessage(text: fullResponseWithNotice, isUser: false)
                await MainActor.run {
                    chatMessages.append(assistantMessage)
                }
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
                // Save transcript after successful retry response
                saveTranscript(newSessionInstance.transcript, sessionId: sessionId)
                
                // Generate title after successful response if this is the first message
                if isFirstMessage && chatSession.title.isEmpty {
                    print("📚 [AeruLLM] Generating title from AI response (retry). Session ID: \(chatSession.id)")
                    let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                    print("📚 [AeruLLM] Generated title: '\(generatedTitle)'")
                    sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                    print("📚 [AeruLLM] Title update completed")
                }
                
            } catch {
                updateIsResponding()
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
                await MainActor.run {
                    chatMessages.append(assistantMessage)
                }
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            updateIsResponding()
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            updateIsResponding()
            // Handle errors including guardrail violations
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
    }
    
    func generateChatTitle(from aiResponse: String, for chatSession: ChatSession) async -> String {
        let titlePrompt = """
        Generate a short, descriptive title (2-4 words) for a chat conversation based on this AI response. The title should capture the main topic or subject matter.
        
        AI Response: "\(aiResponse)"
        
        Instructions:
        1. Keep it concise (2-4 words maximum)
        2. Focus on the main topic or subject matter
        3. Don't include quotation marks
        4. Make it suitable as a chat title
        5. Use simple, clear language
        
        Title:
        """
        
        let session = getSessionForChat(chatSession.id)
        
        do {
            let responseStream = session.streamResponse(to: titlePrompt)
            updateIsResponding()
            var fullResponse = ""
            for try await partialStream in responseStream {
                fullResponse = partialStream.content
            }
            updateIsResponding()
            
            let cleanTitle = fullResponse
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: """
                , with: "")
                .replacingOccurrences(of:
 """, with: "")
            
            return cleanTitle.isEmpty ? "New Chat" : cleanTitle
        } catch {
            print("Error generating title: \(error)")
            return "New Chat"
        }
    }
    
    /// Saves a transcript for a given session to the database.
    func saveTranscript(_ transcript: Transcript, sessionId: String) {
        do {
            let jsonData = try JSONEncoder().encode(transcript)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            databaseManager.saveTranscriptJSON(jsonString, sessionId: sessionId)
        } catch {
            print("Failed to encode transcript: \(error)")
        }
    }
    
    /// Loads a transcript for a given session from the database.
    func loadTranscript(for sessionId: String) -> Transcript? {
        guard let jsonString = databaseManager.loadTranscriptJSON(for: sessionId),
              !jsonString.isEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        do {
            let transcript = try JSONDecoder().decode(Transcript.self, from: jsonData)
            return transcript
        } catch {
            print("Failed to decode transcript: \(error)")
            return nil
        }
    }
    
    // MARK: - Transcript Integration
    
    /// Index a completed transcription job into the RAG system
    func indexTranscriptionJob(_ job: TranscriptionJob, for session: ChatSession) async {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.indexTranscriptionJob(job)
    }
    
    /// Index multiple transcription jobs
    func indexTranscriptionJobs(_ jobs: [TranscriptionJob], for session: ChatSession) async {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.indexTranscriptionJobs(jobs)
    }
    
    func getDocuments(for session: ChatSession) -> [(id: String, name: String, type: String, uploadedAt: Date)] {
        return databaseManager.getDocuments(for: session.id)
    }
    
    func getRagNeighbors(for session: ChatSession) -> [(String, Double)] {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        return rag.neighbors
    }
}
