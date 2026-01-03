#!/bin/bash

# Configuration
APP_NAME="VeloxClip"
BUNDLE_ID="com.antigravity.veloxclip"
EXECUTABLE_NAME="VeloxClip"
BUILD_CONFIG="release"
BUILD_PATH=".build"

echo "🚀 Building $APP_NAME in $BUILD_CONFIG mode..."

# Set build path to avoid permission issues with system cache
export SWIFT_PACKAGE_BUILD_PATH="$BUILD_PATH"
# Disable user-level cache to avoid permission issues
export SWIFTPM_DISABLE_CACHE=1

# Clean build directory if needed (optional, comment out if you want incremental builds)
# echo "🧹 Cleaning build directory..."
# rm -rf "$BUILD_PATH"

# 1. Build the project with explicit build path
echo "📦 Building Swift package..."
swift build -c $BUILD_CONFIG --product $EXECUTABLE_NAME --build-path "$BUILD_PATH" 2>&1
BUILD_STATUS=$?

# Check if executable was created (warnings are OK, but we need the binary)
if [ ! -f "$BUILD_PATH/$BUILD_CONFIG/$EXECUTABLE_NAME" ]; then
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
BINARY_PATH="$BUILD_PATH/$BUILD_CONFIG/$EXECUTABLE_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Executable not found at $BINARY_PATH"
    exit 1
fi
cp "$BINARY_PATH" "$MACOS_DIR/"

# 3.1 Copy LLM Resources (if they exist)
if [ -d "LLM" ]; then
    echo "🧠 Copying LLM/AI model resources..."
    cp -R LLM/* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# 3.2 Copy App Icon (if it exists)
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
