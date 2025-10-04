import SwiftUI

struct DatabaseManagementView: View {
    @StateObject private var ragManager = RAGDatabaseManager.shared
    @State private var showingDeleteAlert = false
    @State private var documentToDelete: RAGDocument?
    @State private var showingEditSheet = false
    @State private var documentToEdit: RAGDocument?
    @State private var searchQuery: String = ""
    
    var filteredDocuments: [RAGDocument] {
        if searchQuery.isEmpty {
            return ragManager.documents
        } else {
            return ragManager.documents.filter { 
                $0.content.localizedCaseInsensitiveContains(searchQuery) || 
                ($0.metadata["filename"] as? String)?.localizedCaseInsensitiveContains(searchQuery) ?? false 
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    TextField("Search documents...", text: $searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .opacity(searchQuery.isEmpty ? 0 : 1)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 8)
                
                // Content
                if ragManager.documents.isEmpty {
                    emptyStateView
                } else if !searchQuery.isEmpty && filteredDocuments.isEmpty {
                    noSearchResultsView
                } else {
                    documentsList
                }
            }
            .navigationTitle("Database Management")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { ragManager.loadDatabase() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                Task { ragManager.loadDatabase() }
            }
            .alert("Delete Document?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let doc = documentToDelete {
                            ragManager.deleteDocument(doc)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let doc = documentToDelete {
                    Text("Are you sure you want to delete '\(doc.metadata["filename"] as? String ?? "this document")' from the RAG database?")
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let doc = documentToEdit {
                    EditRAGDocumentView(document: doc) { updatedContent in
                        // TODO: Implement document update functionality
                        print("Document update requested: \(updatedContent)")
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No documents indexed yet.")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Transcribe audio files to add them to the RAG database.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noSearchResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No documents match your search.")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var documentsList: some View {
        List {
            ForEach(Array(filteredDocuments.enumerated()), id: \.element.id) { index, doc in
                    DatabaseDocumentRowView(
                    document: doc,
                    onEdit: {
                        documentToEdit = doc
                        showingEditSheet = true
                    },
                    onDelete: {
                        documentToDelete = doc
                        showingDeleteAlert = true
                    }
                )
            }
        }
    }
}

struct DatabaseDocumentRowView: View {
    let document: RAGDocument
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.metadata["filename"] as? String ?? document.metadata["original_filename"] as? String ?? "Document")
                .font(.headline)
                .lineLimit(1)
            
            Text(document.content)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Indexed: \(document.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let duration = document.metadata["duration"] as? Double {
                    Text("\(Int(duration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

struct EditRAGDocumentView: View {
    @Environment(\.dismiss) var dismiss
    @State private var editedContent: String
    let document: RAGDocument
    let onSave: (String) -> Void
    
    init(document: RAGDocument, onSave: @escaping (String) -> Void) {
        self.document = document
        self.onSave = onSave
        _editedContent = State(initialValue: document.content)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $editedContent)
                    .padding()
                    .border(Color.gray.opacity(0.2), width: 1)
                    .cornerRadius(5)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Edit Document")
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
                    .disabled(editedContent.isEmpty || editedContent == document.content)
                }
            }
        }
    }
}

#Preview {
    DatabaseManagementView()
}