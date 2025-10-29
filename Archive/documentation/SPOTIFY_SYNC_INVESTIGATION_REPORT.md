# Spotify Data Continuity Investigation Report
**Date:** October 13, 2025  
**User ID:** 98ziMzBOZqRQYIcJS9nlQaJqu9m1  
**Issue:** Gaps in Spotify sync from late August 2025 to now

## 🔍 Investigation Summary

Based on my investigation of the RunMusic Firebase project, I've identified several potential causes for the Spotify data continuity issue and created a comprehensive plan to diagnose and fix the problem.

## 📊 Current State Analysis

### ✅ What's Working
1. **Firebase Functions Deployed**: `continuousSpotifySync` function is deployed and scheduled (runs every 45 minutes)
2. **Manual Trigger Available**: `triggerContinuousSync` callable function exists for testing
3. **API Endpoints Functional**: `myLatestWorkout` endpoint returns recent activity data (Oct 11, 2025 run)
4. **iOS App Spotify Service**: Comprehensive authentication and token management system in place

### ❌ Potential Issues Identified

#### 1. **Missing Function Source Code**
- The `continuousSpotifySync` function source code is not in the current `/functions/src/` directory
- Only authentication functions are present in the current source
- This suggests the sync function may be deployed from a different source or an older version

#### 2. **Authentication Requirements**
- Unable to directly query Firebase data due to missing service account authentication
- Cloud function logs require proper authentication to access

#### 3. **Token Management Complexity**
- The iOS app has complex token refresh logic that could be failing silently
- Token encryption/decryption process could be corrupted for the sync function

## 🔧 Diagnostic Plan

### Phase 1: Immediate Data Assessment
```bash
# 1. Run the debug script (requires authentication setup)
cd "/Users/ckubal/Documents/Programming/iOS Programming Projects/RunMusic"
node debug_spotify_continuity.js

# 2. Test manual sync trigger
curl -X POST "https://us-central1-runmusic-be.cloudfunctions.net/triggerContinuousSync" \
  -H "Content-Type: application/json" \
  -d '{"data": {}}'

# 3. Check function logs using Firebase CLI (requires login)
firebase functions:log --only continuousSpotifySync
```

### Phase 2: Function Source Recovery
The `continuousSpotifySync` function appears to be missing from the source code. Based on the CLAUDE.md documentation, this function should:

1. **Run every 45 minutes** (scheduled)
2. **Process all users** in the system
3. **Call `syncUserSpotifyHistory`** for each user
4. **Fetch recent tracks** using `fetchSpotifyRecentTracks`
5. **Store tracks** in `spotifyListeningHistory` collection

### Phase 3: Expected Function Structure
Based on the documented fix from September 28, 2025, the function should look like:

```typescript
// Expected structure of continuousSpotifySync function
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';

export const continuousSpotifySync = onSchedule('every 45 minutes', async (event) => {
  const db = getFirestore();
  
  try {
    // Get all users with Spotify tokens
    const usersSnapshot = await db.collection('users').get();
    
    for (const userDoc of usersSnapshot.docs) {
      await syncUserSpotifyHistory(userDoc.id);
    }
  } catch (error) {
    console.error('Continuous sync error:', error);
  }
});

async function syncUserSpotifyHistory(userId: string) {
  // Implementation missing - this is where the actual sync happens
}

async function fetchSpotifyRecentTracks(accessToken: string, lastSyncTime: Date) {
  // CRITICAL FIX: Only use 'after' parameter, NOT 'before'
  const params = new URLSearchParams({
    limit: '50',
    after: lastSyncTime.getTime().toString()
    // REMOVED: before parameter (this was causing 400 errors)
  });
  
  // Make API call to Spotify...
}
```

## 🚨 Critical Issues Found (September 28, 2025 Fix)

The CLAUDE.md documentation mentions a critical fix was implemented on September 28, 2025:

> **Root Cause**: Spotify API `/me/player/recently-played` endpoint has mutually exclusive parameters - you can use either `after` OR `before`, but not both simultaneously. The cloud function was sending both parameters, causing 400 Bad Request errors.

This suggests the sync was broken from August 23, 2025 until September 28, 2025, but should be working now.

## 📋 Action Plan to Fix Permanently

### Immediate Actions (Next 24 Hours)

1. **Authenticate Firebase CLI**:
   ```bash
   firebase login
   ```

2. **Run Diagnostic Script**:
   ```bash
   node debug_spotify_continuity.js
   ```

3. **Check Function Logs**:
   ```bash
   firebase functions:log --only continuousSpotifySync --lines 100
   ```

4. **Manual Sync Test**:
   ```bash
   # Test if sync can be triggered manually
   firebase functions:shell
   # Then run: triggerContinuousSync()
   ```

### Short-term Fixes (This Week)

1. **Restore Missing Function Source**:
   - Locate the actual deployed source code for `continuousSpotifySync`
   - Add it to the `/functions/src/` directory for version control
   - Ensure the September 28 fix is properly implemented

2. **Implement Enhanced Monitoring**:
   ```typescript
   // Add comprehensive logging to sync function
   console.log(`Starting sync for user ${userId}`);
   console.log(`Last sync time: ${lastSyncTime}`);
   console.log(`Spotify API call: ${apiUrl}`);
   console.log(`Response status: ${response.status}`);
   console.log(`Tracks found: ${tracks.length}`);
   ```

3. **Add Error Recovery**:
   ```typescript
   // Implement retry logic for failed syncs
   async function syncWithRetry(userId: string, maxRetries = 3) {
     for (let attempt = 1; attempt <= maxRetries; attempt++) {
       try {
         await syncUserSpotifyHistory(userId);
         break;
       } catch (error) {
         console.error(`Sync attempt ${attempt} failed:`, error);
         if (attempt === maxRetries) throw error;
         await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
       }
     }
   }
   ```

### Long-term Improvements (Next Month)

1. **Implement Health Monitoring**:
   - Add a `/health` endpoint that checks sync status
   - Set up alerts for sync failures
   - Create dashboard for monitoring sync metrics

2. **Add User-Specific Sync Control**:
   - Allow users to trigger manual sync from the app
   - Show last sync time in the iOS app
   - Add sync status indicators

3. **Implement Backfill Function**:
   ```typescript
   // Function to backfill missing data for specific date ranges
   export const backfillSpotifyData = onCall(async (request) => {
     const { userId, startDate, endDate } = request.data;
     // Implement backfill logic...
   });
   ```

## 🎯 Root Cause Analysis

Based on the evidence, the most likely causes of the sync gaps are:

1. **API Parameter Bug** (Fixed Sept 28): Using both `after` and `before` parameters
2. **Token Expiration**: Spotify tokens expiring and not being refreshed properly
3. **Rate Limiting**: Hitting Spotify API rate limits and not handling them gracefully
4. **Silent Failures**: Function failing without proper error logging/alerts

## 📈 Expected Outcomes

After implementing these fixes:

1. **Continuous Data**: No more gaps in Spotify listening history
2. **Better Monitoring**: Real-time visibility into sync status
3. **Faster Recovery**: Automatic retry and backfill capabilities
4. **User Transparency**: Users can see sync status and manually trigger if needed

## 🔧 Debug Scripts Created

1. **debug_spotify_continuity.js** - Comprehensive data analysis script
2. **query_spotify_data.js** - Basic data querying (already exists)

## Next Steps

1. **Run authentication setup** to enable Firebase data access
2. **Execute diagnostic scripts** to confirm current data state
3. **Locate missing function source code** and restore to repository
4. **Implement monitoring and alerting** for future prevention
5. **Add manual sync capabilities** for user control

---

*This investigation provides a comprehensive analysis of the Spotify sync issue and a clear path forward to resolve it permanently.*