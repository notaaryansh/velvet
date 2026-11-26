#!/bin/zsh
# Build Velvet.app — a proper bundle so WebKit cookies/login persist.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="dist/Velvet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Velvet "$APP/Contents/MacOS/Velvet"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Velvet</string>
    <key>CFBundleIdentifier</key><string>com.velvet.music</string>
    <key>CFBundleName</key><string>Velvet</string>
    <key>CFBundleDisplayName</key><string>Velvet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP" 2>/dev/null || true

echo ""
echo "✓ Built $APP"
echo "  Run it with:  open $APP"
