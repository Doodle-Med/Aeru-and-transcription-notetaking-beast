import SwiftUI

struct APISettingsView: View {
    @StateObject private var apiManager = APIServiceManager.shared
    @State private var showingAPIKeyAlert = false
    @State private var selectedService: APIService = .gemini
    @State private var tempAPIKey = ""
    @State private var testingConnection = false
    @State private var connectionStatus: [APIService: Bool] = [:]
    
    var body: some View {
        NavigationView {
            Form {
                // API Configuration Section
                Section("API Configuration") {
                    Toggle("Enable API Transcription", isOn: $apiManager.configuration.enableAPITranscription)
                        .onChange(of: apiManager.configuration.enableAPITranscription) { _ in
                            apiManager.saveConfiguration()
                        }
                    
                    if apiManager.configuration.enableAPITranscription {
                        Picker("Transcription API", selection: $apiManager.configuration.selectedTranscriptionAPI) {
                            ForEach(APIService.allCases) { service in
                                Label(service.displayName, systemImage: service.icon)
                                    .tag(service)
                            }
                        }
                        .onChange(of: apiManager.configuration.selectedTranscriptionAPI) { _ in
                            apiManager.saveConfiguration()
                        }
                    }
                    
                    Toggle("Enable API LLM", isOn: $apiManager.configuration.enableAPILLM)
                        .onChange(of: apiManager.configuration.enableAPILLM) { _ in
                            apiManager.saveConfiguration()
                        }
                    
                    if apiManager.configuration.enableAPILLM {
                        Picker("LLM API", selection: $apiManager.configuration.selectedLLMAPI) {
                            ForEach(APIService.allCases) { service in
                                Label(service.displayName, systemImage: service.icon)
                                    .tag(service)
                            }
                        }
                        .onChange(of: apiManager.configuration.selectedLLMAPI) { _ in
                            apiManager.saveConfiguration()
                        }
                    }
                }
                
                // API Keys Section
                Section("API Keys") {
                    ForEach(APIService.allCases) { service in
                        APIServiceRow(
                            service: service,
                            apiKey: apiManager.getAPIKey(for: service),
                            isConfigured: apiManager.isAPIConfigured(for: service),
                            connectionStatus: connectionStatus[service],
                            onSetAPIKey: {
                                selectedService = service
                                tempAPIKey = apiManager.getAPIKey(for: service)
                                showingAPIKeyAlert = true
                            },
                            onTestConnection: {
                                Task {
                                    await testConnection(for: service)
                                }
                            }
                        )
                    }
                }
                
                // Usage Information
                Section("Usage Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Integration")
                            .font(.headline)
                        
                        Text("• API transcription can be used as an alternative to local Whisper models")
                        Text("• API LLM can be used as an alternative to local FoundationModels")
                        Text("• API keys are stored securely on your device")
                        Text("• All API calls are made directly from your device")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("API Settings")
            .alert("Set API Key", isPresented: $showingAPIKeyAlert) {
                TextField("API Key", text: $tempAPIKey)
                Button("Save") {
                    apiManager.setAPIKey(tempAPIKey, for: selectedService)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter your \(selectedService.displayName) API key:")
            }
        }
    }
    
    private func testConnection(for service: APIService) async {
        testingConnection = true
        let isConnected = await apiManager.testAPIConnection(for: service)
        await MainActor.run {
            connectionStatus[service] = isConnected
            testingConnection = false
        }
    }
}

struct APIServiceRow: View {
    let service: APIService
    let apiKey: String
    let isConfigured: Bool
    let connectionStatus: Bool?
    let onSetAPIKey: () -> Void
    let onTestConnection: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: service.icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.headline)
                
                HStack {
                    if isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Configured")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("Not configured")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let status = connectionStatus {
                        Spacer()
                        if status {
                            Image(systemName: "wifi")
                                .foregroundColor(.green)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.red)
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Set Key") {
                    onSetAPIKey()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if isConfigured {
                    Button("Test") {
                        onTestConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    APISettingsView()
}
