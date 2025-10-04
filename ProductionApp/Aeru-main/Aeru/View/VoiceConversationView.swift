//
//  VoiceConversationView.swift
//  Aeru
//
//  Created by Sanskar
//

import SwiftUI
import MarkdownUI

@available(iOS 16.0, *)
struct VoiceConversationView: View {
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject private var textToSpeechManager = TextToSpeechManager()
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var userText: String = ""
    @State private var aiResponse: String = ""
    @State private var isWaitingForResponse: Bool = false
    @State private var isInLiveMode: Bool = false
    @State private var conversationHistory: [(user: String, ai: String)] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Conversation Content
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, exchange in
                            VStack(spacing: 12) {
                                // User message
                                HStack {
                                    Spacer(minLength: 50)
                                    Text(exchange.user)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(20.0)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.blue)
                                        )
                                        .foregroundColor(colorScheme == .dark ? .white : .secondary)
                                }
                                
                                // AI response
                                HStack {
                                    Markdown(exchange.ai)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(20.0)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color(.systemGray5))
                                        )
                                        .foregroundColor(.primary)
                                    
                                    Spacer(minLength: 50)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Control Buttons
                VStack(spacing: 16) {
                    if !isInLiveMode {
                        Button(action: startLiveMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20, weight: .medium))
                                
                                Text("Start Live Conversation")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    } else {
                        Button(action: stopLiveMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20, weight: .medium))
                                
                                Text("Stop Conversation")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding()
            .navigationTitle("Voice Conversation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func startLiveMode() {
        isInLiveMode = true
        speechRecognitionManager.startRecording()
    }
    
    private func stopLiveMode() {
        isInLiveMode = false
        speechRecognitionManager.stopRecording()
    }
}

#Preview {
    VoiceConversationView()
}