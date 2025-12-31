#!/usr/bin/env python3
"""
Generate macOS app icon (.icns) from an image file
"""

import sys
import os
import subprocess
import shutil
from pathlib import Path

def generate_icon(input_image, output_icns):
    """Generate .icns file from input image"""
    
    iconset_name = "VeloxClip.iconset"
    output_path = Path(output_icns)
    
    # Create output directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Remove old iconset if exists
    if os.path.exists(iconset_name):
        shutil.rmtree(iconset_name)
    os.makedirs(iconset_name)
    
    print("🎨 Generating app icon...")
    print(f"📥 Input image: {input_image}")
    
    # Required icon sizes for macOS
    icon_sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    print("📐 Generating icon sizes...")
    
    # Generate all sizes using sips
    for size, filename in icon_sizes:
        output_file = os.path.join(iconset_name, filename)
        result = subprocess.run(
            ["sips", "-z", str(size), str(size), input_image, "--out", output_file],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"❌ Failed to generate {filename}: {result.stderr}")
            shutil.rmtree(iconset_name)
            return False
    
    print("✅ Generated all icon sizes")
    
    # Generate .icns file using iconutil
    print("🔨 Generating .icns file...")
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset_name, "-o", str(output_path)],
        capture_output=True,
        text=True
    )
    
    # Clean up
    shutil.rmtree(iconset_name)
    
    if result.returncode != 0:
        print(f"❌ Icon generation failed: {result.stderr}")
        return False
    
    print(f"✅ Icon generated successfully!")
    print(f"📦 Output file: {output_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 generate_icon.py <image_path>")
        print("Example: python3 generate_icon.py icon.png")
        sys.exit(1)
    
    input_image = sys.argv[1]
    output_icns = "VeloxClip/Resources/AppIcon.icns"
    
    if not os.path.exists(input_image):
        print(f"❌ Error: File not found '{input_image}'")
        sys.exit(1)
    
    if generate_icon(input_image, output_icns):
        print("\n💡 Tip: Icon has been generated, you can now run build_app.sh to build the app")
        sys.exit(0)
    else:
        sys.exit(1)

