//
//  AeruDocumentProcessor.swift
//  WhisperControlMobile
//
//  Ported from AeRU working DocumentProcessor with improvements
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
        
        // Use AeRU's simpler, more reliable approach
        guard url.startAccessingSecurityScopedResource() else {
            StorageManager.logSystemEvent("Security Scoped Resource", details: "Failed to access: \(url.lastPathComponent)")
            print("Failed to access security scoped resource")
            return nil
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
            StorageManager.logSystemEvent("Security Scoped Resource", details: "Released access for: \(url.lastPathComponent)")
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            StorageManager.logError(NSError(domain: "PDF", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDFDocument"]), context: "PDF Document Creation")
            print("Failed to create PDF document from URL: \(url)")
            return nil
        }
        
        let pageCount = pdfDocument.pageCount
        print("INFO: PDF has \(pageCount) pages")
        
        if pageCount == 0 {
            StorageManager.logError(NSError(domain: "PDF", code: -4, userInfo: [NSLocalizedDescriptionKey: "Empty PDF document (0 pages)"]), context: "PDF Page Count Check")
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
            StorageManager.logError(NSError(domain: "PDF", code: -5, userInfo: [NSLocalizedDescriptionKey: "No text extracted from PDF"]), context: "PDF Text Extraction")
            print("ERROR: No text could be extracted from PDF - document may be image-based or corrupted")
            return nil
        }
        
        StorageManager.logSystemEvent("PDF Processing End", details: "Extracted \(extractedText.count) characters")
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
