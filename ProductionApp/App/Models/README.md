# Whisper Models Directory

This directory contains the CoreML Whisper models for offline transcription.

## Model Structure

Each model directory should contain the following components:

```
openai_whisper-{size}.en/
├── AudioEncoder.mlmodelc/
│   ├── coremldata.bin
│   ├── metadata.json
│   ├── model.mil
│   ├── model.mlmodel
│   └── weights/
│       └── weight.bin
├── MelSpectrogram.mlmodelc/
│   ├── coremldata.bin
│   ├── metadata.json
│   ├── model.mil
│   └── weights/
│       └── weight.bin
├── TextDecoder.mlmodelc/
│   ├── coremldata.bin
│   ├── metadata.json
│   ├── model.mil
│   ├── model.mlmodel
│   └── weights/
│       └── weight.bin
├── config.json
└── generation_config.json
```

## Available Models

### Tiny Model (73MB)
- **File**: `openai_whisper-tiny.en`
- **Size**: ~73MB
- **Use Case**: Fast transcription, limited accuracy
- **Best for**: Quick testing, real-time applications

### Base Model (146MB)
- **File**: `openai_whisper-base.en`
- **Size**: ~146MB
- **Use Case**: Balanced speed and accuracy
- **Best for**: General purpose transcription

### Small Model (217MB)
- **File**: `openai_whisper-small.en`
- **Size**: ~217MB
- **Use Case**: Higher accuracy, slower processing
- **Best for**: High-quality transcription

## Setup Instructions

### Automatic Setup
Run the setup script from the ProductionApp directory:

```bash
./setup_models.sh
```

### Manual Setup
1. Download models from [Hugging Face WhisperKit](https://huggingface.co/argmaxinc/whisperkit-openai-whisper-tiny.en)
2. Extract the downloaded ZIP files to this directory
3. Ensure the directory structure matches the format above

## Model Sources

Models are sourced from:
- **Hugging Face**: [argmaxinc/whisperkit-openai-whisper-*](https://huggingface.co/argmaxinc)
- **Original**: OpenAI Whisper models converted to CoreML format
- **License**: MIT License (same as OpenAI Whisper)

## Troubleshooting

### Model Loading Issues
- Ensure all `.bin` files are present and not corrupted
- Check that the model directory structure is correct
- Verify the app has proper file system permissions

### Performance Issues
- Use the Tiny model for fastest performance
- Use the Small model for best accuracy
- Consider device storage and memory limitations

### File Size Issues
- Models are large and excluded from Git
- Use the setup script to download models after cloning
- Models are downloaded on-demand during app setup

## Notes

- Models are automatically compiled during the Xcode build process
- The app will fall back to Apple Native transcription if models are unavailable
- All models support English language only
- Models are processed entirely on-device for privacy
