#!/bin/bash

# Script to add new Swift files to Xcode project
# Usage: ./add_files_to_xcode.sh

PROJECT_DIR="/Users/ckubal/Documents/Programming/iOS Programming Projects/fortune cookie/RunMusic"
PROJECT_FILE="$PROJECT_DIR/RunMusic.xcodeproj/project.pbxproj"

echo "🔍 Scanning for new Swift files not in Xcode project..."

# Find all Swift files in the project directory
find "$PROJECT_DIR/RunMusic" -name "*.swift" -type f | while read -r file; do
    filename=$(basename "$file")
    
    # Check if file is already referenced in project.pbxproj
    if ! grep -q "$filename" "$PROJECT_FILE"; then
        echo "📄 Found new file: $filename"
        echo "   Path: $file"
        echo "   ⚠️  This file needs to be added to Xcode manually"
        echo "   💡 Drag and drop it into Xcode project navigator"
        echo ""
    fi
done

echo "✅ Scan complete!"
echo ""
echo "🛠️  To add files automatically:"
echo "1. Drag new .swift files from Finder into Xcode project navigator"
echo "2. Ensure 'Add to target: RunMusic' is checked"
echo "3. Click 'Finish'"