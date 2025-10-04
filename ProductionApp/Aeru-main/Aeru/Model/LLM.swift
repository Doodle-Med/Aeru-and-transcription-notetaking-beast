//
//  LLM.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on 7/21/25.
//

import Foundation
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import Combine

import FoundationModels

@available(iOS 26.0, *)
class LLM: ObservableObject {
    
    // Contains all the generation and invokes RAGModel.swift and WebSearchService.swift
    
    // RAG - now managed per chat session
    private var ragModels: [String: RAGModel] = [:]
    
    // LLM Sessions - now managed per chat session
    private var sessions: [String: LanguageModelSession] = [:]
    
    // LLM Generation
    @Published var userLLMQuery: String = ""
    @Published var userLLMResponse: String?
    
    // Web Search Services
    var webSearch: WebSearchService = WebSearchService()
    @Published var isWebSearching = false
    @Published var webSearchResults: [WebSearchResult] = []
    
    // Chat session management
    @Published var chatMessages: [ChatMessage] = []
    private var currentSessionId: String?
    private let databaseManager = DatabaseManager.shared
    
    // LLM isResponding property
    @Published var isResponding: Bool = false
    
    private func updateIsResponding() {
        Task { @MainActor in
            if #available(iOS 26.0, *) {
                guard let currentSessionId = currentSessionId,
                      let session = sessions[currentSessionId] else {
                    isResponding = false
                    return
                }
                isResponding = session.isResponding
            } else {
                isResponding = false
            }
        }
    }
    
    private let encoder = JSONEncoder()
    
    @available(iOS 26.0, *)
    private func newSession(previousSession: LanguageModelSession) -> LanguageModelSession {
        let allEntries = previousSession.transcript
        var condensedEntries = [Transcript.Entry]()

        if let firstEntry = allEntries.first {
            condensedEntries.append(firstEntry as! Transcript.Entry)
            if allEntries.count > 1, let lastEntry = allEntries.last {
                condensedEntries.append(lastEntry as! Transcript.Entry)
            }
        }
        let condensedTranscript = Transcript(entries: condensedEntries)
        return LanguageModelSession(transcript: condensedTranscript)
    }
    
    // Get or create RAG model for current session
    private func getRagForSession(_ sessionId: String, collectionName: String) -> RAGModel {
        if let existingRAG = ragModels[sessionId] {
            return existingRAG
        }
        
        let newRAG = RAGModel(collectionName: collectionName)
        ragModels[sessionId] = newRAG
        return newRAG
    }
    
    // Get or create LanguageModelSession for current session
    @available(iOS 26.0, *)
    private func getSessionForChat(_ sessionId: String) -> LanguageModelSession {
        if let existingSession = sessions[sessionId] {
            return existingSession
        }
        
        // Check model availability first
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            print("✅ FoundationModels available")
        case .unavailable(let reason):
            #if targetEnvironment(simulator)
            print("ℹ️  FoundationModels unavailable in simulator: \(reason)")
            print("ℹ️  Apple Intelligence requires a physical device (iPhone 15 Pro or later)")
            #else
            print("❌ FoundationModels unavailable on device: \(reason)")
            #endif
        }
        
        // Load transcript from database if it exists
        let newSession: LanguageModelSession
        if let savedTranscript = loadTranscript(for: sessionId) {
            newSession = LanguageModelSession(transcript: savedTranscript)
            print("✅ Created session with transcript for session: \(sessionId)")
        } else {
            // Create new session if no saved transcript
            newSession = LanguageModelSession()
            print("✅ Created new session for session: \(sessionId)")
        }
        
        // Prewarm the session for better performance (reduces first-token latency by up to 40%)
        newSession.prewarm()
        
        sessions[sessionId] = newSession
        return newSession
    }
    
    func sessionHasDocuments(_ session: ChatSession) -> Bool {
        let documents = databaseManager.getDocuments(for: session.id)
        return !documents.isEmpty
    }
    
    func queryIntelligently(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager, useWebSearch: Bool) async throws {
        StorageManager.logUserAction("Aeru Chat Send", details: "Message: \(UIQuery.prefix(50))..., Session: \(chatSession.id), WebSearch: \(useWebSearch)")
        StorageManager.logSystemEvent("Aeru Chat Processing", details: "Starting query processing")
        
        // Intelligent routing logic:
        // 1. If web search is toggled, use web search
        // 2. If session has 1 or more documents, use RAG
        // 3. Else use general query
        
        let hasDocuments = sessionHasDocuments(chatSession)
        StorageManager.logSystemEvent("Aeru Query Routing", details: "Session has documents: \(hasDocuments)")
        
        if useWebSearch {
            StorageManager.logSystemEvent("Aeru Query Routing", details: "Using web search mode")
            try await webSearch(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else if hasDocuments {
            StorageManager.logSystemEvent("Aeru Query Routing", details: "Using document RAG mode")
            try await queryLLM(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else {
            StorageManager.logSystemEvent("Aeru Query Routing", details: "Using general mode")
            try await queryLLMGeneral(UIQuery, for: chatSession, sessionManager: sessionManager)
        }
        
        StorageManager.logSystemEvent("Aeru Chat Processing", details: "Query processing completed successfully")
    }
    
    func switchToSession(_ session: ChatSession) {
        currentSessionId = session.id
        loadMessagesForCurrentSession()
        
        // Ensure session-specific LanguageModelSession exists
        _ = getSessionForChat(session.id)
    }
    
    func loadMessagesForCurrentSession() {
        guard let sessionId = currentSessionId else {
            chatMessages = []
            return
        }
        
        chatMessages = databaseManager.getMessages(for: sessionId)
    }
    
    func addEntry(_ entry: String, to session: ChatSession) async {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()
        await rag.addEntry(entry)
    }
    
    func processDocument(url: URL, for session: ChatSession) async -> Bool {
        StorageManager.logUserAction("PDF Processing Started", details: "File: \(url.lastPathComponent)")
        
        // Try to access security scoped resource with multiple approaches
        StorageManager.logSystemEvent("Security Scoped Resource", details: "Attempting access for: \(url.lastPathComponent)")
        let hasAccess = url.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("Security Scoped Resource", details: "Access result: \(hasAccess)")
        
        if !hasAccess {
            StorageManager.logSystemEvent("Security Scoped Resource", details: "Failed to access, attempting direct access")
            print("WARNING: Failed to access security scoped resource, attempting direct access")
            
            // On iOS, security scoped bookmarks are not available, so we'll try direct access
            StorageManager.logSystemEvent("Security Scoped Resource", details: "iOS platform - trying direct file access")
            // Continue with direct processing since iOS handles security scoped resources differently
        } else {
            StorageManager.logSystemEvent("Security Scoped Resource", details: "Successfully obtained access")
        }
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
                StorageManager.logSystemEvent("Security Scoped Resource", details: "Released access")
            }
        }
        
        let extractStartTime = Date()
        guard let extractedText = DocumentProcessor.extractTextFromPDF(at: url) else {
            StorageManager.logUserAction("PDF Processing Failed", details: "Text extraction failed for \(url.lastPathComponent)")
            StorageManager.logError(NSError(domain: "PDF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Text extraction failed"]), context: "PDF Processing")
            print("ERROR: Failed to extract text from PDF at: \(url.path)")
            print("ERROR: PDF file may be corrupted, password-protected, or in an unsupported format")
            return false
        }
        
        let extractDuration = Date().timeIntervalSince(extractStartTime)
        StorageManager.logPerformance("PDF Text Extraction", duration: extractDuration, details: "Extracted \(extractedText.count) characters")
        
        let originalFileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = originalFileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let uniqueFileName = "\(baseName)_\(UUID().uuidString).\(fileExtension)"
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDirectory.appendingPathComponent("Documents").appendingPathComponent(uniqueFileName)
        
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            print("Failed to copy document: \(error)")
            return false
        }
        
        guard let documentId = databaseManager.saveDocument(
            sessionId: session.id,
            name: originalFileName,
            path: destinationURL.path,
            type: "pdf"
        ) else {
            print("Failed to save document to database")
            return false
        }
        
        let chunks = DocumentProcessor.chunkText(extractedText)
        print("SUCCESS: Extracted \(extractedText.count) characters from PDF")
        print("SUCCESS: Created \(chunks.count) chunks from text")
        
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()
        
        for (index, chunk) in chunks.enumerated() {
            print("Processing chunk \(index + 1)/\(chunks.count): \(String(chunk.prefix(100)))...")
            
            if let chunkId = databaseManager.saveDocumentChunk(
                documentId: documentId,
                text: chunk,
                index: index
            ) {
                print("SUCCESS: Saved chunk \(index + 1) to database")
                await rag.addEntry(chunk)
                databaseManager.markChunkAsEmbedded(chunkId)
                print("SUCCESS: Added chunk \(index + 1) to RAG and marked as embedded")
            } else {
                print("ERROR: Failed to save chunk \(index + 1) to database")
            }
        }
        
        return true
    }
    
    func getDocuments(for session: ChatSession) -> [(id: String, name: String, type: String, uploadedAt: Date)] {
        return databaseManager.getDocuments(for: session.id)
    }
    
    func getRagNeighbors(for session: ChatSession) -> [(String, Double)] {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        return rag.neighbors
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
        // First try to load from database manager
        if let jsonString = databaseManager.loadTranscriptJSON(for: sessionId),
           !jsonString.isEmpty,
           let jsonData = jsonString.data(using: .utf8) {
            do {
                let transcript = try JSONDecoder().decode(Transcript.self, from: jsonData)
                print("SUCCESS: Loaded transcript from database for session: \(sessionId)")
                return transcript
            } catch {
                print("Failed to decode transcript from database: \(error)")
            }
        }
        
        // Note: FoundationModels Transcript doesn't support manual construction
        // The transcript is built naturally through conversation via LanguageModelSession
        // RAG context will be injected through the query functions instead
        print("INFO: RAG context will be injected at query time rather than via transcript")
        
        print("INFO: Creating new empty transcript for session: \(sessionId)")
        return nil
    }
    
    func webSearch(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = nil
        userLLMQuery = UIQuery
        isWebSearching = true
        webSearchResults = []
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        await MainActor.run {
            chatMessages.append(userMessage)
        }
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Perform web search and scraping
        let results = await webSearch.searchAndScrape(query: userLLMQuery)
        webSearchResults = results
        
        // Get or create RAG model for this session
        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()
        
        // Embed all scraped content into RAG - process chunks concurrently for better performance
        await withTaskGroup(of: Void.self) { group in
            for result in results {
                let chunks = webSearch.chunkText(result.content)
                for chunk in chunks {
                    group.addTask {
                        await rag.addEntry(chunk)
                    }
                }
            }
        }
        
        // Use semantic similarity to find top 3 most relevant chunks
        await rag.findLLMNeighbors(for: userLLMQuery)
        
        // Get top 3 neighbors for context
        let topNeighbors = Array(rag.neighbors.prefix(3))
        let semanticContext = topNeighbors.map { neighbor in
            "Relevance Score: \(String(format: "%.3f", neighbor.1))\n\(neighbor.0)"
        }.joined(separator: "\n\n---\n\n")
        
        // Create enhanced prompt with semantic search results
        let prompt = """
                    You are a helpful assistant that answers questions based on semantically relevant web search results.
                    
                    Most Relevant Web Content (ranked by semantic similarity):
                    \(semanticContext)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based primarily on the most relevant content above (higher relevance scores are more important)
                    2. Be accurate and cite the sources when possible
                    3. If the content doesn't fully answer the question, acknowledge the limitations
                    4. Provide a comprehensive and informative response based on the available information
                    
                    Answer:
                    """
        
        // Generate response using LLM
        let session = getSessionForChat(chatSession.id)
        
        do {
            updateIsResponding()
            let response = try await session.respond(to: prompt)
            let fullResponse = response.content
            updateIsResponding()
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false, sources: results)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
                // Save transcript after successful response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)
            
            // Generate title after successful response if this is the first message
            if isFirstMessage && chatSession.title.isEmpty {
                print("🔍 WebSearch: Generating title from AI response. Session ID: \(chatSession.id)")
                let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                print("🔍 WebSearch: Generated title: '\(generatedTitle)'")
                sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                print("🔍 WebSearch: Title update completed")
            }
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            let newSessionInstance = newSession(previousSession: session)
            sessions[chatSession.id] = newSessionInstance
            
            // Retry with new session
            do {
                let response = try await newSessionInstance.respond(to: prompt)
                let fullResponse = response.content
                updateIsResponding()
                
                // Clear streaming response first to prevent duplicate display
                userLLMResponse = nil
                updateIsResponding()
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false, sources: results)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
                // Save transcript after successful retry response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)
                
                // Generate title after successful response if this is the first message
                if isFirstMessage && chatSession.title.isEmpty {
                    print("🔍 WebSearch: Generating title from AI response (retry). Session ID: \(chatSession.id)")
                    let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                    print("🔍 WebSearch: Generated title: '\(generatedTitle)'")
                    sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                    print("🔍 WebSearch: Title update completed")
                }
                
            } catch {
                updateIsResponding()
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            updateIsResponding()
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            updateIsResponding()
            // Handle errors including guardrail violations
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
        
        isWebSearching = false
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
    
    func queryLLM(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        await MainActor.run {
            userLLMResponse = nil
            userLLMQuery = UIQuery
            webSearchResults = [] // Clear web search results when using RAG
        }
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        await MainActor.run {
            chatMessages.append(userMessage)
        }
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Search session-specific RAG collection
        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.findLLMNeighbors(for: userLLMQuery)
        
        // ALSO search the global whisper_transcripts collection for indexed transcripts
        let transcriptRAG = RAGModel(collectionName: "whisper_transcripts")
        await transcriptRAG.findLLMNeighbors(for: userLLMQuery)
        
        // Combine results from both collections
        var allNeighbors = rag.neighbors
        allNeighbors.append(contentsOf: transcriptRAG.neighbors)
        
        // Sort by relevance score and take top results
        let sortedNeighbors = allNeighbors.sorted { $0.1 > $1.1 }.prefix(5)
        
        let contextItems = sortedNeighbors.map { neighbor in
            "Score: \(String(format: "%.3f", neighbor.1)) | \(neighbor.0)"
        }.joined(separator: "\n")
        
        let contextDescription = sortedNeighbors.isEmpty ? "No relevant context found in knowledge base or transcripts." : contextItems
        
        let prompt = """
                    You are a helpful assistant that answers questions based on the provided context from uploaded documents, knowledge base, and transcribed audio.
                    
                    Context from Knowledge Base and Transcripts:
                    \(contextDescription)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based primarily on the information provided in the context above
                    2. The context includes both uploaded documents and transcribed audio recordings
                    3. Higher relevance scores indicate more relevant information
                    4. If the context doesn't contain enough information, say so clearly
                    5. Be concise and accurate
                    
                    Answer:
                    """
        
        let session = getSessionForChat(chatSession.id)
        
        do {
            // Use official FoundationModels API with concurrency safety
            updateIsResponding()
            let response = try await session.respond(to: prompt)
            let fullResponse = response.content
            updateIsResponding()
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
                // Save transcript after successful response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)
            
            // Generate title after successful response if this is the first message
            if isFirstMessage && chatSession.title.isEmpty {
                print("📚 RAG: Generating title from AI response. Session ID: \(chatSession.id)")
                let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                print("📚 RAG: Generated title: '\(generatedTitle)'")
                sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                print("📚 RAG: Title update completed")
            }
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            let newSessionInstance = newSession(previousSession: session)
            sessions[chatSession.id] = newSessionInstance
            
            // Retry with new session
            do {
                let response = try await newSessionInstance.respond(to: prompt)
                let fullResponse = response.content
                updateIsResponding()
                
                // Clear streaming response first to prevent duplicate display
                userLLMResponse = nil
                updateIsResponding()
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
                // Save transcript after successful retry response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)
                
                // Generate title after successful response if this is the first message
                if isFirstMessage && chatSession.title.isEmpty {
                    print("📚 RAG: Generating title from AI response (retry). Session ID: \(chatSession.id)")
                    let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                    print("📚 RAG: Generated title: '\(generatedTitle)'")
                    sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                    print("📚 RAG: Title update completed")
                }
                
            } catch {
                updateIsResponding()
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            updateIsResponding()
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            updateIsResponding()
            
            // Handle FoundationModels errors properly
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            } else if error.localizedDescription.contains("Model assets are unavailable") {
                #if targetEnvironment(simulator)
                "Apple Intelligence is not available in the iOS Simulator. Please test on a physical iPhone 15 Pro or later with Apple Intelligence enabled."
                #else
                "Apple Intelligence is not available on this device. Please ensure you're running on a compatible device with Apple Intelligence enabled."
                #endif
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
    }
    
    func queryLLMGeneral(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        StorageManager.logUserAction("Aeru Chat Query", details: "Query: \(UIQuery.prefix(50))..., Session: \(chatSession.id), WebSearch: false")
        StorageManager.logSystemEvent("Aeru General Query Start", details: "Session: \(chatSession.id)")
        
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = nil
        userLLMQuery = UIQuery
        webSearchResults = [] // Clear web search results when using general mode
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        await MainActor.run {
            chatMessages.append(userMessage)
        }
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Check if we have any transcripts available
        StorageManager.logSystemEvent("Aeru General Query", details: "Searching whisper_transcripts collection")
        let transcriptRAG = RAGModel(collectionName: "whisper_transcripts")
        await transcriptRAG.findLLMNeighbors(for: userLLMQuery)
        
        StorageManager.logSystemEvent("Aeru RAG Collection", details: transcriptRAG.neighbors.isEmpty ? "Created new: whisper_transcripts" : "Loaded existing: whisper_transcripts")
        StorageManager.logSystemEvent("Aeru RAG Search", details: "Searching whisper_transcripts for: \(UIQuery.prefix(50))...")
        StorageManager.logSystemEvent("Aeru RAG Search", details: "Collection whisper_transcripts: Found \(transcriptRAG.neighbors.count) neighbors")
        
        // Log each result with score and text length
        for (index, neighbor) in transcriptRAG.neighbors.enumerated() {
            StorageManager.logSystemEvent("Aeru RAG Search", details: "Result \(index + 1): Score \(String(format: "%.3f", neighbor.1)), Text length: \(neighbor.0.count)")
        }
        
        // Create prompt - include transcripts if available
        let prompt: String
        if !transcriptRAG.neighbors.isEmpty {
            let sortedNeighbors = transcriptRAG.neighbors.sorted { $0.1 > $1.1 }.prefix(3)
            let contextItems = sortedNeighbors.map { neighbor in
                "Score: \(String(format: "%.3f", neighbor.1)) | \(neighbor.0)"
            }.joined(separator: "\n")
            
            StorageManager.logSystemEvent("Aeru General Query", details: "Found \(transcriptRAG.neighbors.count) transcript results")
            
            prompt = """
                        You are a helpful assistant. Answer the question using available transcript context and your general knowledge.
                        
                        Relevant Transcript Context:
                        \(contextItems)
                        
                        Question: \(userLLMQuery)
                        
                        Instructions:
                        1. Use the transcript context above if relevant
                        2. Otherwise, use your general knowledge
                        3. Be concise and informative
                        
                        Answer:
                        """
        } else {
            prompt = """
                        You are a helpful assistant. Answer the following question based on your general knowledge and training.
                        
                        Question: \(userLLMQuery)
                        
                        Instructions:
                        1. Provide a helpful and accurate response based on your general knowledge
                        2. Be concise and informative
                        3. If you're not certain about something, mention that
                        4. Use a conversational tone
                        
                        Answer:
                        """
        }
        
        let session = getSessionForChat(chatSession.id)
        print("--------------------\nMODEL TRANSCRIPT:\n ", session.transcript)
        print("WHISPER TRANSCRIPTS RAG NEIGHBORS: \(transcriptRAG.neighbors.count)")
        
        do {
            updateIsResponding()
            let response = try await session.respond(to: prompt)
            let fullResponse = response.content
            updateIsResponding()
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)

                // Save transcript after successful response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)

            // Generate title after successful response if this is the first message
            if isFirstMessage && chatSession.title.isEmpty {
                print("💬 General: Generating title from AI response. Session ID: \(chatSession.id)")
                let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                print("💬 General: Generated title: '\(generatedTitle)'")
                sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                print("💬 General: Title update completed")
            }
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            let newSessionInstance = newSession(previousSession: session)
            sessions[chatSession.id] = newSessionInstance
            
            // Retry with new session
            do {
                let response = try await newSessionInstance.respond(to: prompt)
                let fullResponse = response.content
                updateIsResponding()
                
                // Clear streaming response first to prevent duplicate display
                userLLMResponse = nil
                updateIsResponding()
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
                // Save transcript after successful retry response
                // Note: FoundationModels manages transcript internally, no manual saving needed
                // saveTranscript(transcript, sessionId: sessionId)
                
                // Generate title after successful response if this is the first message
                if isFirstMessage && chatSession.title.isEmpty {
                    print("💬 General: Generating title from AI response (retry). Session ID: \(chatSession.id)")
                    let generatedTitle = await generateChatTitle(from: fullResponse, for: chatSession)
                    print("💬 General: Generated title: '\(generatedTitle)'")
                    sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
                    print("💬 General: Title update completed")
                }
                
            } catch {
                updateIsResponding()
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to Apple's safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            updateIsResponding()
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            updateIsResponding()
            
            // Handle FoundationModels errors properly
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to Apple's safety guidelines. Please try rephrasing your question."
            } else if error.localizedDescription.contains("Model assets are unavailable") {
                #if targetEnvironment(simulator)
                "Apple Intelligence is not available in the iOS Simulator. Please test on a physical iPhone 15 Pro or later with Apple Intelligence enabled."
                #else
                "Apple Intelligence is not available on this device. Please ensure you're running on a compatible device with Apple Intelligence enabled."
                #endif
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
    }
    
    
}
