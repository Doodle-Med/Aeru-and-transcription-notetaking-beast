//
//  DocumentProcessor.swift
//  Aeru
//
//  Created by Sanskar
//

import Foundation
import PDFKit
import NaturalLanguage

class DocumentProcessor {
    
    static func extractTextFromPDF(at url: URL) -> String? {
        StorageManager.logSystemEvent("PDF Processing Start", details: "URL: \(url.lastPathComponent)")
        
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            StorageManager.logError(NSError(domain: "PDF", code: -1, userInfo: [NSLocalizedDescriptionKey: "File does not exist"]), context: "PDF File Check")
            print("ERROR: PDF file does not exist at path: \(url.path)")
            return nil
        }
        
        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            StorageManager.logSystemEvent("PDF File Size", details: "\(fileSize) bytes")
            print("INFO: PDF file size: \(fileSize) bytes")
            
            if fileSize == 0 {
                StorageManager.logError(NSError(domain: "PDF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty file"]), context: "PDF File Size Check")
                print("ERROR: PDF file is empty (0 bytes)")
                return nil
            }
        } catch {
            StorageManager.logError(error, context: "PDF File Attributes")
            print("WARNING: Could not read file attributes: \(error)")
        }
        
        // Try to create PDF document with better error handling and device-specific approaches
        StorageManager.logSystemEvent("PDF Document Creation", details: "Attempting to create PDFDocument")
        
        // Try multiple approaches for PDF document creation
        var pdfDocument: PDFDocument?
        
        // Approach 1: Direct URL creation
        pdfDocument = PDFDocument(url: url)
        if pdfDocument != nil {
            StorageManager.logSystemEvent("PDF Document Creation", details: "Success with direct URL - Page count: \(pdfDocument!.pageCount)")
        } else {
            StorageManager.logSystemEvent("PDF Document Creation", details: "Direct URL failed, trying data approach")
            
            // Approach 2: Load from data (for device compatibility issues)
            do {
                let data = try Data(contentsOf: url)
                pdfDocument = PDFDocument(data: data)
                if pdfDocument != nil {
                    StorageManager.logSystemEvent("PDF Document Creation", details: "Success with data approach - Page count: \(pdfDocument!.pageCount)")
                }
            } catch {
                StorageManager.logError(error, context: "PDF Data Loading")
                StorageManager.logSystemEvent("PDF Document Creation", details: "Data approach failed: \(error.localizedDescription)")
                
        // Approach 3: Copy to temporary location and try again
                        StorageManager.logSystemEvent("PDF Document Creation", details: "Trying temporary file copy approach")
                        do {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_pdf_\(UUID().uuidString).pdf")
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            defer { 
                                try? FileManager.default.removeItem(at: tempURL) // Clean up temp file
                            }
                            
                            pdfDocument = PDFDocument(url: tempURL)
                            if pdfDocument != nil {
                                StorageManager.logSystemEvent("PDF Document Creation", details: "Success with temp file approach - Page count: \(pdfDocument!.pageCount)")
                            } else {
                                // Try data approach with temp file
                                let tempData = try Data(contentsOf: tempURL)
                                pdfDocument = PDFDocument(data: tempData)
                                if pdfDocument != nil {
                                    StorageManager.logSystemEvent("PDF Document Creation", details: "Success with temp file data approach - Page count: \(pdfDocument!.pageCount)")
                                }
                            }
                        } catch {
                            StorageManager.logError(error, context: "PDF Temp File Approach")
                            StorageManager.logSystemEvent("PDF Document Creation", details: "Temp file approach failed: \(error.localizedDescription)")
                        }
                        
                        // Approach 4: Try with different file access permissions
                        if pdfDocument == nil {
                            StorageManager.logSystemEvent("PDF Document Creation", details: "Trying secure file access approach")
                            do {
                                // Try reading the file with different access patterns
                                let fileHandle = try FileHandle(forReadingFrom: url)
                                defer { fileHandle.closeFile() }
                                
                                let fileData = fileHandle.readDataToEndOfFile()
                                pdfDocument = PDFDocument(data: fileData)
                                if pdfDocument != nil {
                                    StorageManager.logSystemEvent("PDF Document Creation", details: "Success with file handle approach - Page count: \(pdfDocument!.pageCount)")
                                }
                            } catch {
                                StorageManager.logError(error, context: "PDF File Handle Approach")
                                StorageManager.logSystemEvent("PDF Document Creation", details: "File handle approach failed: \(error.localizedDescription)")
                            }
                        }
            }
        }
        
        guard let pdfDocument = pdfDocument else {
            StorageManager.logError(NSError(domain: "PDF", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDFDocument"]), context: "PDF Document Creation")
            print("ERROR: Failed to create PDF document from URL: \(url)")
            print("ERROR: This could be due to:")
            print("  - Corrupted PDF file")
            print("  - Password-protected PDF")
            print("  - Unsupported PDF format")
            print("  - File access permissions")
            print("  - Device-specific PDFKit compatibility issues")
            return nil
        }
        StorageManager.logSystemEvent("PDF Document Creation", details: "Final success - Page count: \(pdfDocument.pageCount)")
        
        let pageCount = pdfDocument.pageCount
        print("INFO: PDF has \(pageCount) pages")
        
        if pageCount == 0 {
            print("ERROR: PDF document has no pages")
            return nil
        }
        
        var extractedText = ""
        var pagesWithText = 0
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { 
                print("WARNING: Could not access page \(pageIndex)")
                continue 
            }
            
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extractedText += pageText + "\n"
                pagesWithText += 1
            } else {
                print("INFO: Page \(pageIndex + 1) has no extractable text")
            }
        }
        
        print("INFO: Successfully extracted text from \(pagesWithText)/\(pageCount) pages")
        print("INFO: Total extracted text length: \(extractedText.count) characters")
        
        if extractedText.isEmpty {
            print("ERROR: No text could be extracted from PDF - document may be image-based or corrupted")
            return nil
        }
        
        return extractedText
    }
    
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
    
    static func saveDocumentToLocalStorage(_ data: Data, fileName: String) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("Documents").appendingPathComponent(fileName)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save document: \(error)")
            return nil
        }
    }
}
}