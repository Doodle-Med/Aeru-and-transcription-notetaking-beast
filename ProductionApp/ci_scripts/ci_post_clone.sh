#!/usr/bin/env bash
set -euo pipefail

echo "== Xcode Cloud CI Debug Information =="
echo "Current directory: $(pwd)"
echo "Git commit: $(git rev-parse HEAD)"
echo "Git branch: $(git branch --show-current)"

echo ""
echo "== Schemes in project =="
xcodebuild -list -project ProductionApp/WhisperControlMobile.xcodeproj || true

echo ""
echo "== Shared scheme files =="
find ProductionApp -name "*.xcscheme" -path "*/xcshareddata/*" || true

echo ""
echo "== Package.resolved status =="
if [ -f "ProductionApp/WhisperControlMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]; then
    echo "✅ Package.resolved found"
    echo "Package.resolved size: $(wc -c < ProductionApp/WhisperControlMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) bytes"
else
    echo "❌ Package.resolved missing"
fi

echo ""
echo "== Project structure =="
ls -la ProductionApp/ || true
