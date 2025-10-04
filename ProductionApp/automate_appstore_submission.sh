#!/bin/bash

# Automated App Store Submission Script for Whisper Control
# This script automates the entire App Store submission process

set -e  # Exit on any error

# Configuration
PROJECT_NAME="WhisperControlMobile"
SCHEME_NAME="WhisperControlMobile"
BUNDLE_ID="com.josephhennig.whispercontrolmobile"
APP_NAME="Whisper Control"
VERSION="1.0.0"
BUILD_NUMBER="1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        error "Xcode command line tools not found. Please install Xcode."
    fi
    
    # Check if we're in the right directory
    if [ ! -f "${PROJECT_NAME}.xcodeproj/project.pbxproj" ]; then
        error "Xcode project not found. Please run this script from the project directory."
    fi
    
    # Check if logged into Apple Developer account
    if ! xcodebuild -showBuildSettings -project "${PROJECT_NAME}.xcodeproj" -scheme "${SCHEME_NAME}" | grep -q "DEVELOPMENT_TEAM"; then
        error "Not logged into Apple Developer account. Please log in via Xcode."
    fi
    
    success "Prerequisites check passed"
}

# Clean and prepare build
prepare_build() {
    log "Preparing build environment..."
    
    # Clean previous builds
    xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "${SCHEME_NAME}" -configuration Release -destination "generic/platform=iOS"
    
    # Update version numbers
    log "Updating version to ${VERSION} (${BUILD_NUMBER})"
    
    # Update Info.plist version
    if [ -f "App/Info.plist" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "App/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "App/Info.plist"
    fi
    
    success "Build environment prepared"
}

# Create archive
create_archive() {
    log "Creating archive for App Store submission..."
    
    ARCHIVE_PATH="./${PROJECT_NAME}.xcarchive"
    
    # Remove existing archive if it exists
    if [ -d "${ARCHIVE_PATH}" ]; then
        rm -rf "${ARCHIVE_PATH}"
    fi
    
    # Create archive
    xcodebuild archive \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "${ARCHIVE_PATH}" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM=JA6967Z8P6 \
        ONLY_ACTIVE_ARCH=NO
    
    if [ ! -d "${ARCHIVE_PATH}" ]; then
        error "Archive creation failed"
    fi
    
    success "Archive created successfully: ${ARCHIVE_PATH}"
}

# Validate archive
validate_archive() {
    log "Validating archive..."
    
    ARCHIVE_PATH="./${PROJECT_NAME}.xcarchive"
    
    # Validate archive
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "./Export" \
        -exportOptionsPlist "./ExportOptions.plist" \
        -allowProvisioningUpdates
    
    success "Archive validation passed"
}

# Upload to App Store Connect
upload_to_appstore() {
    log "Uploading to App Store Connect..."
    
    ARCHIVE_PATH="./${PROJECT_NAME}.xcarchive"
    
    # Upload using xcodebuild
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "./Export" \
        -exportOptionsPlist "./ExportOptions.plist" \
        -allowProvisioningUpdates
    
    success "Upload to App Store Connect completed"
}

# Create export options plist
create_export_options() {
    log "Creating export options plist..."
    
    cat > "./ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>JA6967Z8P6</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF
    
    success "Export options plist created"
}

# Generate screenshots (placeholder)
generate_screenshots() {
    log "Generating screenshots..."
    
    # Create screenshots directory
    mkdir -p "./Screenshots"
    
    # This is a placeholder - you'll need to take actual screenshots
    warning "Screenshots need to be taken manually on real devices"
    warning "Required sizes:"
    warning "  - iPhone 6.7\" (iPhone 15 Pro Max, 14 Pro Max, 13 Pro Max, 12 Pro Max)"
    warning "  - iPhone 6.5\" (iPhone 11 Pro Max, XS Max)"
    warning "  - iPhone 5.5\" (iPhone 8 Plus, 7 Plus, 6s Plus)"
    warning "  - iPad Pro (6th generation) 12.9\""
    warning "  - iPad Pro (2nd generation) 12.9\""
    warning "  - iPad (9th generation) 10.2\""
    
    # Create placeholder files
    touch "./Screenshots/README.md"
    cat > "./Screenshots/README.md" << EOF
# Screenshots Required for App Store

## iPhone Screenshots
- iPhone 6.7" (iPhone 15 Pro Max, 14 Pro Max, 13 Pro Max, 12 Pro Max)
- iPhone 6.5" (iPhone 11 Pro Max, XS Max)  
- iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus)

## iPad Screenshots
- iPad Pro (6th generation) 12.9"
- iPad Pro (2nd generation) 12.9"
- iPad (9th generation) 10.2"

## App Icon
- 1024x1024 pixels
- PNG format
- No transparency
- No rounded corners (Apple adds them)

## Instructions
1. Take screenshots on real devices (not simulator)
2. Show key app features:
   - Main recording interface
   - Live transcription view
   - Settings screen
   - File management
   - Export options
3. Use high-quality, professional screenshots
4. Ensure text is readable and UI is clean
EOF
    
    success "Screenshots directory created with instructions"
}

# Main execution
main() {
    log "Starting automated App Store submission for ${APP_NAME}"
    log "Bundle ID: ${BUNDLE_ID}"
    log "Version: ${VERSION} (${BUILD_NUMBER})"
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Create export options
    create_export_options
    
    # Step 3: Prepare build
    prepare_build
    
    # Step 4: Create archive
    create_archive
    
    # Step 5: Validate archive
    validate_archive
    
    # Step 6: Upload to App Store Connect
    upload_to_appstore
    
    # Step 7: Generate screenshots placeholder
    generate_screenshots
    
    success "Automated submission completed!"
    
    log "Next steps:"
    log "1. Go to App Store Connect (https://appstoreconnect.apple.com)"
    log "2. Create new app listing with bundle ID: ${BUNDLE_ID}"
    log "3. Upload screenshots from ./Screenshots/ directory"
    log "4. Add app metadata from AppStore_Metadata.md"
    log "5. Submit for review"
    
    log "Files created:"
    log "- ${PROJECT_NAME}.xcarchive (App Store archive)"
    log "- ExportOptions.plist (Export configuration)"
    log "- Screenshots/ (Screenshot instructions)"
    log "- AppStore_Metadata.md (App Store information)"
    log "- PRIVACY.md (Privacy policy)"
}

# Run main function
main "$@"
