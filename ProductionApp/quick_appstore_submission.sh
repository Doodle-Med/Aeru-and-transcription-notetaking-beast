#!/bin/bash

# Quick App Store Submission Script
# This script opens Xcode and guides you through the submission process

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

log "Setting up quick App Store submission..."

# Step 1: Open Xcode project
log "Opening Xcode project..."
open WhisperControlMobile.xcodeproj

# Step 2: Wait a moment for Xcode to load
log "Waiting for Xcode to load..."
sleep 5

# Step 3: Open Simulator
log "Opening iOS Simulator..."
open -a Simulator

# Step 4: Display instructions
echo ""
echo "=========================================="
echo "🚀 QUICK APP STORE SUBMISSION GUIDE"
echo "=========================================="
echo ""
echo "Xcode and Simulator are now open. Follow these steps:"
echo ""
echo "1. 📱 REGISTER DEVICE (if needed):"
echo "   - In Xcode: Window → Devices and Simulators"
echo "   - Select your connected iPhone/iPad"
echo "   - Click 'Use for Development'"
echo "   - OR use the iPhone 17 Pro simulator that's already open"
echo ""
echo "2. 🏗️  CREATE ARCHIVE:"
echo "   - In Xcode: Select 'Any iOS Device (arm64)' from scheme selector"
echo "   - Product → Archive"
echo "   - Wait for build to complete"
echo ""
echo "3. 📤 UPLOAD TO APP STORE:"
echo "   - In Organizer window: Click 'Distribute App'"
echo "   - Choose 'App Store Connect'"
echo "   - Follow the upload wizard"
echo ""
echo "4. 🎯 COMPLETE APP STORE LISTING:"
echo "   - Go to: https://appstoreconnect.apple.com"
echo "   - Create new app with bundle ID: com.josephhennig.whispercontrolmobile"
echo "   - Use metadata from: AppStore_Metadata.md"
echo "   - Upload screenshots from: Screenshots/ directory"
echo ""
echo "📁 Files ready for you:"
echo "   ✅ AppStore_Metadata.md - Complete app description"
echo "   ✅ PRIVACY.md - Privacy policy"
echo "   ✅ Screenshots/ - Screenshot requirements"
echo "   ✅ App version: 1.0.0"
echo ""
echo "⏱️  Expected timeline:"
echo "   - Archive: 5-10 minutes"
echo "   - Upload: 5-15 minutes"
echo "   - Review: 24-48 hours"
echo ""
echo "🎉 Your app is ready for the App Store!"
echo "=========================================="

success "Xcode and Simulator opened successfully!"
warning "Follow the steps above to complete your App Store submission."

# Optional: Try to build first to test
log "Testing build capability..."
if xcodebuild -project WhisperControlMobile.xcodeproj -scheme WhisperControlMobile -destination "generic/platform=iOS" -configuration Release -allowProvisioningUpdates build 2>/dev/null; then
    success "Build test successful! You're ready to archive."
else
    warning "Build test failed. You may need to register a device first."
    warning "Try connecting a physical device or use the simulator registration steps above."
fi
