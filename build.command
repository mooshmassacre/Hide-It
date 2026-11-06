#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swift >/dev/null 2>&1; then
  echo 'Instale as ferramentas da Apple com: xcode-select --install'
  exit 1
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Hide-It.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HideIt" "$APP/Contents/MacOS/HideIt"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/HideIt.icns "$APP/Contents/Resources/HideIt.icns"
rm -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
chmod +x "$APP/Contents/MacOS/HideIt"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Criado: $APP"
echo 'Copie Hide-It.app para Aplicativos e abra-o.'
