#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== TokenEater build ===${NC}"

# 1. Check Xcode
if ! xcode-select -p | grep -q "Xcode.app"; then
    echo -e "${RED}Xcode.app required. Install it from the Mac App Store.${NC}"
    echo "Then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# 2. Check/install XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${BLUE}Installing XcodeGen via Homebrew...${NC}"
    brew install xcodegen
fi

# 3. Generate Xcode project
echo -e "${BLUE}Generating the Xcode project...${NC}"
xcodegen generate

# 4. Restore the widget's NSExtension key (XcodeGen strips it on every
# generate; without it macOS never registers the widget and the gallery
# stays empty). Load-bearing, same step as CI and SETUP.md.
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' \
    TokenEaterWidget/Info.plist 2>/dev/null || true

# 5. Build
echo -e "${BLUE}Building...${NC}"
xcodebuild \
    -project TokenEater.xcodeproj \
    -scheme TokenEaterApp \
    -configuration Release \
    -derivedDataPath build \
    build 2>&1 | tail -20

# 6. Find the built app
APP_PATH=$(find build -name "TokenEater.app" -type d | head -1)

if [ -n "$APP_PATH" ]; then
    echo ""
    echo -e "${GREEN}Build OK!${NC}"
    echo -e "App: ${BLUE}$APP_PATH${NC}"
    echo ""
    echo "To install:"
    echo "  cp -R \"$APP_PATH\" /Applications/"
    echo "  open \"/Applications/TokenEater.app\""
else
    echo -e "${RED}Build failed. Check the errors above.${NC}"
    exit 1
fi
