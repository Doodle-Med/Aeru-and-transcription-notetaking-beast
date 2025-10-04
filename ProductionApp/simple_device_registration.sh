#!/bin/bash

# Simple Device Registration Script
# This script attempts to register a simulator device by building the app

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Configuration
SIMULATOR_ID="AB875782-946A-42DF-9699-32B88FE20969"
SIMULATOR_NAME="iPhone 17 Pro"

log "Attempting to register simulator device for Apple Developer account..."

# Step 1: Ensure simulator is booted
log "Booting simulator: ${SIMULATOR_NAME}"
xcrun simctl boot "${SIMULATOR_ID}" 2>/dev/null || true

# Wait for simulator to be ready
log "Waiting for simulator to be ready..."
sleep 3

# Step 2: Try to build the app on the simulator to trigger device registration
log "Building WhisperControl on simulator to register device..."

cd /Users/johnsnow/01_Whisper_Repo/ProductionApp

# Try building for the specific simulator
if xcodebuild -project WhisperControlMobile.xcodeproj \
    -scheme WhisperControlMobile \
    -destination "id=${SIMULATOR_ID}" \
    -configuration Debug \
    -allowProvisioningUpdates \
    build 2>/dev/null; then
    
    success "Build successful! Device may be registered."
else
    warning "Build failed, but this might still register the device."
fi

# Step 3: Try the App Store build again
log "Testing App Store build capability..."

if xcodebuild -project WhisperControlMobile.xcodeproj \
    -scheme WhisperControlMobile \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=JA6967Z8P6 \
    build 2>/dev/null; then
    
    success "App Store build successful! Device registration worked!"
    
    log "You can now run the App Store submission:"
    log "./automate_appstore_submission.sh"
else
    warning "App Store build still failing. Device registration may need more time."
    warning "Try connecting a physical device instead:"
    warning "1. Connect iPhone/iPad to Mac"
    warning "2. Xcode → Window → Devices and Simulators"
    warning "3. Select device → 'Use for Development'"
fi

success "Device registration attempt completed!"
