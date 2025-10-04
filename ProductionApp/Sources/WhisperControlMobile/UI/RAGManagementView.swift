import SwiftUI
import Charts

struct RAGManagementView: View {
    @StateObject private var ragManager = RAGDatabaseManager.shared
    @State private var selectedTab: ManagementTab = .documents
    @State private var searchQuery: String = ""
    @State private var selectedCollection: String = "All"
    @State private var showingEditSheet = false
    @State private var editingDocument: RAGDocument?
    @State private var showingDeleteAlert = false
    @State private var documentToDelete: RAGDocument?
    
    enum ManagementTab: String, CaseIterable {
        case documents = "Documents"
        case collections = "Collections"
        case analysis = "Vector Analysis"
        case search = "Search"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Management Tab", selection: $selectedTab) {
                    ForEach(ManagementTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                switch selectedTab {
                case .documents:
                    documentsView
                case .collections:
                    collectionsView
                case .analysis:
                    analysisView
                case .search:
                    searchView
                }
            }
            .navigationTitle("RAG Database Manager")
            .onAppear {
                ragManager.loadDatabase()
            }
            .sheet(isPresented: $showingEditSheet) {
                if let document = editingDocument {
                    DocumentEditView(document: document) { updatedContent in
                        ragManager.editDocument(document, newContent: updatedContent)
                    }
                }
            }
            .alert("Delete Document", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let document = documentToDelete {
                        ragManager.deleteDocument(document)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this document? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Documents View
    
    private var documentsView: some View {
        VStack {
            // Filters
            HStack {
                TextField("Search documents...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Collection", selection: $selectedCollection) {
                    Text("All").tag("All")
                    ForEach(Array(ragManager.collections.keys.sorted()), id: \.self) { collection in
                        Text(collection).tag(collection)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding()
            
            // Documents List
            List {
                ForEach(filteredDocuments, id: \.id) { document in
                    DocumentRowView(
                        document: document,
                        onEdit: {
                            editingDocument = document
                            showingEditSheet = true
                        },
                        onDelete: {
                            documentToDelete = document
                            showingDeleteAlert = true
                        },
                        onDuplicate: {
                            ragManager.duplicateDocument(document)
                        }
                    )
                }
            }
        }
    }
    
    private var filteredDocuments: [RAGDocument] {
        var docs = ragManager.documents
        
        // Filter by collection
        if selectedCollection != "All" {
            docs = docs.filter { doc in
                doc.metadata["collection"] as? String == selectedCollection
            }
        }
        
        // Filter by search query
        if !searchQuery.isEmpty {
            docs = docs.filter { doc in
                doc.content.localizedCaseInsensitiveContains(searchQuery) ||
                (doc.metadata["filename"] as? String)?.localizedCaseInsensitiveContains(searchQuery) == true
            }
        }
        
        return docs.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Collections View
    
    private var collectionsView: some View {
        VStack {
            // Collection Stats
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(Array(ragManager.collections.keys.sorted()), id: \.self) { collectionName in
                    CollectionCardView(
                        name: collectionName,
                        documentCount: ragManager.collections[collectionName]?.getDocumentCount() ?? 0,
                        onDelete: {
                            ragManager.deleteCollection(name: collectionName)
                        }
                    )
                }
            }
            .padding()
            
            Spacer()
        }
    }
    
    // MARK: - Analysis View
    
    private var analysisView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Analysis Controls
                HStack {
                    Button("Analyze Vectors") {
                        Task {
                            await ragManager.analyzeVectorDistribution()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ragManager.isAnalyzing)
                    
                    if ragManager.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                
                if let analysis = ragManager.vectorAnalysis {
                    // Vector Statistics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Vector Statistics")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            StatCard(title: "Total Vectors", value: "\(analysis.totalVectors)")
                            StatCard(title: "Dimensions", value: "\(analysis.vectorDimensions)")
                            StatCard(title: "Avg Magnitude", value: String(format: "%.3f", analysis.averageMagnitude))
                            StatCard(title: "Clusters", value: "\(analysis.clusters.count)")
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Magnitude Distribution Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Magnitude Distribution")
                            .font(.headline)
                        
                        if #available(iOS 16.0, *) {
                            Chart(analysis.magnitudeDistribution.enumerated().map { (index, magnitude) in
                                (index: index, magnitude: magnitude)
                            }, id: \.index) { item in
                                LineMark(
                                    x: .value("Index", item.index),
                                    y: .value("Magnitude", item.magnitude)
                                )
                                .foregroundStyle(.blue)
                            }
                            .frame(height: 200)
                        } else {
                            Text("Charts require iOS 16.0+")
                                .foregroundColor(.secondary)
                                .frame(height: 200)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Clusters
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Document Clusters")
                            .font(.headline)
                        
                        ForEach(analysis.clusters, id: \.id) { cluster in
                            HStack {
                                Text("Cluster \(cluster.id)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(cluster.documents.count) documents")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Outliers
                    if !analysis.outliers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Outliers (\(analysis.outliers.count))")
                                .font(.headline)
                            
                            Text("Documents with low similarity to others")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                } else {
                    Text("Run vector analysis to see insights")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack {
            // Search Interface
            VStack(spacing: 12) {
                TextField("Search query...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }
                
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchQuery.isEmpty)
            }
            .padding()
            
            // Search Results
            if !searchResults.isEmpty {
                List(searchResults, id: \.id) { result in
                    SearchResultRowView(result: result)
                }
            } else if !searchQuery.isEmpty {
                Text("No results found")
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Spacer()
        }
    }
    
    @State private var searchResults: [RAGSearchResult] = []
    
    private func performSearch() {
        searchResults = ragManager.searchDocuments(query: searchQuery, limit: 20)
    }
}

// MARK: - Supporting Views

struct DocumentRowView: View {
    let document: RAGDocument
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.metadata["filename"] as? String ?? "Unknown")
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(document.content)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text(document.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button("Edit") { onEdit() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        
                        Button("Duplicate") { onDuplicate() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        
                        Button("Delete") { onDelete() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CollectionCardView: View {
    let name: String
    let documentCount: Int
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                Button("Delete") { onDelete() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
            }
            
            Text("\(documentCount) documents")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SearchResultRowView: View {
    let result: RAGSearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.content)
                .font(.body)
                .lineLimit(3)
            
            HStack {
                Text("Similarity: \(String(format: "%.3f", result.similarity))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Timestamp: \(result.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .cornerRadius(8)
    }
}

struct DocumentEditView: View {
    let document: RAGDocument
    let onSave: (String) -> Void
    
    @State private var editedContent: String
    @Environment(\.dismiss) private var dismiss
    
    init(document: RAGDocument, onSave: @escaping (String) -> Void) {
        self.document = document
        self.onSave = onSave
        self._editedContent = State(initialValue: document.content)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $editedContent)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editedContent)
                        dismiss()
                    }
                    .disabled(editedContent == document.content)
                }
            }
        }
    }
}

struct RAGManagementView_Previews: PreviewProvider {
    static var previews: some View {
        RAGManagementView()
    }
}
