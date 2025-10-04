# Screenshot Resizing Guide for App Store Connect

## 📱 Required Dimensions

Your screenshots need to be resized to these exact dimensions:

- **1242 × 2688px** (iPhone 6.5" portrait)
- **2688 × 1242px** (iPhone 6.5" landscape)
- **1284 × 2778px** (iPhone 6.7" portrait)
- **2778 × 1284px** (iPhone 6.7" landscape)

## 🛠️ Option 1: Automated Script (Recommended)

### Install ImageMagick first:
```bash
brew install imagemagick
```

### Run the resize script:
```bash
cd /Users/johnsnow/01_Whisper_Repo/ProductionApp
./resize-screenshots.sh
```

This will:
1. Find all images in your `screenshots/` directory
2. Resize them to all 4 required dimensions
3. Save them to `screenshots-resized/` directory

## 🛠️ Option 2: Manual Resize with Preview (macOS)

### Using macOS Preview:
1. **Open your screenshot** in Preview
2. **Tools → Adjust Size**
3. **Set dimensions** to one of the required sizes:
   - Width: 1242, Height: 2688 (or 2688 × 1242)
   - Width: 1284, Height: 2778 (or 2778 × 1284)
4. **Resample Image:** Uncheck (to maintain quality)
5. **Save As** with a descriptive name

### Repeat for each dimension you need.

## 🛠️ Option 3: Online Tools

### Free Online Resizers:
- **ResizePixel**: https://www.resizepixel.com/
- **ILoveIMG**: https://www.iloveimg.com/resize-image
- **Canva**: https://www.canva.com/create/resize-image/

### Steps:
1. Upload your screenshot
2. Enter the exact dimensions
3. Download the resized image

## 🛠️ Option 4: Command Line (Manual)

If you have ImageMagick installed:

```bash
# Resize to iPhone 6.5" dimensions
convert your-screenshot.png -resize 1242x2688! screenshot_1242x2688.png
convert your-screenshot.png -resize 2688x1242! screenshot_2688x1242.png

# Resize to iPhone 6.7" dimensions  
convert your-screenshot.png -resize 1284x2778! screenshot_1284x2778.png
convert your-screenshot.png -resize 2778x1284! screenshot_2778x1284.png
```

## 📋 Screenshots You Need

Based on your app, capture these screens:

1. **Main Queue Screen** - Shows the transcription queue interface
2. **Live Transcription** - Shows the live transcription feature
3. **Settings Screen** - Shows app settings and options
4. **Database/Aeru Chat** - Shows the RAG chat interface
5. **File Import** - Shows the file import functionality

## 📱 Device-Specific Sizes

### iPhone 6.5" (iPhone 11 Pro Max, XS Max):
- **Portrait:** 1242 × 2688px
- **Landscape:** 2688 × 1242px

### iPhone 6.7" (iPhone 15 Pro Max, 14 Pro Max, 13 Pro Max):
- **Portrait:** 1284 × 2778px  
- **Landscape:** 2778 × 1284px

## 🎯 Quick Steps:

1. **Take screenshots** on your device or simulator
2. **Resize** using one of the methods above
3. **Upload** to App Store Connect
4. **Use the appropriate size** for each device category

## ⚠️ Important Notes:

- **Exact dimensions required** - don't use approximate sizes
- **High quality** - use PNG format when possible
- **No compression** - maintain original quality
- **Test on devices** - ensure screenshots look good on actual devices

## 🚀 Ready to Upload?

Once you have your resized screenshots:
1. Go to App Store Connect
2. Navigate to your app's "Previews and Screenshots" section
3. Upload the appropriately sized screenshots
4. Complete your app submission!

---

**Need help?** The automated script will handle everything for you once ImageMagick is installed!
