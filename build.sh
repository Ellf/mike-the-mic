#!/bin/zsh
# Builds build/Mike.app (overwrites the previous build in place).
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Mike.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14 Sources/*.swift -o "$APP/Contents/MacOS/Mike"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
