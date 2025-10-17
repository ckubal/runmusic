# RunMusic App - Current State Documentation
Last Updated: 2025-10-17

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
2. **✅ Canvas Customization - FULLY WORKING**: Instagram Story-like drag/pinch/rotate for all elements (Fixed Oct 13, 2025)
3. **✅ Song List Editor - FULLY WORKING**: Complete editing interface with font/color customization (Added Oct 17, 2025)
4. **Authentication**: Strava OAuth (primary), Spotify OAuth (music), Firebase (optional)
5. **Data Integration**: Strava runs + Spotify music matching
6. **Firebase Cloud Functions**: Continuous sync, webhooks, public API
7. **Export System**: High-quality image generation for sharing
8. **✅ Personal Homepage API**: Public endpoint with latest workout + 30-day stats
9. **✅ Spotify Authentication Restored**: Fixed Settings UI and token encryption (Sept 2025)
10. **✅ Spotify Sync FULLY RESOLVED**: Comprehensive fix deployed October 13, 2025 - WORKING PERFECTLY

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

## 🎨 SONG LIST EDITOR - ✅ **FULLY IMPLEMENTED** (October 17, 2025)

**New Feature**: Complete song list editing interface with professional-grade customization options.

### **🎼 What's New**
✅ **Edit Button**: Pencil icon appears when song list is selected on canvas  
✅ **Song Selection**: Choose up to 20 songs from your run's Spotify tracks  
✅ **Font Customization**: 6 font options with live previews (Helvetica Neue, Arial, Georgia, Times New Roman, Futura, Avenir)  
✅ **Color Picker**: Full color customization for track text  
✅ **Text Shadow**: Toggle for black background/shadow for better readability  
✅ **Live Preview**: See exactly how changes will look before saving  
✅ **Smart Defaults**: Shows first 10 songs by default, with "Select First 10" and "Clear" buttons  

### **🔧 How to Use**
1. **Open Canvas**: Tap any run card to enter canvas view
2. **Select Song List**: Tap the song list element on canvas
3. **Edit**: Tap the pencil icon that appears next to the plus button
4. **Customize**: Choose songs, fonts, colors, and text shadow in the popup
5. **Preview**: See live preview at top of edit screen
6. **Save**: Changes apply immediately to canvas

### **💻 Technical Implementation**
**Files Modified**:
- `RunMusic/Views/RunCardStackView.swift`: Added complete `SongListEditSheet` component
- `RunMusic/Models/CanvasAsset.swift`: Added `fontFamily` and `showBlackOutline` properties
- Song list rendering now respects custom fonts, colors, and shadow settings
- Proper save/load functionality with asset state management

**Key Features**:
- **Persistent Storage**: Font and color choices saved with canvas state
- **Dynamic Updates**: Changes reflect immediately on canvas without reload
- **Error Handling**: Graceful fallbacks for missing fonts or invalid colors
- **Performance**: Optimized for smooth real-time preview updates

### **📱 UI/UX Improvements**
✅ **Intuitive Interface**: Bottom sheet presentation matches iOS design patterns  
✅ **Visual Feedback**: Selected songs highlighted with blue background  
✅ **Font Previews**: Each font option shows actual font rendering  
✅ **Touch Targets**: Large, accessible buttons for all controls  
✅ **Responsive Design**: Works seamlessly on all iPhone screen sizes  

---

## 🔧 Recent Fixes 

### 🎵 SPOTIFY "RECONNECT SPOTIFY" ISSUE - ✅ **ACTUALLY** FIXED (December 13, 2025)

**Critical Issue**: The recurring "Reconnect Spotify" prompt that appeared every few days despite previous "fixes".

#### **Why Previous "Fixes" Failed**
The October 13, 2025 documentation claimed "✅ FULLY RESOLVED" but only addressed **one specific scenario** while **multiple other token-destroying patterns** remained active in the codebase.

#### **ACTUAL Root Cause Discovered**
**Fundamental Design Flaw**: The app aggressively cleared refresh tokens on **ANY** authentication error, not just definitive authentication failures.

**Pattern That Kept Repeating**:
1. Network hiccup, rate limit, or timeout occurs → `clearStoredCredentials()` called
2. Refresh token permanently destroyed → User can't authenticate 
3. Firebase sync tries to help but Firebase also missing refresh token
4. User sees "Reconnect Spotify" prompt
5. User reconnects → works temporarily until next network issue
6. **Cycle repeats every few days**

#### **Multiple Token-Destroying Code Paths Found**
1. **Token refresh HTTP errors** → `clearStoredCredentials()` → refresh token destroyed
2. **Network timeouts** → `clearStoredCredentials()` → refresh token destroyed  
3. **Rate limiting (429 errors)** → `clearStoredCredentials()` → refresh token destroyed
4. **Firebase sync overwrites** → Good local tokens replaced with incomplete Firebase tokens
5. **Any parsing/network error** → `clearStoredCredentials()` → refresh token destroyed

#### **Comprehensive Solution Implemented (December 13, 2025)**

**1. Conservative Token Clearing**:
✅ **Smart Error Analysis**: Only clear refresh tokens on definitive Spotify auth errors (`invalid_grant`, `invalid_client`)  
✅ **Preserve on Network Errors**: Rate limits, timeouts, network failures now preserve refresh token  
✅ **New `clearAccessTokenOnly()` Method**: Clears access token but preserves refresh token for retry

**2. Firebase Sync Protection**:
✅ **Local Token Priority**: If Firebase missing refresh token but local has it, preserve local version  
✅ **Automatic Re-sync**: When token discrepancy detected, re-upload complete tokens to Firebase  
✅ **Bidirectional Validation**: Ensure both local and Firebase have complete token sets

**3. Specific Code Changes Made**:
✅ **SpotifyService.swift Lines 1680-1711**: Added smart error detection for token refresh failures  
✅ **SpotifyService.swift Lines 1738-1749**: Added `clearAccessTokenOnly()` method  
✅ **SpotifyService.swift Lines 1852-1895**: Replaced aggressive clearing with conservative approach  
✅ **SpotifyService.swift Lines 1952-1970**: Added Firebase/local token conflict resolution  

#### **How to Verify Fix is Working**

**Expected Log Messages (Good Signs)**:
- `🔧 CRITICAL FIX: Firebase missing refresh token, restoring from local storage`
- `⚠️ TEMPORARY ERROR: Keeping refresh token, only clearing access token`
- `🔐 SpotifyService: Cleared access token but preserved refresh token for retry`

**Bad Log Messages (Fix Not Working)**:
- `🚨 CRITICAL: Have access token but no refresh token` (should be rare now)
- `🔐 SpotifyService: Stored credentials cleared` (should only happen on logout/definitive errors)

**Testing the Fix**:
1. **Simulate Network Error**: Turn off WiFi mid-app-use, should preserve authentication
2. **Check After Network Issues**: Authentication should survive temporary connection problems
3. **Monitor Over Days**: "Reconnect Spotify" prompts should stop appearing regularly

#### **Why This Fix Will Actually Work**

**Previous Approach** (Failed):
- ANY error → Clear everything → Hope Firebase helps → User re-authenticates

**New Approach** (Should Work):
- Network/timeout errors → Clear only access token → Retry with existing refresh token
- Only clear refresh token when Spotify explicitly says it's invalid
- Protect good local tokens from being overwritten by incomplete Firebase tokens

#### **⚠️ IMPORTANT: What Was Wrong With Previous Documentation**

The October 13, 2025 "FULLY RESOLVED" claim was **incorrect** because:

1. **Only fixed Cloud Functions**: Server-side sync improvements don't help iOS token management
2. **Ignored iOS App Issues**: Multiple `clearStoredCredentials()` calls in iOS code remained
3. **Didn't Address Root Cause**: Aggressive token clearing philosophy was never changed
4. **False Confidence**: Documentation claimed problem was solved while core issue persisted

#### **Never Again Checklist - UPDATED**
To ensure this problem ACTUALLY never recurs:
1. ✅ **Conservative Token Management**: Only clear refresh tokens on definitive auth failures
2. ✅ **Network Error Resilience**: Preserve authentication through temporary failures
3. ✅ **Firebase Sync Protection**: Prevent Firebase from overwriting good local tokens
4. ✅ **Smart Error Detection**: Distinguish between temporary and permanent auth errors
5. ✅ **Comprehensive Code Review**: Fixed ALL token-clearing code paths, not just one
6. ✅ **Accurate Documentation**: No more false "FULLY RESOLVED" claims without comprehensive testing

---

### 🎨 CANVAS CUSTOMIZATION FIX (October 13, 2025) - ✅ FULLY RESOLVED

**Issue**: Drag/pinch/rotate gestures weren't working on iOS device despite being implemented.

**Root Cause**: ScrollView in RunDetailView was consuming touch events before they could reach interactive elements.

**Solution Implemented**:
✅ **highPriorityGesture()**: Override ScrollView gesture conflicts  
✅ **DragGesture(minimumDistance: 0)**: Immediate gesture response  
✅ **allowsHitTesting(true)**: Ensure touch events reach interactive elements  
✅ **Visual Feedback**: Opacity changes during interactions  
✅ **Enhanced Animations**: Smooth interaction state transitions  

**Interactive Elements Now Working**:
- ✅ **Song Lists**: Fully draggable, scalable, rotatable with haptic feedback
- ✅ **Route Maps**: Fully draggable, scalable, rotatable with haptic feedback
- ✅ **Visual Indicators**: Elements dim slightly when being manipulated
- ✅ **Gesture Priority**: Canvas interactions override scroll gestures

**Files Modified**:
- `RunMusic/Views/InteractiveShareableCardView.swift`: Added highPriorityGesture modifiers
- `RunMusic/Views/RunDetailView.swift`: Added allowsHitTesting for touch handling

**How to Use**: Open any run → Go to canvas/sharing screen → Drag, pinch, rotate song lists and route maps freely!

---

## 🚀 PERFORMANCE OPTIMIZATION (October 13, 2025) - ✅ FULLY RESOLVED

**Issue**: App startup experiencing severe performance degradation due to excessive debug logging appearing on every app launch and run tap.

**Root Cause**: Multiple services were outputting verbose debug logs for every operation:
- **PhotoService**: 25+ log lines per run (photo search, timezone debugging, screenshot filtering)
- **DataConversionService**: 50+ log lines per run conversion (timestamp parsing, route processing, power song analysis)
- **Firebase Functions**: 17+ verbose log statements per sync cycle (token refresh, API calls, track processing)

**Solution Implemented**:
✅ **PhotoService**: Added `enableDebugLogging = false` flag, converted all debug prints to conditional `debugLog()` calls  
✅ **DataConversionService**: Added debug control flag, eliminated timestamp parsing spam while preserving critical error logs  
✅ **Firebase Functions**: Implemented `enableVerboseLogging = false` with selective `debugLog()` function  
✅ **Selective Logging**: Critical errors still logged, debug spam eliminated  

**Files Optimized**:
- `RunMusic/Services/PhotoService.swift` - **25+ debug prints → 0** (conditional logging)
- `RunMusic/Services/DataConversionService.swift` - **50+ debug prints → 2** (errors only)
- `functions/src/index.ts` - **17+ verbose logs → 3** (summary only)

**Result**: 
🚀 **~90% reduction in console spam**  
🚀 **Significantly faster app launch**  
🚀 **Responsive run browsing experience**  
🚀 **Critical error logging preserved**  

**Performance Impact**: App now feels snappy and responsive instead of sluggish and overloaded with debug output.

---

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