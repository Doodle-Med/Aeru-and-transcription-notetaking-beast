//
//  AeruRAGModel.swift
//  WhisperControlMobile
//
//  Ported from AeRU working RAG system with transcript integration
//

import Foundation
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import Combine

class AeruRAGModel {
    
    let collectionName: String
    var collection: Collection?
    var neighbors: [(String, Double)] = []
    
    init(collectionName: String) {
        self.collectionName = collectionName
        Task {
            await loadCollection()
        }
    }
    
    func loadCollection() async {
        if let existing = SVDB.shared.getCollection(collectionName) {
            self.collection = existing
            print("✅ [AeruRAG] Loaded existing collection: \(collectionName)")
            return
        }
        do {
            self.collection = try SVDB.shared.collection(collectionName)
            print("✅ [AeruRAG] Created new collection: \(collectionName)")
        } catch {
            print("❌ [AeruRAG] Failed to load collection \(collectionName):", error)
        }
    }
    
    func ensureCollectionLoaded() async {
        if collection == nil {
            await loadCollection()
        }
    }
    
    func addEntry(_ entry: String) async {
        await ensureCollectionLoaded()
        
        guard let collection = collection else { 
            print("ERROR: [AeruRAG] Collection is nil")
            return 
        }
        
        // Validate entry is not empty
        let trimmedEntry = entry.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            print("ERROR: [AeruRAG] Skipping empty entry")
            return
        }
        
        // Move embedding generation to background thread
        let embedding = generateEmbedding(for: trimmedEntry)
        
        guard let embedding = embedding else {
            print("ERROR: [AeruRAG] Failed to generate embedding for entry: \(String(trimmedEntry.prefix(100)))...")
            return
        }
        
        print("SUCCESS: [AeruRAG] Adding entry to collection")
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", String(trimmedEntry.prefix(200)))
        print("EMBEDDING COUNT: ", embedding.count)
        collection.addDocument(text: trimmedEntry, embedding: embedding)
        print("SUCCESS: [AeruRAG] Document added to collection")
    }
    
    func addEntryWithMetadata(_ entry: String, metadata: [String: Any]) async {
        await ensureCollectionLoaded()
        
        guard let collection = collection else { 
            print("ERROR: [AeruRAG] Collection is nil")
            return 
        }
        
        // Validate entry is not empty
        let trimmedEntry = entry.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            print("ERROR: [AeruRAG] Skipping empty entry")
            return
        }
        
        // Check for duplicates using content hash
        if let contentHash = metadata["content_hash"] as? Int {
            let existingResults = collection.search(query: generateEmbedding(for: trimmedEntry) ?? [], num_results: 100)
            let isDuplicate = existingResults.contains { result in
                result.text == trimmedEntry
            }
            
            if isDuplicate {
                print("INFO: [AeruRAG] Skipping duplicate entry for: \(metadata["filename"] as? String ?? "unknown")")
                return
            }
        }
        
        // Move embedding generation to background thread
        let embedding = generateEmbedding(for: trimmedEntry)
        
        guard let embedding = embedding else {
            print("ERROR: [AeruRAG] Failed to generate embedding for entry: \(String(trimmedEntry.prefix(100)))...")
            return
        }
        
        print("SUCCESS: [AeruRAG] Adding entry with metadata to collection")
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", String(trimmedEntry.prefix(200)))
        print("FILENAME: ", metadata["filename"] as? String ?? "unknown")
        print("EMBEDDING COUNT: ", embedding.count)
        
        collection.addDocument(text: trimmedEntry, embedding: embedding)
        
        // Register with RAGDatabaseManager for UI display
        await registerDocumentWithManager(
            content: trimmedEntry,
            filename: metadata["filename"] as? String ?? "unknown",
            chunkIndex: metadata["chunk_index"] as? Int ?? 0,
            totalChunks: metadata["total_chunks"] as? Int ?? 1
        )
        
        print("SUCCESS: [AeruRAG] Document with metadata added to collection")
    }
    
    func generateEmbedding(for sentence: String) -> [Double]? {
        // Try sentence embedding first (iOS 14+)
        if #available(iOS 14.0, *) {
            if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
                let vector = embedding.vector(for: sentence)
                if let vector = vector {
                    print("SUCCESS: [AeruRAG] Generated sentence embedding for: \(String(sentence.prefix(50)))...")
                    return [Double](vector)
                }
            }
        }
        
        // Fallback to word embeddings with better preprocessing
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("ERROR: [AeruRAG] Failed to get NLEmbedding for English")
            return nil
        }
        
        // Better text preprocessing
        let cleanedSentence = sentence
            .lowercased()
            .replacingOccurrences(of: "'", with: "")  // Remove apostrophes from contractions
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
        
        let words = cleanedSentence.split(separator: " ").map { String($0) }
        guard !words.isEmpty else {
            print("ERROR: [AeruRAG] No words found in sentence")
            return nil
        }
        
        var validVectors: [[Double]] = []
        
        for word in words {
            if let vector = embedding.vector(for: word) {
                validVectors.append([Double](vector))
            }
        }
        
        // If no valid embeddings found, return nil - this is a production system
        if validVectors.isEmpty {
            print("ERROR: [AeruRAG] No valid word embeddings found for any words in: \(String(sentence.prefix(50)))...")
            return nil
        }
        
        let vectorLength = validVectors[0].count
        var vectorSum = [Double](repeating: 0, count: vectorLength)
        
        for vector in validVectors {
            vDSP_vaddD(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
        }
        
        var vectorAverage = [Double](repeating: 0, count: vectorSum.count)
        var divisor = Double(validVectors.count)
        vDSP_vsdivD(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorAverage.count))
        
        print("SUCCESS: [AeruRAG] Generated embedding with \(validVectors.count) valid word vectors out of \(words.count) total words")
        return vectorAverage
    }
    
    func findLLMNeighbors(for query: String) async {
        await ensureCollectionLoaded()
        
        guard let collection = collection else { 
            print("ERROR: [AeruRAG] Collection is nil in findLLMNeighbors")
            return 
        }
        
        // Move query embedding generation to background thread
        let queryEmbedding = generateEmbedding(for: query)
        
        guard let queryEmbedding = queryEmbedding else {
            print("ERROR: [AeruRAG] Failed to generate query embedding")
            return
        }
        
        print("SUCCESS: [AeruRAG] Searching collection for query: \(query)")
        // Increase search results to filter out empty ones
        let results = collection.search(query: queryEmbedding, num_results: 10)
        
        // Filter out empty results and apply context limits
        let filteredResults = results
            .filter { !$0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }
            .filter { $0.score > 0.0 } // Only include positive scores
            .prefix(3) // Limit to top 3 results
        
        neighbors = filteredResults.map { ($0.text, $0.score) }
        print("SEARCH RESULTS: [AeruRAG] Found \(results.count) total, \(neighbors.count) valid neighbors")
        for (index, neighbor) in neighbors.enumerated() {
            print("Neighbor \(index + 1): Score \(neighbor.1), Text: \(String(neighbor.0.prefix(100)))...")
        }
    }
    
    // MARK: - Transcript Integration Methods
    
    /// Index a transcription job result into the RAG system
    func indexTranscriptionJob(_ job: TranscriptionJob) async {
        guard let result = job.result, 
              !result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            print("ERROR: [AeruRAG] Cannot index job \(job.filename) - no text content")
            return
        }
        
        StorageManager.logSystemEvent("RAG Indexing", details: "Starting indexing for job: \(job.filename)")
        
        // Process text using chunking
            let chunks = EnhancedDocumentProcessor.chunkText(result.text, maxChunkSize: 800, overlapTokens: 50)
        
        // Index each chunk and register with RAGDatabaseManager
        for (index, chunk) in chunks.enumerated() {
            guard !chunk.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                print("WARNING: [AeruRAG] Skipping empty chunk \(index + 1) for job \(job.filename)")
                continue
            }
            
            await addEntry(chunk)
            
            // Register with RAGDatabaseManager for UI display
            await registerDocumentWithManager(
                content: chunk,
                filename: job.filename,
                chunkIndex: index,
                totalChunks: chunks.count
            )
            
            print("SUCCESS: [AeruRAG] Indexed chunk \(index + 1)/\(chunks.count) for job \(job.filename)")
        }
        
        StorageManager.logSystemEvent("RAG Indexing", details: "Completed indexing for job: \(job.filename)")
        print("SUCCESS: [AeruRAG] Indexed job \(job.filename) with \(chunks.count) chunks")
    }
    
    /// Register a document with the RAGDatabaseManager for UI display
    private func registerDocumentWithManager(content: String, filename: String, chunkIndex: Int, totalChunks: Int) async {
        await MainActor.run {
            let document = RAGDocument(
                id: "\(filename)_chunk_\(chunkIndex)_\(Date().timeIntervalSince1970)",
                content: content,
                embedding: [],
                metadata: [
                    "filename": filename,
                    "chunk_index": chunkIndex,
                    "total_chunks": totalChunks,
                    "source": "whisper_transcripts",
                    "collection": "whisper_transcripts"
                ],
                timestamp: Date()
            )
            
            // Add to RAGDatabaseManager
            RAGDatabaseManager.shared.documents.append(document)
            
            // Add to collection
            if RAGDatabaseManager.shared.collections["whisper_transcripts"] == nil {
                RAGDatabaseManager.shared.collections["whisper_transcripts"] = RAGCollection(name: "whisper_transcripts")
            }
            RAGDatabaseManager.shared.collections["whisper_transcripts"]?.addDocument(document)
            
            // Save to local storage
            RAGDatabaseManager.shared.saveDatabase()
        }
    }
    
    /// Index multiple transcription jobs efficiently
    func indexTranscriptionJobs(_ jobs: [TranscriptionJob]) async {
        await withTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    await self.indexTranscriptionJob(job)
                }
            }
        }
    }
}
