#!/bin/bash

# Screenshot Resizer for App Store Connect
# Resizes screenshots to the exact dimensions required by App Store Connect

set -e

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

# Check if ImageMagick is installed
check_imagemagick() {
    if ! command -v convert &> /dev/null; then
        error "ImageMagick not found. Please install it with: brew install imagemagick"
    fi
    success "ImageMagick found"
}

# Create output directory
create_output_dir() {
    OUTPUT_DIR="./screenshots-resized"
    if [ -d "$OUTPUT_DIR" ]; then
        rm -rf "$OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"
    log "Created output directory: $OUTPUT_DIR"
}

# Resize screenshot function
resize_screenshot() {
    local input_file="$1"
    local output_dir="$2"
    local base_name=$(basename "$input_file" | sed 's/\.[^.]*$//')
    local extension="${input_file##*.}"
    
    log "Processing: $input_file"
    
    # Resize to all required dimensions
    magick "$input_file" -resize 1242x2688! "$output_dir/${base_name}_1242x2688.${extension}"
    magick "$input_file" -resize 2688x1242! "$output_dir/${base_name}_2688x1242.${extension}"
    magick "$input_file" -resize 1284x2778! "$output_dir/${base_name}_1284x2778.${extension}"
    magick "$input_file" -resize 2778x1284! "$output_dir/${base_name}_2778x1284.${extension}"
    
    success "Resized $input_file to all required dimensions"
}

# Main function
main() {
    log "Starting screenshot resizing for App Store Connect..."
    
    # Check prerequisites
    check_imagemagick
    create_output_dir
    
    # Check if screenshots directory exists
    if [ ! -d "./screenshots" ] && [ ! -d "./Screenshots" ]; then
        error "No screenshots directory found. Please create a 'screenshots' directory and add your screenshot files."
    fi
    
    # Find screenshots directory
    SCREENSHOTS_DIR=""
    if [ -d "./screenshots" ]; then
        SCREENSHOTS_DIR="./screenshots"
    elif [ -d "./Screenshots" ]; then
        SCREENSHOTS_DIR="./Screenshots"
    fi
    
    # Find all image files (only in the screenshots directory, not subdirectories)
    image_files=($(find "$SCREENSHOTS_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \)))
    
    if [ ${#image_files[@]} -eq 0 ]; then
        error "No image files found in $SCREENSHOTS_DIR"
    fi
    
    log "Found ${#image_files[@]} image files"
    
    # Process each screenshot
    for file in "${image_files[@]}"; do
        resize_screenshot "$file" "$OUTPUT_DIR"
    done
    
    success "All screenshots resized successfully!"
    
    log "Resized screenshots saved to: $OUTPUT_DIR"
    log "Files created:"
    ls -la "$OUTPUT_DIR"
    
    echo ""
    log "App Store Connect Requirements:"
    log "• iPhone 6.5\": 1242 × 2688px or 2688 × 1242px"
    log "• iPhone 6.7\": 1284 × 2778px or 2778 × 1284px"
    log "• Use the appropriate size for your target device"
    
    echo ""
    success "Ready to upload to App Store Connect! 🚀"
}

# Run main function
main "$@"
