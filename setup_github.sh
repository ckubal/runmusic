#!/bin/bash

# Setup GitHub repository for RunMusic
# Run this script AFTER creating the repository on GitHub.com

echo "Setting up GitHub repository for RunMusic..."

# Add the correct remote (replace YOUR_USERNAME with your actual GitHub username)
git remote add origin https://github.com/ckubal/RunMusic.git

# Make initial commit
git commit -m "Initial commit: RunMusic iOS app

Features:
- SwiftUI iOS app combining Strava + Spotify data
- Card-based interface for shareable workout summaries  
- Canvas customization with drag/drop assets
- Firebase backend with cloud functions
- Real-time Spotify sync (45-minute intervals)
- Strava webhook integration
- Public API endpoint for homepage integration

⚠️  TODO: Move hardcoded API keys to secure configuration
- Strava client ID/secret in StravaService.swift
- Spotify client ID/secret in SpotifyService.swift  
- Weather API key in WeatherService.swift"

# Push to GitHub
echo "Pushing to GitHub..."
git branch -M main
git push -u origin main

echo "✅ Repository setup complete!"
echo "🔗 Your repository: https://github.com/ckubal/RunMusic"
echo "⚠️  Remember to secure the API keys before production deployment"