//
//  EnhancedDocumentProcessor.swift
//  WhisperControlMobile
//
//  Enhanced document processing with multiple parsing strategies and robust error handling
//  Mirrors AeRU original implementation with improvements for reliability
//

import Foundation
import PDFKit
import Vision
import NaturalLanguage
import UniformTypeIdentifiers

class EnhancedDocumentProcessor {
    
    // MARK: - PDF Processing with Multiple Strategies
    
    /// Enhanced PDF text extraction with multiple fallback strategies
    static func extractTextFromPDF(at url: URL) -> String? {
        StorageManager.logSystemEvent("Enhanced PDF Processing Start", details: "URL: \(url.lastPathComponent)")
        
        // Validate file access and properties
        guard let fileInfo = validatePDFFile(at: url) else {
            return nil
        }
        
        StorageManager.logSystemEvent("PDF File Validation", details: "File size: \(fileInfo.size) bytes, Pages: \(fileInfo.pageCount)")
        
        // Strategy 1: Standard PDFKit extraction (fastest, most reliable for text-based PDFs)
        if let text = extractWithPDFKit(at: url) {
            StorageManager.logSystemEvent("PDF Extraction Success", details: "PDFKit method - \(text.count) characters")
            return text
        }
        
        // Strategy 2: Enhanced PDFKit with multiple access patterns
        if let text = extractWithEnhancedPDFKit(at: url) {
            StorageManager.logSystemEvent("PDF Extraction Success", details: "Enhanced PDFKit method - \(text.count) characters")
            return text
        }
        
        // Strategy 3: File Provider Storage specific approach
        if url.path.contains("File Provider Storage") {
            if let text = extractFromFileProviderStorage(at: url) {
                StorageManager.logSystemEvent("PDF Extraction Success", details: "File Provider Storage method - \(text.count) characters")
                return text
            }
        }
        
        // Strategy 4: Vision OCR for image-based PDFs (slower but more comprehensive)
        if let text = extractWithVisionOCR(at: url) {
            StorageManager.logSystemEvent("PDF Extraction Success", details: "Vision OCR method - \(text.count) characters")
            return text
        }
        
        // Strategy 5: Hybrid approach combining multiple methods
        if let text = extractWithHybridApproach(at: url) {
            StorageManager.logSystemEvent("PDF Extraction Success", details: "Hybrid method - \(text.count) characters")
            return text
        }
        
        StorageManager.logError(NSError(domain: "PDF", code: -999, userInfo: [NSLocalizedDescriptionKey: "All extraction methods failed"]), context: "Enhanced PDF Processing")
        return nil
    }
    
    // MARK: - File Validation
    
    private struct PDFFileInfo {
        let exists: Bool
        let size: Int64
        let pageCount: Int
        let isReadable: Bool
    }
    
    private static func validatePDFFile(at url: URL) -> PDFFileInfo? {
        StorageManager.logSystemEvent("PDF Validation", details: "Validating file at: \(url.path)")
        
        // For File Provider Storage, we need to access security-scoped resources
        let hasAccess = url.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("PDF Validation", details: "Security scoped access: \(hasAccess)")
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check file existence
        guard FileManager.default.fileExists(atPath: url.path) else {
            StorageManager.logError(NSError(domain: "PDF", code: -1, userInfo: [NSLocalizedDescriptionKey: "File does not exist at path: \(url.path)"]), context: "PDF File Validation")
            return nil
        }
        
        // Check file size with error handling
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            StorageManager.logError(error, context: "PDF File Attributes")
            StorageManager.logSystemEvent("PDF Validation", details: "Failed to read file attributes: \(error.localizedDescription)")
            return nil
        }
        
        let fileSize = attributes[.size] as? Int64 ?? 0
        StorageManager.logSystemEvent("PDF Validation", details: "File size: \(fileSize) bytes")
        
        if fileSize == 0 {
            StorageManager.logError(NSError(domain: "PDF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty file"]), context: "PDF File Validation")
            return nil
        }
        
        // For File Provider Storage, isReadableFile might not work as expected
        // Let's try a different approach
        let isReadable = FileManager.default.isReadableFile(atPath: url.path)
        StorageManager.logSystemEvent("PDF Validation", details: "File readable check: \(isReadable)")
        
        // Try to get page count for validation - this is a good test of PDF accessibility
        var pageCount = 0
        do {
            if let pdfDoc = PDFDocument(url: url) {
                pageCount = pdfDoc.pageCount
                StorageManager.logSystemEvent("PDF Validation", details: "PDF document created successfully, pages: \(pageCount)")
            } else {
                StorageManager.logSystemEvent("PDF Validation", details: "Failed to create PDFDocument from URL")
            }
        } catch {
            StorageManager.logSystemEvent("PDF Validation", details: "Error creating PDFDocument: \(error.localizedDescription)")
        }
        
        return PDFFileInfo(
            exists: true,
            size: fileSize,
            pageCount: pageCount,
            isReadable: isReadable
        )
    }
    
    // MARK: - Strategy 1: Standard PDFKit
    
    private static func extractWithPDFKit(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Extraction", details: "Trying standard PDFKit approach")
        
        guard url.startAccessingSecurityScopedResource() else {
            StorageManager.logSystemEvent("PDF Extraction", details: "Failed to access security scoped resource")
            return nil
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            StorageManager.logSystemEvent("PDF Extraction", details: "Failed to create PDFDocument")
            return nil
        }
        
        return extractTextFromPDFDocument(pdfDocument)
    }
    
    // MARK: - Strategy 2: Enhanced PDFKit with Multiple Access Patterns
    
    private static func extractWithEnhancedPDFKit(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Extraction", details: "Trying enhanced PDFKit approach")
        
        guard url.startAccessingSecurityScopedResource() else {
            StorageManager.logSystemEvent("PDF Extraction", details: "Failed to access security scoped resource")
            return nil
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        var pdfDocument: PDFDocument?
        
        // Approach 1: Direct URL
        pdfDocument = PDFDocument(url: url)
        if pdfDocument != nil {
            StorageManager.logSystemEvent("PDF Extraction", details: "Direct URL approach succeeded")
            return extractTextFromPDFDocument(pdfDocument!)
        }
        
        // Approach 2: Data loading
        do {
            let data = try Data(contentsOf: url)
            pdfDocument = PDFDocument(data: data)
            if pdfDocument != nil {
                StorageManager.logSystemEvent("PDF Extraction", details: "Data loading approach succeeded")
                return extractTextFromPDFDocument(pdfDocument!)
            }
        } catch {
            StorageManager.logError(error, context: "PDF Data Loading")
        }
        
        // Approach 3: Temporary file copy
        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_pdf_\(UUID().uuidString).pdf")
            try FileManager.default.copyItem(at: url, to: tempURL)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            pdfDocument = PDFDocument(url: tempURL)
            if pdfDocument != nil {
                StorageManager.logSystemEvent("PDF Extraction", details: "Temporary file approach succeeded")
                return extractTextFromPDFDocument(pdfDocument!)
            }
        } catch {
            StorageManager.logError(error, context: "PDF Temporary File")
        }
        
        // Approach 4: File handle access
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            
            let fileData = fileHandle.readDataToEndOfFile()
            pdfDocument = PDFDocument(data: fileData)
            if pdfDocument != nil {
                StorageManager.logSystemEvent("PDF Extraction", details: "File handle approach succeeded")
                return extractTextFromPDFDocument(pdfDocument!)
            }
        } catch {
            StorageManager.logError(error, context: "PDF File Handle")
        }
        
        return nil
    }
    
    // MARK: - Strategy 3: File Provider Storage Specific Approach
    
    private static func extractFromFileProviderStorage(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Extraction", details: "Trying File Provider Storage specific approach")
        
        // For File Provider Storage, we need to be more careful with resource access
        let hasAccess = url.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage access: \(hasAccess)")
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Strategy 1: Copy to app's documents directory first
        do {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileName = url.lastPathComponent
            let localURL = documentsDirectory.appendingPathComponent("temp_pdf_\(UUID().uuidString)_\(fileName)")
            
            StorageManager.logSystemEvent("PDF Extraction", details: "Copying to local directory: \(localURL.path)")
            
            // Copy the file to a local directory
            try FileManager.default.copyItem(at: url, to: localURL)
            defer {
                try? FileManager.default.removeItem(at: localURL)
            }
            
            // Now try to extract from the local copy
            if let pdfDocument = PDFDocument(url: localURL) {
                StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage copy approach succeeded")
                return extractTextFromPDFDocument(pdfDocument)
            }
        } catch {
            StorageManager.logError(error, context: "File Provider Storage Copy")
            StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage copy failed: \(error.localizedDescription)")
        }
        
        // Strategy 2: Direct data access with chunked reading
        do {
            StorageManager.logSystemEvent("PDF Extraction", details: "Trying chunked data reading for File Provider Storage")
            
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            
            // Read data in chunks to handle large files
            var allData = Data()
            let chunkSize = 1024 * 1024 // 1MB chunks
            
            while true {
                let chunk = fileHandle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                allData.append(chunk)
            }
            
            StorageManager.logSystemEvent("PDF Extraction", details: "Read \(allData.count) bytes from File Provider Storage")
            
            if let pdfDocument = PDFDocument(data: allData) {
                StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage chunked reading succeeded")
                return extractTextFromPDFDocument(pdfDocument)
            }
        } catch {
            StorageManager.logError(error, context: "File Provider Storage Chunked Reading")
            StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage chunked reading failed: \(error.localizedDescription)")
        }
        
        // Strategy 3: Try with different URL access patterns
        do {
            // Sometimes File Provider Storage URLs need different handling
            let resourceValues = try url.resourceValues(forKeys: [.isReadableKey, .fileSizeKey])
            StorageManager.logSystemEvent("PDF Extraction", details: "Resource values - readable: \(resourceValues.isReadable ?? false), size: \(resourceValues.fileSize ?? 0)")
            
            if resourceValues.isReadable == true {
                if let pdfDocument = PDFDocument(url: url) {
                    StorageManager.logSystemEvent("PDF Extraction", details: "File Provider Storage direct access succeeded")
                    return extractTextFromPDFDocument(pdfDocument)
                }
            }
        } catch {
            StorageManager.logError(error, context: "File Provider Storage Resource Values")
        }
        
        StorageManager.logSystemEvent("PDF Extraction", details: "All File Provider Storage strategies failed")
        return nil
    }
    
    // MARK: - Strategy 4: Vision OCR for Image-based PDFs
    
    private static func extractWithVisionOCR(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Extraction", details: "Trying Vision OCR approach")
        
        guard #available(iOS 13.0, *) else {
            StorageManager.logSystemEvent("PDF Extraction", details: "Vision OCR not available on this iOS version")
            return nil
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            return nil
        }
        
        var allText = ""
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            // Convert PDF page to image
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { context in
                context.cgContext.translateBy(x: 0, y: pageRect.size.height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            
            // Extract text using Vision
            if let pageText = extractTextFromImage(image) {
                allText += pageText + "\n"
            }
        }
        
        return allText.isEmpty ? nil : allText
    }
    
    @available(iOS 13.0, *)
    private static func extractTextFromImage(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                StorageManager.logError(error, context: "Vision OCR")
                return
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results else { return nil }
            
            var extractedText = ""
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                extractedText += topCandidate.string + " "
            }
            
            return extractedText.isEmpty ? nil : extractedText
        } catch {
            StorageManager.logError(error, context: "Vision OCR Processing")
            return nil
        }
    }
    
    // MARK: - Strategy 4: Hybrid Approach
    
    private static func extractWithHybridApproach(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Extraction", details: "Trying hybrid approach")
        
        guard let pdfDocument = PDFDocument(url: url) else {
            return nil
        }
        
        var allText = ""
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            // Try PDFKit text extraction first
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += pageText + "\n"
                StorageManager.logSystemEvent("PDF Page Processing", details: "Page \(pageIndex + 1): PDFKit text extraction")
            } else if #available(iOS 13.0, *) {
                // Fallback to Vision OCR for this page
                let pageRect = page.bounds(for: .mediaBox)
                let renderer = UIGraphicsImageRenderer(size: pageRect.size)
                let image = renderer.image { context in
                    context.cgContext.translateBy(x: 0, y: pageRect.size.height)
                    context.cgContext.scaleBy(x: 1.0, y: -1.0)
                    page.draw(with: .mediaBox, to: context.cgContext)
                }
                
                if let pageText = extractTextFromImage(image) {
                    allText += pageText + "\n"
                    StorageManager.logSystemEvent("PDF Page Processing", details: "Page \(pageIndex + 1): Vision OCR extraction")
                }
            }
        }
        
        return allText.isEmpty ? nil : allText
    }
    
    // MARK: - Common PDF Text Extraction
    
    private static func extractTextFromPDFDocument(_ pdfDocument: PDFDocument) -> String? {
        let pageCount = pdfDocument.pageCount
        
        if pageCount == 0 {
            StorageManager.logError(NSError(domain: "PDF", code: -4, userInfo: [NSLocalizedDescriptionKey: "Empty PDF document (0 pages)"]), context: "PDF Page Count Check")
            return nil
        }
        
        var extractedText = ""
        var pagesWithText = 0
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                StorageManager.logSystemEvent("PDF Page Processing", details: "Could not access page \(pageIndex)")
                continue
            }
            
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extractedText += pageText + "\n"
                pagesWithText += 1
            } else {
                StorageManager.logSystemEvent("PDF Page Processing", details: "Page \(pageIndex + 1) has no extractable text")
            }
        }
        
        StorageManager.logSystemEvent("PDF Text Extraction", details: "Extracted text from \(pagesWithText)/\(pageCount) pages")
        
        if extractedText.isEmpty {
            StorageManager.logError(NSError(domain: "PDF", code: -5, userInfo: [NSLocalizedDescriptionKey: "No text extracted from PDF"]), context: "PDF Text Extraction")
            return nil
        }
        
        return extractedText
    }
    
    // MARK: - Enhanced Text Chunking (Mirrors AeRU Original)
    
    private static func countTokens(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        let tokens = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        return tokens.count
    }
    
    static func chunkText(_ text: String, maxChunkSize: Int = 3500, overlapTokens: Int = 125) -> [String] {
        // Convert maxChunkSize from characters to approximate tokens (roughly 4 chars per token)
        let maxTokens = maxChunkSize / 4
        
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { sentence in
                sentence.hasSuffix(".") || sentence.hasSuffix("!") || sentence.hasSuffix("?") ? 
                sentence : sentence + "."
            }
        
        var chunks: [String] = []
        var currentChunk = ""
        var currentTokenCount = 0
        var previousChunkSentences: [String] = []
        
        for sentence in sentences {
            let sentenceTokenCount = countTokens(in: sentence)
            let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence
            let potentialTokenCount = currentTokenCount + sentenceTokenCount + (currentChunk.isEmpty ? 0 : 1)
            
            if potentialTokenCount <= maxTokens {
                currentChunk = potentialChunk
                currentTokenCount = potentialTokenCount
            } else {
                // Current chunk is ready, save it
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    
                    // Store sentences for overlap calculation
                    let chunkSentences = currentChunk.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    previousChunkSentences = chunkSentences
                }
                
                // Start new chunk with overlap from previous chunk
                var overlapText = ""
                var overlapTokenCount = 0
                
                if !previousChunkSentences.isEmpty && chunks.count > 0 {
                    // Take sentences from the end of previous chunk for overlap
                    for sentenceIndex in stride(from: previousChunkSentences.count - 1, through: 0, by: -1) {
                        let overlapSentence = previousChunkSentences[sentenceIndex]
                        let overlapSentenceTokens = countTokens(in: overlapSentence)
                        
                        if overlapTokenCount + overlapSentenceTokens <= overlapTokens {
                            overlapText = overlapSentence + (overlapText.isEmpty ? "" : " " + overlapText)
                            overlapTokenCount += overlapSentenceTokens
                        } else {
                            break
                        }
                    }
                }
                
                // Start new chunk with overlap + current sentence
                if sentenceTokenCount <= maxTokens {
                    if !overlapText.isEmpty {
                        currentChunk = overlapText + " " + sentence
                        currentTokenCount = overlapTokenCount + sentenceTokenCount + 1
                    } else {
                        currentChunk = sentence
                        currentTokenCount = sentenceTokenCount
                    }
                } else {
                    // Sentence is too long, truncate it
                    let words = sentence.components(separatedBy: .whitespaces)
                    var truncatedSentence = ""
                    var truncatedTokenCount = 0
                    
                    for word in words {
                        let wordTokenCount = countTokens(in: word)
                        if truncatedTokenCount + wordTokenCount <= maxTokens {
                            truncatedSentence += (truncatedSentence.isEmpty ? "" : " ") + word
                            truncatedTokenCount += wordTokenCount
                        } else {
                            break
                        }
                    }
                    
                    if !truncatedSentence.isEmpty {
                        if !truncatedSentence.hasSuffix(".") && !truncatedSentence.hasSuffix("!") && !truncatedSentence.hasSuffix("?") {
                            truncatedSentence += "."
                        }
                        chunks.append(truncatedSentence)
                    }
                    currentChunk = ""
                    currentTokenCount = 0
                }
            }
        }
        
        // Add the final chunk if not empty
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks.filter { !$0.isEmpty }
    }
    
    // MARK: - Document Storage (Mirrors AeRU Original)
    
    static func saveDocumentToLocalStorage(_ data: Data, fileName: String) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            StorageManager.logError(NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Documents directory not accessible"]), context: "Document Storage")
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("Documents").appendingPathComponent(fileName)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL)
            StorageManager.logSystemEvent("Document Storage", details: "Saved document: \(fileName)")
            return fileURL
        } catch {
            StorageManager.logError(error, context: "Document Storage")
            return nil
        }
    }
    
    // MARK: - Document Processing Pipeline
    
    /// Complete document processing pipeline that mirrors AeRU original
    static func processDocument(url: URL, for session: ChatSession) async -> Bool {
        StorageManager.logUserAction("Enhanced PDF Processing Started", details: "File: \(url.lastPathComponent)")
        
        let hasAccess = url.startAccessingSecurityScopedResource()
        StorageManager.logSystemEvent("Security Scoped Resource", details: "Access result: \(hasAccess)")
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
                StorageManager.logSystemEvent("Security Scoped Resource", details: "Released access")
            }
        }
        
        let extractStartTime = Date()
        guard let extractedText = extractTextFromPDF(at: url) else {
            StorageManager.logUserAction("Enhanced PDF Processing Failed", details: "Text extraction failed for \(url.lastPathComponent)")
            return false
        }
        let extractDuration = Date().timeIntervalSince(extractStartTime)
        StorageManager.logPerformance("Enhanced PDF Text Extraction", duration: extractDuration, details: "Extracted \(extractedText.count) characters")
        
        let originalFileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = originalFileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let uniqueFileName = "\(baseName)_\(UUID().uuidString).\(fileExtension)"
        
        // Save document to local storage
        let data = extractedText.data(using: String.Encoding.utf8) ?? Data()
        guard saveDocumentToLocalStorage(data, fileName: uniqueFileName) != nil else {
            StorageManager.logUserAction("Enhanced PDF Processing Failed", details: "Failed to save document locally")
            return false
        }
        
        // Save to database (if database manager is available)
        // Note: This would need to be adapted based on your specific database implementation
        // databaseManager.saveDocument(
        //     sessionId: session.id,
        //     name: originalFileName,
        //     path: savedURL.path,
        //     type: "PDF"
        // )
        
        StorageManager.logUserAction("Enhanced PDF Processing Success", details: "File: \(originalFileName), Duration: \(String(format: "%.2f", extractDuration))s")
        return true
    }
    
    // MARK: - Utility Methods
    
    /// Check if file is a valid PDF
    static func isValidPDF(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        
        // Check file extension
        if url.pathExtension.lowercased() != "pdf" {
            return false
        }
        
        // Try to create PDFDocument to validate
        guard let pdfDocument = PDFDocument(url: url) else {
            return false
        }
        
        return pdfDocument.pageCount > 0
    }
    
    /// Get PDF metadata
    static func getPDFMetadata(at url: URL) -> [String: Any]? {
        guard let pdfDocument = PDFDocument(url: url) else { return nil }
        
        var metadata: [String: Any] = [:]
        metadata["pageCount"] = pdfDocument.pageCount
        
        // Add basic document attributes without complex type conversion
        if let documentAttributes = pdfDocument.documentAttributes {
            for (key, value) in documentAttributes {
                if let stringKey = key as? String {
                    metadata[stringKey] = value
                }
            }
        }
        
        return metadata
    }
}
