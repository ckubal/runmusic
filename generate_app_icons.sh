#!/bin/bash

# App Icon Generator Script
# This script takes your 1024x1024 app icon and generates all required iOS sizes

SOURCE_ICON="/Users/ckubal/Documents/Programming/iOS Programming Projects/fortune cookie/RunMusic/RunMusic/Assets.xcassets/AppIcon.appiconset/appstore.png"
OUTPUT_DIR="/Users/ckubal/Documents/Programming/iOS Programming Projects/fortune cookie/RunMusic/RunMusic/Assets.xcassets/AppIcon.appiconset"

echo "🎨 Generating iOS app icons from source: $SOURCE_ICON"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Source icon not found at: $SOURCE_ICON"
    exit 1
fi

# Required iOS icon sizes (filename: width x height)
declare -A ICON_SIZES=(
    # iPhone notification icons
    ["icon-20@2x.png"]="40"
    ["icon-20@3x.png"]="60"
    
    # iPhone settings icons  
    ["icon-29@2x.png"]="58"
    ["icon-29@3x.png"]="87"
    
    # iPhone spotlight icons
    ["icon-40@2x.png"]="80"
    ["icon-40@3x.png"]="120"
    
    # iPhone app icons
    ["icon-60@2x.png"]="120"
    ["icon-60@3x.png"]="180"
    
    # iPad notification icons
    ["icon-20@1x.png"]="20"
    ["icon-20@2x-ipad.png"]="40"
    
    # iPad settings icons
    ["icon-29@1x.png"]="29"
    ["icon-29@2x-ipad.png"]="58"
    
    # iPad spotlight icons
    ["icon-40@1x.png"]="40"
    ["icon-40@2x-ipad.png"]="80"
    
    # iPad app icons
    ["icon-76@2x.png"]="152"
    ["icon-83.5@2x.png"]="167"
)

# Generate all required sizes using sips (built into macOS)
for filename in "${!ICON_SIZES[@]}"; do
    size=${ICON_SIZES[$filename]}
    output_path="$OUTPUT_DIR/$filename"
    
    echo "📱 Generating $filename (${size}x${size}px)..."
    sips -z $size $size "$SOURCE_ICON" --out "$output_path" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Generated $filename"
    else
        echo "❌ Failed to generate $filename"
    fi
done

echo ""
echo "🎉 App icon generation complete!"
echo "💡 Now update the Contents.json file to reference these new icons"
echo ""