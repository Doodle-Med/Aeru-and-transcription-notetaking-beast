import AVFoundation

struct PreparedAudioFile {
    let url: URL
    let duration: TimeInterval
}

enum AudioProcessing {
    private static let targetSampleRate: Double = 16_000
    private static let targetChannels: AVAudioChannelCount = 1

    static func normalize(_ buffer: AVAudioPCMBuffer, targetRMS: Float = 0.2) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }

        let samples = channelData[0]
        var sumSquares: Float = 0
        var maxAbs: Float = 0

        for i in 0..<frames {
            let value = samples[i]
            sumSquares += value * value
            maxAbs = max(maxAbs, fabsf(value))
        }

        let rms = sqrtf(sumSquares / Float(frames))
        let epsilon: Float = 1e-7
        var gain = targetRMS / max(rms, epsilon)
        if maxAbs > 0 { gain = min(gain, 1.0 / maxAbs) }
        if gain.isNaN || gain.isInfinite { gain = 1 }

        // Debug audio levels occasionally
        if Int.random(in: 0..<100) == 0 { // 1% chance
            print("[AUDIO] RMS: \(String(format: "%.4f", rms)), Max: \(String(format: "%.4f", maxAbs)), Gain: \(String(format: "%.2f", gain))")
        }

        for i in 0..<frames {
            let normalized = max(min(samples[i] * gain, 1.0), -1.0)
            samples[i] = normalized
        }
    }

    static func copyFloat32ToInt16(source: AVAudioPCMBuffer, destination: AVAudioPCMBuffer) {
        guard source.format.commonFormat == .pcmFormatFloat32,
              destination.format.commonFormat == .pcmFormatInt16,
              let src = source.floatChannelData,
              let dst = destination.int16ChannelData else { return }

        let frames = Int(source.frameLength)
        destination.frameLength = source.frameLength

        let sourceChannel = src[0]
        let destinationChannel = dst[0]

        for i in 0..<frames {
            let sample = sourceChannel[i]
            let scaled = sample * Float(Int16.max)
            destinationChannel[i] = Int16(max(Float(Int16.min), min(Float(Int16.max), scaled)))
        }
    }

    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func prepareForTranscription(originalURL: URL) throws -> PreparedAudioFile {
        let inputFile = try AVAudioFile(forReading: originalURL)
        let duration = Double(inputFile.length) / inputFile.processingFormat.sampleRate

        guard let intermediateFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create intermediate format"])
        }

        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: intermediateFormat) else {
            throw NSError(domain: "AudioProcessing", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to create converter"])
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("prepared-\(UUID().uuidString).wav")
        // Write as 32-bit float WAV to maximize compatibility on simulator and avoid
        // fragile int16 write paths that can trigger asserts inside AVAudioFile.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: targetChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let inputFormat = inputFile.processingFormat
        let frameCapacity: AVAudioFrameCount = 1024
        var endOfStream = false

        while !endOfStream {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: frameCapacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if endOfStream {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
                    outStatus.pointee = .endOfStream
                    endOfStream = true
                    return nil
                }

                do {
                    try inputFile.read(into: inputBuffer)
                } catch {
                    outStatus.pointee = .endOfStream
                    endOfStream = true
                    return nil
                }

                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    endOfStream = true
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let conversionError = conversionError {
                throw conversionError
            }

            switch status {
            case .haveData:
                outputBuffer.frameLength = min(outputBuffer.frameLength, frameCapacity)
                if outputBuffer.frameLength == 0 { break }
                normalize(outputBuffer)
                try outputFile.write(from: outputBuffer)
            case .inputRanDry:
                continue
            case .endOfStream:
                endOfStream = true
            case .error:
                throw NSError(domain: "AudioProcessing", code: -3, userInfo: [NSLocalizedDescriptionKey: "Conversion error"])
            @unknown default:
                endOfStream = true
            }
        }

        return PreparedAudioFile(url: outputURL, duration: duration)
    }
}

