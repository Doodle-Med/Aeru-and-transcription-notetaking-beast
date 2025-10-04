import Foundation
import NaturalLanguage
import Accelerate
import SwiftUI
import SVDB

@MainActor
class RAGDatabaseManager: ObservableObject {
    static let shared = RAGDatabaseManager()
    
    @Published var documents: [RAGDocument] = []
    @Published var collections: [String: RAGCollection] = [:]
    @Published var isAnalyzing: Bool = false
    @Published var vectorAnalysis: VectorAnalysis?
    
    private let storageURL: URL
    private let analysisURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documentsPath.appendingPathComponent("rag_database.json")
        analysisURL = documentsPath.appendingPathComponent("vector_analysis.json")
        loadDatabase()
    }
    
    // MARK: - Database Management
    
    func loadDatabase() {
        // Load documents from local storage first, then sync with SVDB
        documents = []
        collections.removeAll()
        
        // Try to load from local storage
        loadFromLocalStorage()
        
        // Sync with SVDB collection to ensure we have the latest documents
        syncWithSVDB()
        
        print("RAG Database: Loaded \(documents.count) documents from local storage and SVDB")
    }
    
    private func loadFromLocalStorage() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([RAGDocument].self, from: data) else {
            return
        }
        documents = loaded
        
        // Rebuild collections from loaded documents
        for doc in documents {
            let collectionName = doc.metadata["collection"] as? String ?? "whisper_transcripts"
            if collections[collectionName] == nil {
                collections[collectionName] = RAGCollection(name: collectionName)
            }
            collections[collectionName]?.addDocument(doc)
        }
    }
    
    private func syncWithSVDB() {
        // Initialize SVDB collection if needed
        let svdbCollection: Collection
        do {
            if let existing = SVDB.shared.getCollection("whisper_transcripts") {
                svdbCollection = existing
            } else {
                svdbCollection = try SVDB.shared.collection("whisper_transcripts")
                print("RAG Database: Created new SVDB collection: whisper_transcripts")
            }
        } catch {
            print("RAG Database: Failed to access SVDB collection: \(error)")
            return
        }
        
        // Get a sample of documents from SVDB to check for new ones
        // Use a neutral query to get documents
        let neutralEmbedding = Array(repeating: 0.0, count: 300)
        let svdbResults = svdbCollection.search(query: neutralEmbedding, num_results: 1000)
        
        var newDocumentsCount = 0
        for (index, result) in svdbResults.enumerated() {
            // Check if this document already exists in our local storage
            let existingDoc = documents.first { doc in
                doc.content == result.text
            }
            
            // Also check for exact content matches to prevent duplicates
            let isDuplicate = documents.contains { doc in
                doc.content.trimmingCharacters(in: .whitespacesAndNewlines) == result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if existingDoc == nil && !isDuplicate {
                // Create new document from SVDB result
                // Validate score to prevent NaN values
                let validScore = result.score.isNaN || result.score.isInfinite ? 0.0 : result.score
                
                let document = RAGDocument(
                    id: "svdb_\(Date().timeIntervalSince1970)_\(index)",
                    content: result.text,
                    embedding: [], // SVDB SearchResult doesn't expose embedding
                    metadata: [
                        "source": "whisper_transcripts",
                        "score": validScore,
                        "collection": "whisper_transcripts",
                        "timestamp": Date().timeIntervalSince1970
                    ],
                    timestamp: Date()
                )
                documents.append(document)
                
                // Add to collection
                if collections["whisper_transcripts"] == nil {
                    collections["whisper_transcripts"] = RAGCollection(name: "whisper_transcripts")
                }
                collections["whisper_transcripts"]?.addDocument(document)
                newDocumentsCount += 1
            }
        }
        
        if newDocumentsCount > 0 {
            // Save updated documents to local storage
            saveToLocalStorage()
            print("RAG Database: Added \(newDocumentsCount) new documents from SVDB")
        }
    }
    
    private func saveToLocalStorage() {
        do {
            let data = try JSONEncoder().encode(documents)
            try data.write(to: storageURL)
        } catch {
            print("RAG Database: Failed to save documents to local storage: \(error)")
        }
    }
    
    func saveDatabase() {
        saveToLocalStorage()
        print("RAG Database: Saved \(documents.count) documents to local storage")
    }
    
    // MARK: - Document Management
    
    func deleteDocument(_ document: RAGDocument) {
        documents.removeAll { $0.id == document.id }
        
        // Remove from collection
        let collectionName = document.metadata["collection"] as? String ?? "whisper_transcripts"
        collections[collectionName]?.removeDocument(id: document.id)
        
        saveDatabase()
    }
    
    func deleteDocuments(by filename: String) {
        let toDelete = documents.filter { doc in
            doc.metadata["filename"] as? String == filename
        }
        
        for doc in toDelete {
            deleteDocument(doc)
        }
    }
    
    func deleteAllDocuments() {
        // Clear local storage
        documents.removeAll()
        collections.removeAll()
        saveToLocalStorage()
        
        // Clear SVDB collection
        do {
            if let existing = SVDB.shared.getCollection("whisper_transcripts") {
                // SVDB doesn't have a direct "delete all" method, so we'll recreate the collection
                // This effectively clears all documents
                let _ = try SVDB.shared.collection("whisper_transcripts")
                print("RAG Database: Cleared all documents from local storage and SVDB")
            }
        } catch {
            print("RAG Database: Failed to clear SVDB collection: \(error)")
        }
    }
    
    func editDocument(_ document: RAGDocument, newContent: String) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        
        // Regenerate embedding for new content
        if let newEmbedding = generateEmbedding(for: newContent) {
            documents[index].content = newContent
            documents[index].embedding = newEmbedding
            documents[index].timestamp = Date()
            
            // Update in collection
            let collectionName = document.metadata["collection"] as? String ?? "whisper_transcripts"
            collections[collectionName]?.updateDocument(id: document.id, content: newContent, embedding: newEmbedding)
            
            saveDatabase()
        }
    }
    
    func duplicateDocument(_ document: RAGDocument) {
        let newDoc = RAGDocument(
            id: UUID().uuidString,
            content: document.content,
            embedding: document.embedding,
            metadata: document.metadata.merging(["duplicated_from": document.id]) { _, new in new },
            timestamp: Date()
        )
        
        documents.append(newDoc)
        
        let collectionName = document.metadata["collection"] as? String ?? "whisper_transcripts"
        if collections[collectionName] == nil {
            collections[collectionName] = RAGCollection(name: collectionName)
        }
        collections[collectionName]?.addDocument(newDoc)
        
        saveDatabase()
    }
    
    // MARK: - Collection Management
    
    func createCollection(name: String) {
        collections[name] = RAGCollection(name: name)
    }
    
    func deleteCollection(name: String) {
        // Remove all documents from this collection
        documents.removeAll { doc in
            doc.metadata["collection"] as? String == name
        }
        collections.removeValue(forKey: name)
        saveDatabase()
    }
    
    func moveDocument(_ document: RAGDocument, to collectionName: String) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        
        let oldCollection = document.metadata["collection"] as? String ?? "whisper_transcripts"
        
        // Remove from old collection
        collections[oldCollection]?.removeDocument(id: document.id)
        
        // Add to new collection
        if collections[collectionName] == nil {
            collections[collectionName] = RAGCollection(name: collectionName)
        }
        collections[collectionName]?.addDocument(document)
        
        // Update document metadata
        documents[index].metadata["collection"] = collectionName
        saveDatabase()
    }
    
    // MARK: - Vector Analysis
    
    func analyzeVectorDistribution() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        let analysis = await performVectorAnalysis()
        vectorAnalysis = analysis
        
        // Save analysis
        do {
            let data = try JSONEncoder().encode(analysis)
            try data.write(to: analysisURL)
        } catch {
            print("[RAG] Failed to save vector analysis: \(error)")
        }
    }
    
    private func performVectorAnalysis() async -> VectorAnalysis {
        let allEmbeddings = documents.compactMap { $0.embedding }
        guard !allEmbeddings.isEmpty else {
            return VectorAnalysis(
                totalVectors: 0,
                vectorDimensions: 0,
                averageMagnitude: 0,
                magnitudeDistribution: [],
                similarityMatrix: [],
                clusters: [],
                outliers: []
            )
        }
        
        let dimensions = allEmbeddings[0].count
        var magnitudes: [Float] = []
        var similarityMatrix: [[Float]] = []
        
        // Calculate magnitudes
        for embedding in allEmbeddings {
            let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
            magnitudes.append(magnitude)
        }
        
        // Calculate similarity matrix (sample for performance)
        let sampleSize = min(50, allEmbeddings.count)
        for i in 0..<sampleSize {
            var similarities: [Float] = []
            for j in 0..<sampleSize {
                if i == j {
                    similarities.append(1.0)
                } else {
                    let similarity = cosineSimilarity(allEmbeddings[i], allEmbeddings[j])
                    similarities.append(similarity)
                }
            }
            similarityMatrix.append(similarities)
        }
        
        // Simple clustering (k-means with k=3)
        let clusters = performSimpleClustering(embeddings: Array(allEmbeddings.prefix(100)))
        
        // Find outliers (documents with very low average similarity)
        let outliers = findOutliers(embeddings: allEmbeddings, magnitudes: magnitudes)
        
        return VectorAnalysis(
            totalVectors: allEmbeddings.count,
            vectorDimensions: dimensions,
            averageMagnitude: magnitudes.reduce(0, +) / Float(magnitudes.count),
            magnitudeDistribution: magnitudes.sorted(),
            similarityMatrix: similarityMatrix,
            clusters: clusters,
            outliers: outliers
        )
    }
    
    private func performSimpleClustering(embeddings: [[Float]]) -> [VectorCluster] {
        guard embeddings.count >= 3 else { return [] }
        
        let k = 3
        var centroids = Array(embeddings.prefix(k))
        var clusters: [VectorCluster] = []
        
        // Simple k-means iteration
        for _ in 0..<5 { // 5 iterations
            clusters = Array(0..<k).map { VectorCluster(id: $0, centroid: centroids[$0], documents: []) }
            
            for (index, embedding) in embeddings.enumerated() {
                var bestCluster = 0
                var bestSimilarity: Float = -1
                
                for (clusterIndex, centroid) in centroids.enumerated() {
                    let similarity = cosineSimilarity(embedding, centroid)
                    if similarity > bestSimilarity {
                        bestSimilarity = similarity
                        bestCluster = clusterIndex
                    }
                }
                
                clusters[bestCluster].documents.append(index)
            }
            
            // Update centroids
            for i in 0..<k {
                if !clusters[i].documents.isEmpty {
                    let clusterEmbeddings = clusters[i].documents.map { embeddings[$0] }
                    centroids[i] = averageEmbedding(clusterEmbeddings)
                }
            }
        }
        
        return clusters
    }
    
    private func findOutliers(embeddings: [[Float]], magnitudes: [Float]) -> [Int] {
        var outliers: [Int] = []
        let threshold: Float = 0.1 // Low similarity threshold
        
        for (i, embedding) in embeddings.enumerated() {
            var totalSimilarity: Float = 0
            var count = 0
            
            for (j, otherEmbedding) in embeddings.enumerated() {
                if i != j {
                    totalSimilarity += cosineSimilarity(embedding, otherEmbedding)
                    count += 1
                }
            }
            
            let averageSimilarity = count > 0 ? totalSimilarity / Float(count) : 0
            if averageSimilarity < threshold {
                outliers.append(i)
            }
        }
        
        return outliers
    }
    
    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        
        let dimensions = embeddings[0].count
        var result = Array(repeating: Float(0), count: dimensions)
        
        for embedding in embeddings {
            for i in 0..<dimensions {
                result[i] += embedding[i]
            }
        }
        
        for i in 0..<dimensions {
            result[i] /= Float(embeddings.count)
        }
        
        return result
    }
    
    // MARK: - Search and Similarity
    
    func findSimilarDocuments(to document: RAGDocument, limit: Int = 5) -> [RAGSearchResult] {
        var results: [RAGSearchResult] = []
        
        for otherDoc in documents {
            if otherDoc.id != document.id {
                let similarity = cosineSimilarity(document.embedding, otherDoc.embedding)
                results.append(RAGSearchResult(id: otherDoc.id, content: otherDoc.content, similarity: similarity, metadata: otherDoc.metadata))
            }
        }
        
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }
    
    func searchDocuments(query: String, limit: Int = 10) -> [RAGSearchResult] {
        guard let queryEmbedding = generateEmbedding(for: query) else { return [] }
        
        var results: [RAGSearchResult] = []
        
        for doc in documents {
            let similarity = cosineSimilarity(queryEmbedding, doc.embedding)
            results.append(RAGSearchResult(id: doc.id, content: doc.content, similarity: similarity, metadata: doc.metadata))
        }
        
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Helper Functions
    
    private func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        
        let words = text.lowercased().split(separator: " ").map { String($0) }
        guard !words.isEmpty else { return nil }
        
        var validVectors: [[Float]] = []
        
        for word in words {
            if let vector = embedding.vector(for: word) {
                validVectors.append(vector.map { Float($0) })
            }
        }
        
        guard !validVectors.isEmpty else { return nil }
        
        let vectorLength = validVectors[0].count
        var vectorSum = [Float](repeating: 0, count: vectorLength)
        
        for vector in validVectors {
            vDSP_vadd(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
        }
        
        var vectorAverage = [Float](repeating: 0, count: vectorSum.count)
        var divisor = Float(validVectors.count)
        vDSP_vsdiv(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorSum.count))
        
        // Validate the result to prevent NaN values
        let validatedAverage = vectorAverage.map { value in
            if value.isNaN || value.isInfinite {
                print("WARNING: Generated NaN/infinite embedding value: \(value), replacing with 0.0")
                return Float(0.0)
            }
            return value
        }
        
        return validatedAverage
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let magnitude = sqrt(normA) * sqrt(normB)
        return magnitude > 0 ? dotProduct / magnitude : 0.0
    }
}

// MARK: - Supporting Types

struct VectorAnalysis: Codable {
    let totalVectors: Int
    let vectorDimensions: Int
    let averageMagnitude: Float
    let magnitudeDistribution: [Float]
    let similarityMatrix: [[Float]]
    let clusters: [VectorCluster]
    let outliers: [Int]
}

struct VectorCluster: Codable {
    let id: Int
    let centroid: [Float]
    var documents: [Int]
}

class RAGCollection {
    let name: String
    private var documents: [RAGDocument] = []
    
    init(name: String) {
        self.name = name
    }
    
    func addDocument(_ document: RAGDocument) {
        documents.append(document)
    }
    
    func removeDocument(id: String) {
        documents.removeAll { $0.id == id }
    }
    
    func updateDocument(id: String, content: String, embedding: [Float]) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].content = content
            documents[index].embedding = embedding
            documents[index].timestamp = Date()
        }
    }
    
    func getDocuments() -> [RAGDocument] {
        return documents
    }
    
    func getDocumentCount() -> Int {
        return documents.count
    }
}

struct RAGSearchResult: Identifiable {
    let id: String
    let content: String
    let similarity: Float
    let metadata: [String: Any]
    
    init(id: String, content: String, similarity: Float, metadata: [String: Any] = [:]) {
        self.id = id
        self.content = content
        self.similarity = similarity
        self.metadata = metadata
    }
}
