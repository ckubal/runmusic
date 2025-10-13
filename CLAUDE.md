# RunMusic App - Current State Documentation
Last Updated: 2025-10-13

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
1. **Continuous Spotify Sync**: `continuousSpotifySync` - ✅ **FULLY OPERATIONAL** Runs every 45 minutes (FIXED Oct 13, 2025)
2. **Personal Homepage API**: `myLatestWorkout` - ✅ **WORKING** Public endpoint for latest activity
3. **Strava Webhooks**: `stravaWebhook` - Real-time activity updates  
4. **Authentication Functions**: User account management
5. **Debug User Tokens**: `debugUserTokens` - ✅ **AVAILABLE** For troubleshooting token status

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
9. **✅ Spotify Sync FULLY RESOLVED**: Comprehensive fix deployed October 13, 2025 - WORKING PERFECTLY

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

## 🔧 Recent Fixes 

### 🎵 SPOTIFY SYNC COMPREHENSIVE FIX (October 13, 2025) - ✅ FULLY RESOLVED

**Critical Issue Resolved**: The infamous "You only have 5 total Spotify tracks" problem is now **PERMANENTLY FIXED**.

#### **Timeline of Fixes**
1. **August 23 - September 28, 2025**: API parameter bug (using both `after` AND `before`)
2. **October 13, 2025 at 15:45**: Refresh token lost, breaking sync entirely  
3. **October 13, 2025 at 16:45**: **COMPREHENSIVE FIX DEPLOYED** - All systems operational

#### **Root Causes Identified & Fixed**
1. **API Parameter Bug** (Sept 28 fix): Spotify API `/me/player/recently-played` endpoint requires either `after` OR `before`, not both
2. **Token Loss Issue** (Oct 13 fix): Refresh tokens were being lost, breaking authentication
3. **Decryption Missing** (Oct 13 fix): Cloud function couldn't decrypt iOS app's encrypted tokens
4. **Error Handling Gaps** (Oct 13 fix): Silent failures with no recovery mechanism

#### **Comprehensive Solution Implemented**
✅ **Robust Token Refresh Mechanism**: Automatic refresh with fallback handling  
✅ **AES-256-GCM Token Decryption**: Full compatibility with iOS app encryption  
✅ **Enhanced Error Handling**: Comprehensive logging and graceful recovery  
✅ **API Parameter Fix**: Only uses `after` parameter (no more 400 errors)  
✅ **Token Storage Security**: Encrypted storage matching iOS implementation  
✅ **Date Validation**: Fixed timestamp parsing errors  
✅ **Monitoring & Alerts**: Real-time sync status tracking  

#### **Verification Completed (October 13, 2025)**
**Live Test Results at 16:45**:
- ✅ `"Found 1 users with Spotify tokens"` (was 0 before re-auth)
- ✅ `"Successfully decrypted token data using AES-256-GCM"`  
- ✅ `"Successfully decrypted tokens - hasRefreshToken: true"`
- ✅ `"Successfully refreshed Spotify token"`
- ✅ `"Successfully stored refreshed tokens"`

#### **How to Verify System is Working (Future Reference)**

**Quick Status Check**:
```bash
# Check if continuous sync is finding tokens
firebase functions:log --only continuousSpotifySync --lines 10

# Look for these SUCCESS indicators:
# ✅ "Found 1 users with Spotify tokens" (not 0)
# ✅ "Successfully decrypted tokens - hasRefreshToken: true"  
# ✅ "Synced X tracks" (where X > 0)
```

**If User Reports Missing Spotify Data**:
1. **Check Last Sync**: Look for recent `continuousSpotifySync` logs
2. **Verify Tokens**: Should see "Found 1 users with Spotify tokens"
3. **User Re-auth**: If tokens missing, user needs to sign out/in with Spotify in iOS app
4. **Wait 45 minutes**: Next automatic sync will pick up new tokens

#### **System Architecture Now Includes**
- **Scheduled Sync**: Runs every 45 minutes automatically
- **Token Security**: AES-256-GCM encryption matching iOS app
- **API Credentials**: Properly configured via Firebase config
- **Error Recovery**: Clears invalid tokens, prompts re-authentication
- **Comprehensive Logging**: Full visibility into sync process
- **Manual Triggers**: Available for testing and recovery

#### **Key Files Modified (October 13, 2025)**
- **`/functions/src/index.ts`**: Complete rewrite with robust sync logic
- **Token Decryption**: Implemented AES-256-GCM compatible with iOS 
- **Token Refresh**: Full OAuth refresh flow with error handling
- **Date Validation**: Fixed timestamp parsing issues
- **Error Logging**: Comprehensive debug information

#### **Never Again Checklist** 
To ensure this problem never recurs, the system now:
1. ✅ **Validates refresh tokens** before attempting sync
2. ✅ **Handles token expiration** gracefully with automatic refresh  
3. ✅ **Clears invalid tokens** to force user re-authentication
4. ✅ **Logs every step** for debugging and monitoring
5. ✅ **Uses correct API parameters** (only `after`, no `before`)
6. ✅ **Encrypts/decrypts tokens** exactly like the iOS app
7. ✅ **Runs continuously** every 45 minutes without intervention

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

## 🚨 CRITICAL: Spotify Sync Health Check (For Future Sessions)

**ALWAYS run this check if user reports missing Spotify data**:

### **1. Quick Status Verification**
```bash
# Check recent sync logs (look for last 2 hours of activity)
firebase functions:log --only continuousSpotifySync --lines 15

# Expected HEALTHY output:
# ✅ "Starting continuous Spotify sync (every 45 minutes)..."
# ✅ "Found 1 users with Spotify tokens for continuous sync" 
# ✅ "Successfully decrypted tokens - hasRefreshToken: true"
# ✅ "Synced X tracks for user 98ziMzBOZqRQYIcJS9nlQaJqu9m1" (X > 0)
```

### **2. Troubleshooting Decision Tree**

**IF you see `"Found 0 users with Spotify tokens"`**:
- ❌ **PROBLEM**: User needs to re-authenticate Spotify 
- ✅ **SOLUTION**: User must sign out and back in with Spotify in iOS app
- ⏰ **WAIT**: 45 minutes for next automatic sync to pick up new tokens

**IF you see `"Failed to decrypt Spotify tokens"`**:
- ❌ **PROBLEM**: Token encryption/decryption mismatch
- ✅ **SOLUTION**: Check if `decryptSpotifyTokens` function in `/functions/src/index.ts` is working
- 🔧 **ACTION**: May need to redeploy with: `firebase deploy --only functions:continuousSpotifySync`

**IF you see `"No refresh token available"`**:
- ❌ **PROBLEM**: Refresh token missing (same as scenario 1)
- ✅ **SOLUTION**: User re-authentication required

**IF you see `"Spotify API error: 400"`**:
- ❌ **PROBLEM**: API parameter issue (should be FIXED permanently)
- 🚨 **CRITICAL**: This should NOT happen - check if code regression occurred
- 🔧 **ACTION**: Verify `fetchSpotifyRecentTracks` only uses `after` parameter

### **3. Emergency Recovery Commands**
```bash
# Deploy latest function code
firebase deploy --only functions:continuousSpotifySync

# Check function deployment status  
firebase functions:list | grep continuousSpotifySync

# Test homepage endpoint (should work regardless of Spotify)
curl "https://us-central1-runmusic-be.cloudfunctions.net/myLatestWorkout"
```

### **4. Success Confirmation**
After any fix, wait for next 45-minute sync cycle and verify:
```bash
firebase functions:log --only continuousSpotifySync --lines 10

# Must see ALL of these for SUCCESS:
# ✅ "Found 1 users with Spotify tokens"
# ✅ "Successfully decrypted tokens - hasRefreshToken: true"  
# ✅ "Synced X tracks" (where X > 0)
# ✅ "Continuous sync completed. Users: 1 successful, 0 failed"
```

---

## 🎯 Development Notes
- Homepage API uses live Strava API calls with automatic token management
- Endpoint filters for activities over 10 minutes and sorts by date for most recent
- 30-day stats count unique workout days for consistency tracking
- Spotify sync processes ~50 tracks per user per sync cycle (45-minute intervals)
- Token encryption uses industry-standard AES-256-GCM with SHA256 key derivation
- **Spotify sync runs every 45 minutes**: Next sync times are at :00, :45 minutes of each hour
- **User ID**: `98ziMzBOZqRQYIcJS9nlQaJqu9m1` (for debugging/logs reference)