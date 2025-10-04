#!/bin/bash

# Simplified App Store Build Script
# This script creates a production build ready for App Store submission

set -e

# Configuration
PROJECT_NAME="WhisperControlMobile"
SCHEME_NAME="WhisperControlMobile"
BUNDLE_ID="com.josephhennig.whispercontrolmobile"

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

log "Creating App Store ready build for Whisper Control"

# Step 1: Clean build
log "Cleaning previous builds..."
xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "${SCHEME_NAME}" -configuration Release

# Step 2: Create production build
log "Creating production build..."
xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=JA6967Z8P6 \
    CODE_SIGN_IDENTITY="iPhone Distribution"

success "Production build completed!"

log "Next steps for App Store submission:"
log "1. Open Xcode"
log "2. Select 'Any iOS Device (arm64)' as destination"
log "3. Product → Archive"
log "4. In Organizer, click 'Distribute App'"
log "5. Choose 'App Store Connect'"
log "6. Follow the upload wizard"

warning "Note: You may need to register a device in Apple Developer Portal first"
warning "Go to: https://developer.apple.com/account/resources/devices/list"
warning "Add at least one iOS device to enable provisioning profiles"
