#!/bin/bash
# build_ipa.sh - GhostStream IPA 빌드 스크립트
# SideStore / AltStore 배포용
set -e

SCHEME="GhostStream"
CONFIG="Release"
ARCHIVE_PATH="build/GhostStream.xcarchive"
EXPORT_PATH="build/IPA"

echo "🔨 Building GhostStream..."

# Step 1: Archive
xcodebuild -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    CODE_SIGN_IDENTITY="Apple Development" \
    archive

echo "📦 Exporting IPA..."

# Step 2: Export IPA
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist ExportOptions.plist

echo "✅ IPA built successfully!"
echo "   Location: $EXPORT_PATH/GhostStream.ipa"
echo ""
echo "📱 To install via SideStore:"
echo "   1. Upload GhostStream.ipa to your server"
echo "   2. Update downloadURL in ghoststream-source.json"
echo "   3. Add source URL in SideStore: Settings → Sources → +"
echo ""
echo "   Or drag GhostStream.ipa directly to SideStore/AltStore"
