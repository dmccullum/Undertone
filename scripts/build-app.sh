#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
APP="$PWD/build/Undertone.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Undertone "$APP/Contents/MacOS/Undertone"

# Compile the Icon Composer icon (Icon/Undertone.icon) into Assets.car + Undertone.icns.
# Assets.car carries the modern (Liquid Glass) icon; the .icns is the fallback on older systems.
xcrun actool "Icon/Undertone.icon" \
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
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
