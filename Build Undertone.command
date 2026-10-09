#!/bin/zsh
# Double-click in Finder to build build/Undertone.app and open it.

set -u

ROOT="${0:A:h}"
APP="$ROOT/build/Undertone.app"

pause_before_exit() {
    if [[ -t 0 ]]; then
        echo
        read -k 1 "?Press any key to close this window…"
        echo
    fi
}

fail() {
    echo
    echo "❌ Undertone could not be built."
    echo "$1"
    pause_before_exit
    exit 1
}

cd "$ROOT" || fail "The Undertone source folder could not be opened."

if ! /usr/bin/xcrun --find actool >/dev/null 2>&1; then
    fail "Install the full Xcode 26 application, open it once, and try again. The icon needs its actool."
fi

echo "Building Undertone (release)…"
echo

# Compile first, so a failed build leaves a running copy alone.
if ! swift build -c release --disable-sandbox; then
    fail "See the build output above for details."
fi

# Quit a running copy so the new build (and its icon) replaces it cleanly.
if pgrep -xq Undertone; then
    osascript -e 'quit app "Undertone"'
    while pgrep -xq Undertone; do sleep 0.2; done
fi

if ! zsh "$ROOT/scripts/build-app.sh"; then
    fail "Packaging the app failed. See the output above for details."
fi

[[ -d "$APP" ]] || fail "The build finished without creating build/Undertone.app."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo
echo "✅ Built Undertone $VERSION ($BUILD) → $APP"

/usr/bin/open "$APP"
pause_before_exit
