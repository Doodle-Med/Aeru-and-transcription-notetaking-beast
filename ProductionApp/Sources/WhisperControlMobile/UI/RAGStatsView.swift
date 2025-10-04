import SwiftUI

struct RAGStatsView: View {
    @StateObject private var ragAdapter = AeruRAGAdapter.shared
    @State private var stats: RAGStats = RAGStats(totalDocuments: 0, storageSize: 0, lastIndexed: nil)
    @State private var searchQuery: String = ""
    @State private var searchResults: [RAGSearchResult] = []
    @State private var isSearching: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Stats Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("RAG Database Stats")
                        .font(.headline)
                        .padding(.bottom, 8)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Documents")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(stats.totalDocuments)")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Storage Size")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatBytes(stats.storageSize))
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Last Indexed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(stats.lastIndexed?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Search Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Transcripts")
                        .font(.headline)
                    
                    HStack {
                        TextField("Search for content in transcripts...", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task {
                                    await performSearch()
                                }
                            }
                        
                        Button {
                            Task {
                                await performSearch()
                            }
                        } label: {
                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(searchQuery.isEmpty || isSearching)
                    }
                    
                    if !searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Results (\(searchResults.count))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.content)
                                                .font(.body)
                                                .lineLimit(3)
                                            
                                            HStack {
                                                Text("Score: \(String(format: "%.3f", result.similarity))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text("#\(index + 1)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding()
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("RAG Database")
            .onAppear {
                refreshStats()
            }
        }
    }
    
        private func refreshStats() {
            // Since we've unified to SVDB, we'll create basic stats
            stats = RAGStats(
                totalDocuments: 0,
                storageSize: 0,
                lastIndexed: Date()
            )
        }
    
    private func performSearch() async {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        // Since we've unified to SVDB, we'll use the RAGModel for search
        let ragModel = RAGModel(collectionName: "whisper_transcripts")
        await ragModel.findLLMNeighbors(for: searchQuery)
        
        // Convert RAGModel results to search results
        searchResults = ragModel.neighbors.compactMap { (text, score) in
            // Validate score to prevent NaN values
            let validScore = score.isNaN || score.isInfinite ? 0.0 : score
            let validSimilarity = Float(validScore)
            
            let document = RAGDocument(
                id: UUID().uuidString,
                content: text,
                embedding: [],
                metadata: ["source": "whisper_transcripts"],
                timestamp: Date()
            )
            return RAGSearchResult(id: document.id, content: document.content, similarity: validSimilarity, metadata: document.metadata)
        }
        isSearching = false
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct RAGStatsView_Previews: PreviewProvider {
    static var previews: some View {
        RAGStatsView()
    }
}
