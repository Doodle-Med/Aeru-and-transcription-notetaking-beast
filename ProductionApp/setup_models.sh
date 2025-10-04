#!/bin/bash

# WhisperControlMobile - Model Setup Script
# This script downloads and sets up the required Whisper models for the app

set -e

echo "🎤 WhisperControlMobile - Model Setup"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "WhisperControlMobile.xcodeproj/project.pbxproj" ]; then
    print_error "Please run this script from the ProductionApp directory"
    exit 1
fi

# Create models directory
MODELS_DIR="App/Models"
print_status "Creating models directory: $MODELS_DIR"
mkdir -p "$MODELS_DIR"

# Model configurations
declare -A MODELS=(
    ["openai_whisper-tiny.en"]="https://huggingface.co/argmaxinc/whisperkit-openai-whisper-tiny.en/resolve/main/openai_whisper-tiny.en.zip"
    ["openai_whisper-base.en"]="https://huggingface.co/argmaxinc/whisperkit-openai-whisper-base.en/resolve/main/openai_whisper-base.en.zip"
    ["openai_whisper-small.en"]="https://huggingface.co/argmaxinc/whisperkit-openai-whisper-small.en/resolve/main/openai_whisper-small.en.zip"
)

# Function to download and extract model
download_model() {
    local model_name=$1
    local download_url=$2
    local model_dir="$MODELS_DIR/$model_name"
    
    print_status "Setting up model: $model_name"
    
    if [ -d "$model_dir" ]; then
        print_warning "Model directory already exists: $model_dir"
        read -p "Do you want to re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping $model_name"
            return 0
        fi
        rm -rf "$model_dir"
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/${model_name}.zip"
    
    print_status "Downloading $model_name from Hugging Face..."
    if curl -L -o "$zip_file" "$download_url"; then
        print_success "Downloaded $model_name"
    else
        print_error "Failed to download $model_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Extracting $model_name..."
    if unzip -q "$zip_file" -d "$temp_dir"; then
        print_success "Extracted $model_name"
    else
        print_error "Failed to extract $model_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Move extracted model to final location
    local extracted_dir="$temp_dir/$model_name"
    if [ -d "$extracted_dir" ]; then
        mv "$extracted_dir" "$model_dir"
        print_success "Installed $model_name to $model_dir"
    else
        print_error "Could not find extracted model directory"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    return 0
}

# Download all models
print_status "Starting model downloads..."
echo

for model_name in "${!MODELS[@]}"; do
    download_model "$model_name" "${MODELS[$model_name]}"
    echo
done

print_success "All models downloaded successfully!"
echo
print_status "Model installation complete. You can now build the app in Xcode."
echo
print_status "Models installed:"
for model_name in "${!MODELS[@]}"; do
    if [ -d "$MODELS_DIR/$model_name" ]; then
        echo "  ✅ $model_name"
    else
        echo "  ❌ $model_name (failed)"
    fi
done

echo
print_status "Next steps:"
echo "1. Open WhisperControlMobile.xcodeproj in Xcode"
echo "2. Build and run the project"
echo "3. The app will automatically use the downloaded models"
echo
print_warning "Note: These models are large (73MB - 1.5GB total). Make sure you have sufficient disk space."
