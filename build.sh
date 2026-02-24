#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== TokenEater — Build ===${NC}"

# 1. Check Xcode
if ! xcode-select -p | grep -q "Xcode.app"; then
    echo -e "${RED}Xcode.app requis. Installe-le depuis le Mac App Store.${NC}"
    echo "Puis lance: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# 2. Check/install XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${BLUE}Installation de XcodeGen via Homebrew...${NC}"
    brew install xcodegen
fi

# 3. Generate Xcode project
echo -e "${BLUE}Generation du projet Xcode...${NC}"
xcodegen generate

# 4. Build
echo -e "${BLUE}Build en cours...${NC}"
xcodebuild \
    -project TokenEater.xcodeproj \
    -scheme TokenEaterApp \
    -configuration Release \
    -derivedDataPath build \
    build 2>&1 | tail -20

# 5. Find the built app
APP_PATH=$(find build -name "TokenEater.app" -type d | head -1)

if [ -n "$APP_PATH" ]; then
    echo ""
    echo -e "${GREEN}Build OK !${NC}"
    echo -e "App: ${BLUE}$APP_PATH${NC}"
    echo ""
    echo "Pour installer:"
    echo "  cp -R \"$APP_PATH\" /Applications/"
    echo "  open \"/Applications/TokenEater.app\""
else
    echo -e "${RED}Build echoue. Verifie les erreurs ci-dessus.${NC}"
    exit 1
fi
