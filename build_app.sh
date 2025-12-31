#!/bin/bash

# Configuration
APP_NAME="VeloxClip"
BUNDLE_ID="com.antigravity.veloxclip"
EXECUTABLE_NAME="VeloxClip"
BUILD_CONFIG="release"

echo "🚀 Building $APP_NAME in $BUILD_CONFIG mode..."

# 1. Build the project
swift build -c $BUILD_CONFIG --product $EXECUTABLE_NAME

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
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
BINARY_PATH=$(swift build -c $BUILD_CONFIG --show-bin-path)/$EXECUTABLE_NAME
cp "$BINARY_PATH" "$MACOS_DIR/"

# 3.1 Copy LLM Resources (if they exist)
if [ -d "LLM" ]; then
    echo "🧠 Copying LLM/AI model resources..."
    cp -R LLM/* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# 4. Create Info.plist
echo "📝 Generating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" <<EOF
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
</dict>
</plist>
EOF

echo "✅ $APP_BUNDLE created successfully!"
echo "👉 You can find it at: $(pwd)/$APP_BUNDLE"
