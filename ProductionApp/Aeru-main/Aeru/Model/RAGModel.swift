//
//  RAGModel.swift
//  Aeru
//
//  Created by Sanskar
//

import Foundation
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import Combine

class RAGModel {
    
    let collectionName: String
    var collection: Collection?
    var neighbors: [(String, Double)] = []
    
    init(collectionName: String) {
        self.collectionName = collectionName
    }
    
    func loadCollection() async {
        if let existing = SVDB.shared.getCollection(collectionName) {
            self.collection = existing
            print("✅ Loaded existing collection: \(collectionName)")
            return
        }
        do {
            self.collection = try SVDB.shared.collection(collectionName)
            print("✅ Created new collection: \(collectionName)")
        } catch {
            print("❌ Failed to load collection \(collectionName):", error)
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
            print("ERROR: Collection is nil")
            return 
        }
        
        // Move embedding generation to background thread
        let embedding = generateEmbedding(for: entry)
        
        guard let embedding = embedding else {
            print("ERROR: Failed to generate embedding for entry: \(String(entry.prefix(100)))...")
            return
        }
        
        print("SUCCESS: Adding entry to collection")
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", String(entry.prefix(200)))
        print("EMBEDDING COUNT: ", embedding.count)
        collection.addDocument(text: entry, embedding: embedding)
        print("SUCCESS: Document added to collection")
    }
    
    func generateEmbedding(for sentence: String) -> [Double]? {
        // Try sentence embedding first (iOS 14+)
        if #available(iOS 14.0, *) {
            if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
                let vector = embedding.vector(for: sentence)
                if let vector = vector {
                    print("SUCCESS: Generated sentence embedding for: \(String(sentence.prefix(50)))...")
                    return [Double](vector)
                }
            }
        }
        
        // Fallback to word embeddings with better preprocessing
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("ERROR: Failed to get NLEmbedding for English")
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
            print("ERROR: No words found in sentence")
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
            print("ERROR: No valid word embeddings found for any words in: \(String(sentence.prefix(50)))...")
            return nil
        }
        
        guard !validVectors.isEmpty else {
            print("ERROR: No valid word embeddings found for any words in: \(String(sentence.prefix(50)))...")
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
        
        print("SUCCESS: Generated embedding with \(validVectors.count) valid word vectors out of \(words.count) total words")
        return vectorAverage
    }
    
    func findLLMNeighbors(for query: String) async {
        await ensureCollectionLoaded()
        
        guard let collection = collection else { 
            print("ERROR: Collection is nil in findLLMNeighbors")
            return 
        }
        
        // Move query embedding generation to background thread
        let queryEmbedding = generateEmbedding(for: query)
        
        guard let queryEmbedding = queryEmbedding else {
            print("ERROR: Failed to generate query embedding")
            return
        }
        
        print("SUCCESS: Searching collection for query: \(query)")
        // Increase search results to filter out empty ones
        let results = collection.search(query: queryEmbedding, num_results: 10)
        
        // Filter out empty results and apply context limits
        let filteredResults = results
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.score > 0.0 } // Only include positive scores
            .prefix(3) // Limit to top 3 results
        
        neighbors = filteredResults.map { ($0.text, $0.score) }
        print("SEARCH RESULTS: Found \(results.count) total, \(neighbors.count) valid neighbors")
        for (index, neighbor) in neighbors.enumerated() {
            print("Neighbor \(index + 1): Score \(neighbor.1), Text: \(String(neighbor.0.prefix(100)))...")
        }
    }
    
    
}

