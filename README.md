# Aeru: Enhanced Apple Intelligence + Whisper Transcription

> **An intelligent iOS application that combines Whisper transcription, Retrieval-Augmented Generation (RAG), and Apple FoundationModels for comprehensive on-device AI transcription and analysis.**

Aeru is a powerful iOS app that leverages Apple's FoundationModels framework and WhisperKit for transcription, delivering intelligent responses by searching both local knowledge bases and real-time web content. Built with SwiftUI and optimized for iOS 26.0+, it provides a seamless experience for transcription and AI-powered analysis.

## 🎯 Features

### 🎤 **Advanced Transcription**
- **Apple Native Speech Recognition:** Real-time, on-device transcription
- **WhisperKit CoreML Models:** Offline transcription with multiple model sizes (Tiny, Base, Small)
- **Live Transcription:** Continuous audio capture with real-time text generation
- **Audio Import:** Support for various audio formats from Files, Photos, and other apps

### 🧠 **AI-Powered Intelligence**
- **Apple FoundationModels:** Native integration with Apple's language models (iOS 26.0+)
- **RAG System:** Local vector database for semantic search and context-aware responses
- **Document Processing:** PDF and text file processing for knowledge base creation
- **Voice Mode:** Hands-free interaction with AI using natural speech

### 💻 **Native iOS Experience**
- **SwiftUI Interface:** Modern, responsive design with iOS 26 Liquid Glass effects
- **Real-time Streaming:** Live response generation with streaming updates
- **File Management:** Comprehensive import/export capabilities
- **Privacy-First:** All processing occurs on-device

### 🔧 **Technical Excellence**
- **Vector Database:** SVDB integration for efficient similarity search
- **CoreML Integration:** On-device Whisper model processing
- **NaturalLanguage Framework:** Semantic embeddings and text processing
- **Robust Error Handling:** Graceful degradation and comprehensive logging

## 🛠 Installation

### Prerequisites

- **iPhone 15 Pro or higher end model REQUIRED** (for FoundationModels)
- **iOS 26.0+ REQUIRED** (for FoundationModels and advanced features)
- **Xcode 16.0+**
- **Swift 6+**
- **Apple Developer Account** (for device testing)

### Setup Instructions

1. **Clone the Repository**
   ```bash
   git clone https://github.com/Doodle-Med/Aeru-and-transcription-notetaking-beast.git
   cd Aeru-and-transcription-notetaking-beast
   ```

2. **Open in Xcode**
   ```bash
   open ProductionApp/WhisperControlMobile.xcodeproj
   ```

3. **Install Dependencies**
   Dependencies are automatically managed through Xcode's built-in Swift Package Manager integration:
   - **WhisperKit**: CoreML transcription engine
   - **SVDB**: Vector database operations
   - **SwiftSoup**: HTML parsing and content extraction
   - **FoundationModels**: Apple's language model framework
   - **NaturalLanguage**: Text embeddings and processing
   - **Accelerate**: High-performance vector operations

4. **Download Whisper Models**
   ```bash
   cd ProductionApp
   ./setup_models.sh
   ```
   This downloads the required CoreML models (73MB - 1.5GB total).

5. **Configure Signing**
   - Select your development team in Xcode
   - Ensure proper provisioning profiles are configured
   - Note: Audio processing entitlements may require Apple Developer Support request

6. **Build and Run**
   - Press `Cmd+R` or click the play button in Xcode
   - The app will launch with the main transcription interface

## 🚦 Usage

### Transcription Features

1. **Live Transcription**: 
   - Tap the microphone button to start real-time transcription
   - Choose between Apple Native or WhisperKit backends
   - Save transcriptions with optional audio recording

2. **Audio Import**:
   - Import audio files from Files app, Photos, or other sources
   - Process with WhisperKit models for offline transcription
   - Support for various audio formats

3. **Document Processing**:
   - Import PDFs and text files for RAG processing
   - Automatic text extraction and vector embedding generation
   - Semantic search through your document collection

### AI Features

1. **RAG Chat**:
   - Ask questions about your transcribed content and documents
   - Get contextually aware responses using local knowledge base
   - Maintain conversation history across sessions

2. **Database Management**:
   - View and manage your RAG database
   - Edit or delete specific documents
   - Analyze vector distribution and search quality

3. **Voice Interaction**:
   - Use voice mode for hands-free AI interaction
   - Natural speech-to-text with intelligent responses

## 🏗 Architecture

### Core Components

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│  WhisperControl     │    │   Transcription     │    │    RAG System       │
│  MobileApp.swift    │◄──►│   Engine (CoreML)   │◄──►│   (SVDB + NLP)     │
│   (Main App)        │    │                     │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
           │                           │                           │
           ▼                           ▼                           ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   LiveTranscription │    │   AudioRecorder     │    │  FoundationModels   │
│   Manager           │    │   & Capture         │    │  (AI Responses)     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

### Data Flow

1. **Audio Input** → LiveTranscriptionManager captures audio streams
2. **Transcription** → WhisperKit/CoreML processes audio to text
3. **RAG Indexing** → Transcriptions are embedded and stored in vector database
4. **AI Processing** → FoundationModels generates intelligent responses
5. **User Interface** → SwiftUI updates with real-time results

### Key Technologies

- **SwiftUI**: Reactive UI framework with iOS 26 Liquid Glass effects
- **Combine**: Reactive programming for data flow
- **WhisperKit**: CoreML-based transcription engine
- **FoundationModels**: Apple's on-device language models
- **SVDB**: Vector database for semantic search
- **NaturalLanguage**: Text embeddings and processing
- **AVFoundation**: Audio capture and processing

## 🔒 Privacy & Security

- **On-Device Processing**: All audio, transcription, and AI processing occurs locally
- **No External Servers**: No data transmission to external services
- **iOS Sandboxing**: App data protected by iOS security model
- **User Control**: Full control over data retention and sharing

See [Privacy Policy](ProductionApp/privacy-policy-site/) for detailed information.

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and test thoroughly
4. Commit with clear messages: `git commit -m 'Add amazing feature'`
5. Push to your branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

### Code Standards

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Include unit tests for new functionality
- Maintain documentation for public APIs
- Ensure Xcode builds without warnings

### Areas for Contribution

- 🐛 **Bug Fixes**: Help improve stability and compatibility
- ✨ **Features**: Add new transcription or AI capabilities
- 📚 **Documentation**: Improve guides and examples
- 🧪 **Testing**: Expand test coverage
- 🎨 **UI/UX**: Enhance user experience

## 📋 Requirements

### Device Requirements
- **iPhone 15 Pro or later** (for FoundationModels)
- **iOS 26.0+** (for full feature set)
- **Minimum 4GB RAM** (for WhisperKit models)

### Development Requirements
- **Xcode 16.0+**
- **Swift 6+**
- **Apple Developer Account**
- **macOS 14.0+** (for development)

## 🚨 Known Issues

- FoundationModels requires Apple Intelligence activated device
- Audio processing entitlements may need Apple Developer Support approval
- Some features limited on simulator vs. physical device
- Large model files (up to 293MB each) are not included in Git - use setup script to download

## 📄 License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Apple**: For FoundationModels, NaturalLanguage, and CoreML frameworks
- **OpenAI**: For Whisper transcription models
- **WhisperKit**: For CoreML integration
- **SVDB**: Vector database library
- **Open Source Community**: For inspiration and support

## 📞 Support

- **GitHub Issues**: [Report bugs and request features](https://github.com/Doodle-Med/Aeru-and-transcription-notetaking-beast/issues)
- **Privacy Policy**: [ProductionApp/privacy-policy-site/](ProductionApp/privacy-policy-site/)
- **Developer**: Joseph Hennig

---

**Built with ❤️ for the iOS community**

*Combining the power of Whisper transcription with Apple Intelligence for the ultimate on-device transcription and AI experience.*
