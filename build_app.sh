#!/bin/bash

# Configuration
APP_NAME="VeloxClip"
BUNDLE_ID="com.antigravity.veloxclip"
EXECUTABLE_NAME="VeloxClip"
BUILD_CONFIG="release"
BUILD_PATH=".build"

echo "🚀 Building $APP_NAME in $BUILD_CONFIG mode..."

# Get absolute paths to avoid permission issues
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ABS_BUILD_PATH="$PROJECT_ROOT/$BUILD_PATH"

# Set build path to avoid permission issues with system cache
export SWIFT_PACKAGE_BUILD_PATH="$ABS_BUILD_PATH"
# Disable user-level cache to avoid permission issues
export SWIFTPM_DISABLE_CACHE=1
# Redirect Clang module cache to build directory to avoid permission issues
export CLANG_MODULE_CACHE_PATH="$ABS_BUILD_PATH/clang-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
# Note: TMPDIR is not set to avoid sandbox-exec issues with Swift compiler
# The compiler will use system temp directory, but module cache is redirected to avoid permission issues

# Clean build directory if needed (optional, comment out if you want incremental builds)
# echo "🧹 Cleaning build directory..."
# rm -rf "$ABS_BUILD_PATH"

# 1. Build the project with explicit build path
echo "📦 Building Swift package..."
swift build -c $BUILD_CONFIG --product $EXECUTABLE_NAME --build-path "$ABS_BUILD_PATH" 2>&1
BUILD_STATUS=$?

# Check if executable was created (warnings are OK, but we need the binary)
if [ ! -f "$ABS_BUILD_PATH/$BUILD_CONFIG/$EXECUTABLE_NAME" ]; then
    if [ $BUILD_STATUS -ne 0 ]; then
        echo "❌ Build failed with exit code $BUILD_STATUS!"
        exit 1
    else
        echo "❌ Build completed but executable not found!"
        exit 1
    fi
fi

if [ $BUILD_STATUS -ne 0 ]; then
    echo "⚠️  Build completed with warnings (exit code $BUILD_STATUS), but executable exists. Continuing..."
fi

# 2. Setup Bundle Structure
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📂 Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy Executable
BINARY_PATH="$ABS_BUILD_PATH/$BUILD_CONFIG/$EXECUTABLE_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Executable not found at $BINARY_PATH"
    exit 1
fi
cp "$BINARY_PATH" "$MACOS_DIR/"

# 3.1 Copy App Icon (if it exists)
if [ -f "VeloxClip/Resources/AppIcon.icns" ]; then
    echo "🎨 Copying app icon..."
    cp "VeloxClip/Resources/AppIcon.icns" "$RESOURCES_DIR/"
    ICON_NAME="AppIcon"
else
    ICON_NAME=""
fi

# 4. Create Info.plist
echo "📝 Generating Info.plist..."
{
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <string>1</string>
    <key>LSHideExtension</key>
    <true/>
EOF
    if [ -n "$ICON_NAME" ]; then
        cat <<EOF
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
EOF
    fi
    cat <<EOF
</dict>
</plist>
EOF
} > "$CONTENTS_DIR/Info.plist"

echo "✅ $APP_BUNDLE created successfully!"
echo "👉 You can find it at: $(pwd)/$APP_BUNDLE"

# 5. Create DMG package
echo "📦 Creating DMG package..."
DMG_NAME="${APP_NAME}.dmg"
DMG_TEMP_DIR="dmg_temp"
DMG_VOLUME_NAME="${APP_NAME}"

# Clean up any existing temp directory
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"

# Create Applications link (shortcut)
# Use macOS alias instead of symlink for better icon display
# First create a symlink, then convert it to an alias using osascript
ln -sf /Applications "$DMG_TEMP_DIR/Applications"

# Note: We'll set the icon after DMG is mounted using osascript
# The symlink should work, but we'll ensure the icon is set correctly
APPLICATIONS_ICON_PATH="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
if [ -f "$APPLICATIONS_ICON_PATH" ]; then
    # Copy icon for later use
    cp "$APPLICATIONS_ICON_PATH" "$DMG_TEMP_DIR/.ApplicationsIcon.icns" 2>/dev/null || true
fi

# Create installation instructions as a hidden file that will be shown in DMG
cat > "$DMG_TEMP_DIR/.DS_Store" <<'EOF'
# This will be created by Finder
EOF

# Create installation instructions file
cat > "$DMG_TEMP_DIR/📖 Installation Instructions.txt" <<'INSTRUCTIONS'
╔══════════════════════════════════════════════════════════════╗
║              VeloxClip Installation Instructions            ║
╚══════════════════════════════════════════════════════════════╝

Installation:

  Drag VeloxClip.app on the left to Applications folder on the right

──────────────────────────────────────────────────────────────

After installation, find VeloxClip in your Applications folder.

INSTRUCTIONS

# Create DMG
DMG_TEMP="${DMG_NAME}.temp.dmg"
rm -f "$DMG_TEMP" "$DMG_NAME"

# Calculate app size for display
APP_SIZE=$(du -sk "$DMG_TEMP_DIR" | cut -f1)
echo "📊 App size: $((APP_SIZE / 1024))MB"

# Create temporary DMG (hdiutil will auto-calculate size from srcfolder)
hdiutil create -srcfolder "$DMG_TEMP_DIR" -volname "$DMG_VOLUME_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$DMG_TEMP"

# Mount the DMG
MOUNT_DIR="/Volumes/$DMG_VOLUME_NAME"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | \
    egrep '^/dev/' | sed 1q | awk '{print $1}')

# Wait for mount
sleep 2

# Set DMG window properties and fix Applications icon
if [ -d "$MOUNT_DIR" ]; then
    # Set Applications folder icon using osascript
    # This is the most reliable method for setting folder icons in DMG
    APPLICATIONS_ICON_PATH="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
    
    if [ -f "$APPLICATIONS_ICON_PATH" ] && [ -L "$MOUNT_DIR/Applications" ]; then
        # Ensure icon file exists in mounted volume
        if [ ! -f "$MOUNT_DIR/.ApplicationsIcon.icns" ]; then
            cp "$APPLICATIONS_ICON_PATH" "$MOUNT_DIR/.ApplicationsIcon.icns" 2>/dev/null || true
        fi
        
        # Use osascript to set the icon for the Applications symlink
        # Try multiple times to ensure it works
        for i in 1 2 3; do
            osascript <<APPLICON 2>/dev/null || true
tell application "Finder"
    try
        set iconPath to POSIX file "$MOUNT_DIR/.ApplicationsIcon.icns"
        set applicationsItem to item "Applications" of disk "$DMG_VOLUME_NAME"
        set icon of applicationsItem to iconPath
        delay 0.5
    end try
end tell
APPLICON
            sleep 0.5
        done
    fi
    
    # Set window properties and icon positions
    osascript <<EOF 2>/dev/null || true
tell application "Finder"
    tell disk "$DMG_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 1000, 550}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        -- Position icons: App on left, Applications on right, Instructions below
        set position of item "$APP_BUNDLE" of container window to {180, 200}
        set position of item "Applications" of container window to {380, 200}
        try
            set position of item "📖 Installation Instructions.txt" of container window to {280, 320}
        end try
        -- Set background color (light gray)
        set background picture of viewOptions to none
        set background color of viewOptions to {65535, 65535, 65535}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF
    
    # Wait a bit for Finder to update
    sleep 1
fi

# Unmount (with error handling - device may have auto-unmounted)
if [ -n "$DEVICE" ]; then
    hdiutil detach "$DEVICE" 2>/dev/null || true
fi

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

# Clean up
rm -rf "$DMG_TEMP_DIR"
rm -f "$DMG_TEMP"

echo "✅ DMG package created successfully!"
echo "👉 DMG file: $(pwd)/$DMG_NAME"
echo "📦 Users can drag $APP_NAME.app to Applications folder to install"
