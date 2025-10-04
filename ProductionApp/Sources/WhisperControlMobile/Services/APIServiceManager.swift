import Foundation
import Combine

enum APIService: String, CaseIterable, Identifiable, Codable {
    case gemini = "gemini"
    case gemma = "gemma"
    case openai = "openai"
    case anthropic = "anthropic"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .gemma: return "Google Gemma"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        }
    }
    
    var icon: String {
        switch self {
        case .gemini: return "brain.head.profile"
        case .gemma: return "brain.head.profile"
        case .openai: return "sparkles"
        case .anthropic: return "person.crop.circle"
        }
    }
}

struct APIConfiguration: Codable {
    var geminiAPIKey: String = ""
    var gemmaAPIKey: String = ""
    var openaiAPIKey: String = ""
    var anthropicAPIKey: String = ""
    var selectedTranscriptionAPI: APIService = .openai
    var selectedLLMAPI: APIService = .gemini
    var enableAPITranscription: Bool = false
    var enableAPILLM: Bool = false
}

@MainActor
class APIServiceManager: ObservableObject {
    static let shared = APIServiceManager()
    
    @Published var configuration = APIConfiguration()
    
    private let userDefaults = UserDefaults.standard
    private let configurationKey = "APIConfiguration"
    
    private init() {
        loadConfiguration()
    }
    
    func loadConfiguration() {
        if let data = userDefaults.data(forKey: configurationKey),
           let config = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            self.configuration = config
        }
    }
    
    func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }
    
    func getAPIKey(for service: APIService) -> String {
        switch service {
        case .gemini: return configuration.geminiAPIKey
        case .gemma: return configuration.gemmaAPIKey
        case .openai: return configuration.openaiAPIKey
        case .anthropic: return configuration.anthropicAPIKey
        }
    }
    
    func setAPIKey(_ key: String, for service: APIService) {
        switch service {
        case .gemini: configuration.geminiAPIKey = key
        case .gemma: configuration.gemmaAPIKey = key
        case .openai: configuration.openaiAPIKey = key
        case .anthropic: configuration.anthropicAPIKey = key
        }
        saveConfiguration()
    }
    
    func isAPIConfigured(for service: APIService) -> Bool {
        return !getAPIKey(for: service).isEmpty
    }
    
    func testAPIConnection(for service: APIService) async -> Bool {
        let apiKey = getAPIKey(for: service)
        guard !apiKey.isEmpty else { return false }
        
        // Implement actual API test calls here
        // For now, just return true if API key is present
        return true
    }
}

// MARK: - API Service Implementations

class GeminiAPIService {
    let apiKey: String  // Changed from private to internal
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateText(prompt: String, context: String? = nil) async throws -> String {
        let fullPrompt = context != nil ? "\(context!)\n\n\(prompt)" : prompt
        
        let url = URL(string: "\(baseURL)/models/gemini-pro:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048,
                "topP": 0.95,
                "topK": 40
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GeminiAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return text
    }
    
    func streamGenerateText(prompt: String, context: String? = nil) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let fullPrompt = context != nil ? "\(context!)\n\n\(prompt)" : prompt
                    
                    let url = URL(string: "\(baseURL)/models/gemini-pro:streamGenerateContent?key=\(apiKey)")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let requestBody: [String: Any] = [
                        "contents": [
                            [
                                "parts": [
                                    ["text": fullPrompt]
                                ]
                            ]
                        ],
                        "generationConfig": [
                            "temperature": 0.7,
                            "maxOutputTokens": 2048,
                            "topP": 0.95,
                            "topK": 40
                        ]
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }
                    
                    var accumulatedText = ""
                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        
                        // Remove "data: " prefix if present
                        let jsonLine = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
                        
                        if let data = jsonLine.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let candidates = json["candidates"] as? [[String: Any]],
                           let firstCandidate = candidates.first,
                           let content = firstCandidate["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String {
                            accumulatedText += text
                            continuation.yield(accumulatedText)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func transcribeAudio(audioData: Data) async throws -> String {
        // Gemini doesn't have audio transcription yet, so this would use another service
        throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gemini doesn't support audio transcription yet. Use OpenAI Whisper or Google Speech-to-Text."])
    }
}

class GemmaAPIService {
    private let apiKey: String
    private let baseURL = "https://api.google.com/v1" // Placeholder URL
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateText(prompt: String, context: String? = nil) async throws -> String {
        // Implement Gemma API call
        let fullPrompt = context != nil ? "Context: \(context!)\n\nQuestion: \(prompt)" : prompt
        
        // Placeholder implementation
        return "Gemma response for: \(fullPrompt)"
    }
    
    func transcribeAudio(audioData: Data) async throws -> String {
        // Implement Gemma audio transcription
        return "Gemma transcription result"
    }
}

class OpenAIAPIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateText(prompt: String, context: String? = nil) async throws -> String {
        // Implement OpenAI API call
        let fullPrompt = context != nil ? "Context: \(context!)\n\nQuestion: \(prompt)" : prompt
        
        // Placeholder implementation
        return "OpenAI response for: \(fullPrompt)"
    }
    
    func transcribeAudio(audioData: Data) async throws -> String {
        // Implement OpenAI Whisper API call
        return "OpenAI Whisper transcription result"
    }
}

class AnthropicAPIService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateText(prompt: String, context: String? = nil) async throws -> String {
        // Implement Anthropic API call
        let fullPrompt = context != nil ? "Context: \(context!)\n\nQuestion: \(prompt)" : prompt
        
        // Placeholder implementation
        return "Anthropic Claude response for: \(fullPrompt)"
    }
    
    func transcribeAudio(audioData: Data) async throws -> String {
        // Anthropic doesn't have audio transcription, so this would delegate to another service
        throw NSError(domain: "AnthropicAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Anthropic doesn't support audio transcription"])
    }
}

// MARK: - API Service Factory

class APIServiceFactory {
    static func createService(for type: APIService, apiKey: String) -> Any {
        switch type {
        case .gemini:
            return GeminiAPIService(apiKey: apiKey)
        case .gemma:
            return GemmaAPIService(apiKey: apiKey)
        case .openai:
            return OpenAIAPIService(apiKey: apiKey)
        case .anthropic:
            return AnthropicAPIService(apiKey: apiKey)
        }
    }
}
