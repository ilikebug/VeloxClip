#!/bin/bash

# Icon generation script
# Usage: ./generate_icon.sh <input image path>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <image path>"
    echo "Example: $0 icon.png"
    echo ""
    echo "Supported formats: PNG, JPEG, TIFF"
    exit 1
fi

INPUT_IMAGE="$1"

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "❌ Error: File not found '$INPUT_IMAGE'"
    exit 1
fi

# Check if sips is installed (built-in on macOS)
if ! command -v sips &> /dev/null; then
    echo "❌ Error: sips tool is required (built-in on macOS)"
    exit 1
fi

# Check if iconutil is installed (built-in on macOS)
if ! command -v iconutil &> /dev/null; then
    echo "❌ Error: iconutil tool is required (built-in on macOS)"
    exit 1
fi

ICONSET_NAME="VeloxClip.iconset"
OUTPUT_ICNS="VeloxClip/Resources/AppIcon.icns"

echo "🎨 Generating app icon..."
echo "📥 Input image: $INPUT_IMAGE"

# Create temporary iconset directory
rm -rf "$ICONSET_NAME"
mkdir -p "$ICONSET_NAME"

# macOS app icon required sizes (including @2x high-resolution versions)
# Format: icon_<size>x<size>.png and icon_<size>x<size>@2x.png

echo "📐 Generating icon sizes..."

# macOS requires specific icon sizes in iconset
# Use -z to resize maintaining aspect ratio
# Note: If source image is not square, sips will add padding (white by default)
# To avoid white borders, ensure source image is square or use --padColor to match background
sips -z 16 16 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_16x16.png" > /dev/null 2>&1 || { echo "Failed to generate 16x16"; exit 1; }
sips -z 32 32 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_16x16@2x.png" > /dev/null 2>&1 || { echo "Failed to generate 16x16@2x"; exit 1; }
sips -z 32 32 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_32x32.png" > /dev/null 2>&1 || { echo "Failed to generate 32x32"; exit 1; }
sips -z 64 64 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_32x32@2x.png" > /dev/null 2>&1 || { echo "Failed to generate 32x32@2x"; exit 1; }
sips -z 128 128 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_128x128.png" > /dev/null 2>&1 || { echo "Failed to generate 128x128"; exit 1; }
sips -z 256 256 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_128x128@2x.png" > /dev/null 2>&1 || { echo "Failed to generate 128x128@2x"; exit 1; }
sips -z 256 256 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_256x256.png" > /dev/null 2>&1 || { echo "Failed to generate 256x256"; exit 1; }
sips -z 512 512 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_256x256@2x.png" > /dev/null 2>&1 || { echo "Failed to generate 256x256@2x"; exit 1; }
sips -z 512 512 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_512x512.png" > /dev/null 2>&1 || { echo "Failed to generate 512x512"; exit 1; }
sips -z 1024 1024 "$INPUT_IMAGE" --out "$ICONSET_NAME/icon_512x512@2x.png" > /dev/null 2>&1 || { echo "Failed to generate 512x512@2x"; exit 1; }

# Verify all files were created
missing_files=0
required_files=(
    "icon_16x16.png"
    "icon_16x16@2x.png"
    "icon_32x32.png"
    "icon_32x32@2x.png"
    "icon_128x128.png"
    "icon_128x128@2x.png"
    "icon_256x256.png"
    "icon_256x256@2x.png"
    "icon_512x512.png"
    "icon_512x512@2x.png"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$ICONSET_NAME/$file" ]; then
        echo "⚠️  Warning: Missing $file"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    echo "❌ Error: Failed to generate $missing_files icon files"
    rm -rf "$ICONSET_NAME"
    exit 1
fi

echo "✅ Generated all icon sizes"

# Generate .icns file using iconutil
echo "🔨 Generating .icns file..."

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_ICNS")"

# Use iconutil with correct syntax: --convert icns --output
if iconutil --convert icns --output "$OUTPUT_ICNS" "$ICONSET_NAME" 2>&1; then
    echo "✅ Icon generated successfully!"
    echo "📦 Output file: $OUTPUT_ICNS"
    
    # Clean up temporary files
    rm -rf "$ICONSET_NAME"
    
    echo ""
    echo "💡 Tip: Icon has been generated, you can now run build_app.sh to build the app"
else
    echo "❌ Icon generation failed"
    echo "Debug: Checking iconset contents..."
    ls -lh "$ICONSET_NAME" 2>/dev/null || echo "Iconset directory not found"
    echo "Keeping iconset directory for debugging: $ICONSET_NAME"
    exit 1
fi

