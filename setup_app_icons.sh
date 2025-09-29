#!/bin/bash

# Script to help organize app icons for RunMusic
# After generating icons from AppIcon.co or similar service

echo "🎨 RunMusic App Icon Setup Guide"
echo "================================"
echo ""

ICONS_DIR="/Users/ckubal/Documents/Programming/iOS Programming Projects/fortune cookie/RunMusic/AppIcons"
ASSETS_DIR="/Users/ckubal/Documents/Programming/iOS Programming Projects/fortune cookie/RunMusic/RunMusic/Assets.xcassets/AppIcon.appiconset"

echo "📁 Expected icon files needed:"
echo "  - Icon-20.png (20x20)"
echo "  - Icon-29.png (29x29)" 
echo "  - Icon-40.png (40x40)"
echo "  - Icon-58.png (58x58)"
echo "  - Icon-60.png (60x60)"
echo "  - Icon-80.png (80x80)"
echo "  - Icon-87.png (87x87)"
echo "  - Icon-120.png (120x120)"
echo "  - Icon-180.png (180x180)"
echo "  - Icon-1024.png (1024x1024)"
echo ""

if [ -d "$ICONS_DIR" ]; then
    echo "✅ Found AppIcons directory"
    echo "📋 Icons found:"
    ls -la "$ICONS_DIR"/*.png 2>/dev/null || echo "❌ No PNG files found"
else
    echo "📁 Creating AppIcons directory..."
    mkdir -p "$ICONS_DIR"
    echo "✅ Created: $ICONS_DIR"
    echo ""
    echo "📥 Next steps:"
    echo "1. Go to https://appicon.co"
    echo "2. Upload your running shoe image"
    echo "3. Download the generated icons"
    echo "4. Extract them to: $ICONS_DIR"
    echo "5. Run this script again"
fi

echo ""
echo "🎯 Xcode Integration:"
echo "1. Open RunMusic.xcodeproj"
echo "2. Navigate to Assets.xcassets → AppIcon"
echo "3. Drag icons from $ICONS_DIR into the appropriate slots"
echo "4. Or just drag the 1024x1024 icon and let Xcode auto-generate"
echo ""
echo "💡 Pro tip: Make sure your icon:"
echo "   - Is square (width = height)"
echo "   - Has no transparency for the main icon"
echo "   - Looks good at small sizes (20x20)"
echo "   - Follows Apple's design guidelines"