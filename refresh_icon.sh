#!/bin/bash

# Force refresh macOS icon cache

APP_NAME="VeloxClip.app"
ICON_FILE="VeloxClip/Resources/AppIcon.icns"

if [ ! -f "$ICON_FILE" ]; then
    echo "❌ Error: Icon file not found: $ICON_FILE"
    exit 1
fi

echo "🔄 Refreshing icon cache..."

# Copy icon to app bundle
if [ -d "$APP_NAME" ]; then
    cp "$ICON_FILE" "$APP_NAME/Contents/Resources/AppIcon.icns"
    echo "✅ Icon copied to app bundle"
fi

# Touch the app bundle to update timestamp
touch "$APP_NAME" 2>/dev/null

# Clear icon cache
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null
killall Finder 2>/dev/null

echo "✅ Icon cache cleared"
echo "💡 Tip: The icon should now be visible. If not, try:"
echo "   1. Log out and log back in"
echo "   2. Or restart your Mac"

