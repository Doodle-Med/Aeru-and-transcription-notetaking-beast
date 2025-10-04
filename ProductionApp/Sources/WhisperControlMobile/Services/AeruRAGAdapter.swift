import Foundation
import NaturalLanguage
import Accelerate
import SVDB

final class AeruRAGAdapter: ObservableObject {
    static let shared = AeruRAGAdapter()
    
    // Use SVDB for unified RAG system
    private var collection: Collection?
    private let collectionName = "whisper_transcripts"
    
    private init() {
        // Initialize SVDB collection for unified RAG system
        Task {
            await initializeCollection()
        }
    }
    
    private func initializeCollection() async {
        do {
            if let existing = SVDB.shared.getCollection(collectionName) {
                self.collection = existing
                print("[AeruRAG] Loaded existing SVDB collection: \(collectionName)")
            } else {
                self.collection = try SVDB.shared.collection(collectionName)
                print("[AeruRAG] Created new SVDB collection: \(collectionName)")
            }
        } catch {
            print("[AeruRAG] Failed to initialize collection: \(error)")
        }
    }
    
    private func ensureCollectionLoaded() async {
        if collection == nil {
            await initializeCollection()
        }
    }
    
    func index(jobFilename: String, created: Date, durationSeconds: Double, text: String) async {
        await ensureCollectionLoaded()
        
        guard let collection = collection else {
            print("[AeruRAG] Collection not available for indexing")
            return
        }
        
        // Process text using Aeru's DocumentProcessor
        let chunks = DocumentProcessor.chunkText(text, maxChunkSize: 800, overlapTokens: 50)
        
        // Index each chunk in the unified SVDB system
        for (index, chunkText) in chunks.enumerated() {
            // Generate embedding for the chunk
            guard let embedding = generateEmbedding(for: chunkText) else {
                print("[AeruRAG] Failed to generate embedding for chunk \(index) of \(jobFilename)")
                continue
            }
            
            // Add document to SVDB collection (convert Float to Double)
            let doubleEmbedding = embedding.map { Double($0) }
            collection.addDocument(text: chunkText, embedding: doubleEmbedding)
        }
        
        print("[AeruRAG] Indexed: \(jobFilename) chunks=\(chunks.count)")
    }
    
    private func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("[AeruRAG] Failed to get NLEmbedding for English")
            return nil
        }
        
        let words = text.lowercased().split(separator: " ").map { String($0) }
        guard !words.isEmpty else {
            print("[AeruRAG] No words found in text")
            return nil
        }
        
        var validVectors: [[Float]] = []
        
        for word in words {
            if let vector = embedding.vector(for: word) {
                validVectors.append(vector.map { Float($0) })
            }
        }
        
        guard !validVectors.isEmpty else {
            print("[AeruRAG] No valid word embeddings found for: \(String(text.prefix(50)))...")
            return nil
        }
        
        let vectorLength = validVectors[0].count
        var vectorSum = [Float](repeating: 0, count: vectorLength)
        
        for vector in validVectors {
            vDSP_vadd(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
        }
        
        var vectorAverage = [Float](repeating: 0, count: vectorSum.count)
        var divisor = Float(validVectors.count)
        vDSP_vsdiv(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorAverage.count))
        
        return vectorAverage
    }
    
    // Unified RAG system - all search and management is handled by SVDB
    // The AeruRAGAdapter now acts as a bridge to the unified SVDB system
}

// MARK: - Supporting Types
// Using RAGCollection from RAGDatabaseManager.swift
