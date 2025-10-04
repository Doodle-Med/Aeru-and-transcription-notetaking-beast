import Foundation
import CoreML
import NaturalLanguage
import SVDB

@MainActor
class LocalRAGService: ObservableObject {
    static let shared = LocalRAGService()
    
    @Published var isIndexing = false
    @Published var indexedCount = 0
    
    private let storageURL: URL
    private let embeddingsURL: URL
    private let documentsURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = documentsPath.appendingPathComponent("RAGStorage")
        embeddingsURL = storageURL.appendingPathComponent("embeddings.json")
        documentsURL = storageURL.appendingPathComponent("documents.json")
        
        createStorageIfNeeded()
    }
    
    private func createStorageIfNeeded() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Indexing
    
    func indexTranscript(_ transcript: String, metadata: [String: Any] = [:]) async {
        isIndexing = true
        defer { isIndexing = false }
        
        // Use SVDB via Aeru's flow: one collection for transcripts
        let collectionName = "whisper_transcripts"
        let collection: Collection
        if let existing = SVDB.shared.getCollection(collectionName) {
            collection = existing
        } else {
            do {
                collection = try SVDB.shared.collection(collectionName)
            } catch {
                print("[RAG] Failed to create SVDB collection: \(error)")
                return
            }
        }
        
        // Check for duplicates before adding
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            print("[RAG] Skipping empty transcript")
            return
        }
        
        // Check if this exact content already exists
        let existingDocs = await loadDocuments()
        let isDuplicate = existingDocs.contains { doc in
            doc.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTranscript
        }
        
        if isDuplicate {
            print("[RAG] Skipping duplicate transcript")
            return
        }
        
        // Generate embedding using NLEmbedding word vectors averaged
        let embedding = generateEmbedding(for: transcript)
        // Add into SVDB (store text; metadata persistence stays in our JSON for now)
        collection.addDocument(text: transcript, embedding: embedding.map { Double($0) })
        
        // Also maintain our lightweight JSON for metadata/stats
        let document = RAGDocument(
            id: UUID().uuidString,
            content: transcript,
            embedding: embedding,
            metadata: metadata,
            timestamp: Date()
        )
        await saveDocument(document)
        indexedCount += 1
    }
    
    private func generateEmbedding(for text: String) -> [Float] {
        // Use NaturalLanguage framework to generate embeddings
        // For simplicity, we'll use a basic text vectorization
        // In a production app, you'd use a proper embedding model
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var vector = Array(repeating: Float(0), count: 300) // 300-dimensional vector
        
        for (index, word) in words.enumerated() {
            if index < vector.count {
                // Simple hash-based embedding
                let hash = word.hashValue
                vector[index] = Float(hash % 1000) / 1000.0
            }
        }
        
        return vector
    }
    
    private func saveDocument(_ document: RAGDocument) async {
        // Load existing documents
        var documents = await loadDocuments()
        documents.append(document)
        
        // Save back to storage
        do {
            let data = try JSONEncoder().encode(documents)
            try data.write(to: documentsURL)
        } catch {
            print("[RAG] Failed to save document: \(error)")
        }
    }
    
    private func loadDocuments() async -> [RAGDocument] {
        do {
            let data = try Data(contentsOf: documentsURL)
            return try JSONDecoder().decode([RAGDocument].self, from: data)
        } catch {
            return []
        }
    }
    
    // MARK: - Search
    
    func search(_ query: String, limit: Int = 5) async -> [RAGSearchResult] {
        let collectionName = "whisper_transcripts"
        guard let collection = SVDB.shared.getCollection(collectionName) else {
            return []
        }
        let queryEmbedding = generateEmbedding(for: query).map { Double($0) }
        let neighbors = collection.search(query: queryEmbedding, num_results: limit)
        
        // Return results by pairing SVDB text with our JSON metadata when possible
        let localDocs = await loadDocuments()
        var results: [RAGSearchResult] = []
        for n in neighbors {
            // Validate score to prevent NaN values
            let validScore = n.score.isNaN || n.score.isInfinite ? 0.0 : n.score
            let validSimilarity = Float(validScore)
            
            if let match = localDocs.first(where: { $0.content == n.text }) {
                results.append(RAGSearchResult(id: match.id, content: match.content, similarity: validSimilarity, metadata: match.metadata))
            } else {
                // Fallback shell doc
                let doc = RAGDocument(id: UUID().uuidString, content: n.text, embedding: [], metadata: [:], timestamp: Date())
                results.append(RAGSearchResult(id: doc.id, content: doc.content, similarity: validSimilarity, metadata: doc.metadata))
            }
        }
        return results
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let magnitude = sqrt(normA) * sqrt(normB)
        return magnitude > 0 ? dotProduct / magnitude : 0
    }
    
    // MARK: - Management
    
    func clearAll() async {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: embeddingsURL)
        indexedCount = 0
    }
    
    func getStats() async -> RAGStats {
        let documents = await loadDocuments()
        return RAGStats(
            totalDocuments: documents.count,
            storageSize: getStorageSize(),
            lastIndexed: documents.last?.timestamp
        )
    }
    
    private func getStorageSize() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Data Models

struct RAGDocument: Codable, Identifiable {
    let id: String
    var content: String
    var embedding: [Float]
    var metadata: [String: Any]
    var timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id, content, embedding, timestamp
        case metadata
    }
    
    init(id: String, content: String, embedding: [Float], metadata: [String: Any], timestamp: Date) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.metadata = metadata
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        embedding = try container.decode([Float].self, forKey: .embedding)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Handle metadata as JSON
        if let metadataData = try? container.decode(Data.self, forKey: .metadata),
           let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
            metadata = metadataDict
        } else {
            metadata = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        
        // Validate embedding array to prevent NaN values
        let validEmbedding = embedding.map { value in
            if value.isNaN || value.isInfinite {
                print("WARNING: Found invalid embedding value: \(value), replacing with 0.0")
                return Float(0.0)
            }
            return value
        }
        try container.encode(validEmbedding, forKey: .embedding)
        
        try container.encode(timestamp, forKey: .timestamp)
        
        // Convert metadata to JSON-safe format and validate for NaN values
        let jsonSafeMetadata = convertToJSONSafe(metadata)
        let metadataData = try JSONSerialization.data(withJSONObject: jsonSafeMetadata)
        try container.encode(metadataData, forKey: .metadata)
    }
    
    private func convertToJSONSafe(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if let date = value as? Date {
                result[key] = date.timeIntervalSince1970
            } else if let string = value as? String {
                result[key] = string
            } else if let floatValue = value as? Float {
                // Validate Float values for NaN/infinite
                if floatValue.isNaN || floatValue.isInfinite {
                    print("WARNING: Found invalid metadata float value: \(floatValue), replacing with 0.0")
                    result[key] = Float(0.0)
                } else {
                    result[key] = floatValue
                }
            } else if let doubleValue = value as? Double {
                // Validate Double values for NaN/infinite
                if doubleValue.isNaN || doubleValue.isInfinite {
                    print("WARNING: Found invalid metadata double value: \(doubleValue), replacing with 0.0")
                    result[key] = Double(0.0)
                } else {
                    result[key] = doubleValue
                }
            } else if let number = value as? NSNumber {
                result[key] = number
            } else if let bool = value as? Bool {
                result[key] = bool
            } else if let array = value as? [Any] {
                result[key] = array
            } else if let nestedDict = value as? [String: Any] {
                result[key] = convertToJSONSafe(nestedDict)
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }
}


struct RAGStats {
    let totalDocuments: Int
    let storageSize: Int64
    let lastIndexed: Date?
}
