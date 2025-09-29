# RunMusic App - Current State Documentation
Last Updated: 2025-09-28

## 🎯 Project Overview
RunMusic is an iOS app that combines Strava running data with Spotify listening history to create beautiful, shareable cards. Built with SwiftUI for iOS 17+.

## 🏗️ Current Architecture

### Core App Flow
```
ContentView (entry point)
  ↓
RunCardStackView (main interface)
  ↓ 
RunDetailView (canvas customization)
```

### Main Views
- **ContentView.swift**: App entry point with authentication routing
- **RunCardStackView.swift**: Card-based interface for browsing runs (primary view)  
- **RunDetailView.swift**: Canvas view for customizing shareable cards
- **AuthenticationView.swift**: Strava OAuth authentication flow

### Key Services
- **StravaService.swift**: Strava API integration for run data
- **SpotifyService.swift**: Spotify API for music data matching
- **FirestoreService.swift**: Firebase cloud storage
- **PhotoService.swift**: Photo background management
- **AuthViewModel.swift**: Authentication state management

## 🌐 Firebase Cloud Functions

### Available Endpoints
1. **Continuous Spotify Sync**: `continuousSpotifySync` - Runs every 45 minutes to sync all users
2. **Personal Homepage API**: `myLatestWorkout` - ✅ **WORKING** Public endpoint for latest activity
3. **Strava Webhooks**: `stravaWebhook` - Real-time activity updates  
4. **Authentication Functions**: User account management

### ✅ Personal Homepage API - WORKING
- **URL**: `https://us-central1-runmusic-be.cloudfunctions.net/myLatestWorkout`
- **Status**: ✅ **FULLY FUNCTIONAL** - Returns most recent workout data with 30-day stats
- **CORS**: Enabled for web integration
- **Cache**: 5-minute cache headers  
- **Data Source**: Live Strava API with automatic token refresh
- **Filter**: Only activities over 10 minutes duration
- **Sorting**: Activities sorted by date to ensure most recent is returned

### Strava Webhook Integration
- **Webhook ID**: Active webhook for real-time activity sync
- **Verification**: Proper signature validation
- **Processing**: Stores activities in `users/{userId}/activities` collection

## 📱 Data Architecture

### Firebase Collections
```
users/
  {userId}/
    - displayName, email, stravaUserId
    tokens/
      strava/           - Main Strava tokens
      strava_public/    - Public endpoint tokens  
      spotify/          - Spotify tokens
    cachedRuns/         - Cached run activities (used by homepage API)
    activities/         - Full run data with Spotify tracks (webhook target)
    
spotifyListeningHistory/  - Global Spotify track collection
userSyncSettings/         - Background sync preferences
```

### Authentication Flow
1. **Strava First**: Primary authentication for run data access
2. **Spotify Second**: Optional music integration  
3. **Firebase**: Optional account persistence (Google/Apple Sign-In)

## 📊 Data Storage Patterns

### Run Data
- **Primary Storage**: `users/{userId}/cachedRuns` (used by app UI)
- **Webhook Target**: `users/{userId}/activities` (real-time webhook data)
- **Format**: RunActivity model with embedded Spotify tracks

### Spotify Data  
- **Global Collection**: `spotifyListeningHistory` (unified across users)
- **Background Sync**: 45-minute scheduled function for all users (`continuousSpotifySync`)
- **Track Matching**: Time-based matching with run duration
- **Token Security**: AES-256-GCM encryption with SHA256 key derivation

## 🔧 Key Implementation Details

### Card Stack Interface
- **Main View**: `RunCardStackView.swift` - Primary app interface
- **Individual Cards**: `RunCardView.swift` - Run data display
- **Navigation**: Swipe up/down for browsing, tap for canvas view

## 🎨 Canvas Customization System

### Canvas Assets (RunDetailView.swift)
- **Interactive Elements**: Drag, pinch, rotate gestures for all assets
- **Asset Types**: title/distance, route map, song list, stats, power song
- **Export**: High-resolution image generation for sharing
- **Portrait Mode**: Optimized for Instagram Stories (1080×1920)

### Visual Customization
- **8 Color Schemes**: Gradient themes for different aesthetics
- **Photo Backgrounds**: Camera roll integration with filter system
- **Font Selection**: 14 font families available
- **Dynamic Layouts**: Weather-based theming and route visualization

## 🚀 Development Environment

### Project Structure
- **Xcode Project**: `RunMusic.xcodeproj`
- **Platform**: iOS 17.0+
- **Dependencies**: Firebase SDK, Photos framework, AVFoundation
- **URL Scheme**: `runthetunes://`

### Key Test Commands
```bash
# Build for simulator
xcodebuild -project RunMusic.xcodeproj -scheme RunMusic -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests  
xcodebuild test -project RunMusic.xcodeproj -scheme RunMusic -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 📋 Current Status

### ✅ Working Features
1. **Card Stack Interface**: Swipe-based run browsing with smooth animations
2. **Canvas Customization**: Drag/pinch/rotate assets for shareable cards  
3. **Authentication**: Strava OAuth (primary), Spotify OAuth (music), Firebase (optional)
4. **Data Integration**: Strava runs + Spotify music matching
5. **Firebase Cloud Functions**: Continuous sync, webhooks, public API
6. **Export System**: High-quality image generation for sharing
7. **✅ Personal Homepage API**: Public endpoint with latest workout + 30-day stats
8. **✅ Spotify Authentication Restored**: Fixed Settings UI and token encryption (Sept 2025)
9. **✅ Spotify Sync Fixed**: Cloud function now syncing tracks every 45 minutes (Sept 28, 2025)

### 🏠 Personal Homepage Integration
**Production Endpoint**: `https://us-central1-runmusic-be.cloudfunctions.net/myLatestWorkout`

**Response Format:**
```json
{
  "success": true,
  "activity": {
    "type": "Hike",
    "distance": 15.63,
    "distanceUnit": "miles", 
    "duration": 27365,
    "durationFormatted": "456:05",
    "date": "2025-08-31T14:03:16Z",
    "name": "mountain miles in mammoth",
    "location": "Location not available"
  },
  "stats": {
    "workoutDaysLast30": 8,
    "totalWorkouts": 10
  }
}
```

**Features:**
- ✅ Returns most recent workout over 10 minutes
- ✅ Includes distance in miles, duration, activity type, date, name
- ✅ Provides 30-day workout statistics (days active + total workouts)
- ✅ CORS enabled for web integration
- ✅ Automatic Strava token refresh
- ✅ 5-minute response caching

### 🔧 Quick Test Commands
```bash
# Test homepage endpoint
curl "https://us-central1-runmusic-be.cloudfunctions.net/myLatestWorkout"

# Build and test app
xcodebuild -project RunMusic.xcodeproj -scheme RunMusic -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## 🔧 Recent Fixes (September 28, 2025)

### 🎵 Spotify Sync Resolution
**Issue**: Users were not seeing Spotify songs in the app - sync had been broken since August 23, 2025.

**Root Cause**: Spotify API `/me/player/recently-played` endpoint has mutually exclusive parameters - you can use either `after` OR `before`, but not both simultaneously. The cloud function was sending both parameters, causing 400 Bad Request errors.

**Solution**: 
- Removed the `before` parameter from API calls in `fetchSpotifyRecentTracks` function
- Added enhanced error logging for future debugging
- Verified timezone consistency (UTC storage, Pacific Time display)

**Result**: ✅ Successfully synced 44 tracks spanning August 23 - September 28, 2025. Function now runs every 45 minutes automatically.

**Key Files Modified**:
- `/Users/ckubal/functions/src/index.ts` - Fixed API parameters and error logging
- Spotify API call now uses only `after: startTime.getTime()` parameter

## 🛠️ Development Tools & MCPs

### Nuanced MCP Integration
When working on TypeScript/Node.js components (Firebase Cloud Functions, Next.js apps), use the Nuanced MCP for enhanced code analysis:

**When to Use Nuanced**:
- Debugging complex function call chains (like the Spotify sync flow: `continuousSpotifySync` → `syncUserSpotifyHistory` → `fetchSpotifyRecentTracks`)
- Understanding cross-file dependencies in Firebase functions
- Refactoring functions safely with impact analysis
- Generating AI-assisted code reviews and test cases

**Best Practices**:
- Generate call graphs before modifying cloud functions
- Use function enrichment to understand token flow and API interactions  
- Leverage change impact analysis when updating shared utilities
- Local execution ensures Firebase/Spotify API keys stay private

**Note**: Nuanced currently supports TypeScript only - use for Firebase functions, not iOS Swift code.

## 🎯 Development Notes
- Homepage API uses live Strava API calls with automatic token management
- Endpoint filters for activities over 10 minutes and sorts by date for most recent
- 30-day stats count unique workout days for consistency tracking
- Spotify sync processes ~44 tracks per user per sync cycle when catching up from gaps
- Token encryption uses industry-standard AES-256-GCM with SHA256 key derivation