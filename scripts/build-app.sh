#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
APP="$PWD/build/Undertone.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Undertone "$APP/Contents/MacOS/Undertone"

# SwiftPM stamps the binary's SDK version with the deployment target (26.0), so AppKit treats the
# app as built against the 26 SDK and withholds behavior that newer SDKs opt into. Record the real
# SDK instead; the minimum OS stays 26.0.
vtool -set-build-version macos 26.0 "$(xcrun --sdk macosx --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Undertone" "$APP/Contents/MacOS/Undertone"

# Compile the Icon Composer icon (Icon/Undertone.icon) into Assets.car + Undertone.icns.
# The path must be absolute: actool's icon exporter fails on a relative one and writes nothing.
# Assets.car carries the Liquid Glass icon (CFBundleIconName); the .icns backs CFBundleIconFile.
xcrun actool "$PWD/Icon/Undertone.icon" \
    --compile "$APP/Contents/Resources" \
    --app-icon "Undertone" \
    --output-partial-info-plist "$PWD/build/icon-partial.plist" \
    --platform macosx --minimum-deployment-target 26.0 \
    --errors --warnings >/dev/null

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Undertone</string>
<key>CFBundleDisplayName</key><string>Undertone</string>
<key>CFBundleIdentifier</key><string>studio.undertone.mac</string>
<key>CFBundleExecutable</key><string>Undertone</string>
<key>CFBundleIconFile</key><string>Undertone</string>
<key>CFBundleIconName</key><string>Undertone</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
