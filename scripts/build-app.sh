#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
APP="$PWD/build/Undertone.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Undertone "$APP/Contents/MacOS/Undertone"
ICONSET="$PWD/build/Undertone.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/Undertone-icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" assets/Undertone-icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/python3 scripts/package-icon.py "$ICONSET" "$APP/Contents/Resources/Undertone.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Undertone</string>
<key>CFBundleDisplayName</key><string>Undertone</string>
<key>CFBundleIdentifier</key><string>studio.undertone.mac</string>
<key>CFBundleExecutable</key><string>Undertone</string>
<key>CFBundleIconFile</key><string>Undertone.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
