# Firebase Firestore Indexes Required

This document lists the required Firestore composite indexes for the RunMusic app.

## Required Indexes

### 1. spotifyListeningHistory Collection

**Query Pattern**: Used in `SpotifyBackgroundSync.swift:350-355` for retrieving tracks within a time range for a specific user.

**Required Index**:
- Collection: `spotifyListeningHistory`
- Fields:
  - `userId` (Ascending)
  - `playedAt` (Ascending)

**Query Example**:
```swift
db.collection("spotifyListeningHistory")
  .whereField("userId", isEqualTo: userId)
  .whereField("playedAt", isGreaterThanOrEqualTo: Timestamp(date: startTime))
  .whereField("playedAt", isLessThanOrEqualTo: Timestamp(date: endTime))
  .order(by: "playedAt", descending: false)
```

## How to Create These Indexes

### Option 1: Using Firebase Console (Recommended)
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to Firestore Database
4. Click on "Indexes" tab
5. Click "Create Index"
6. Set up the index as specified above

### Option 2: Using Firebase CLI
Create a `firestore.indexes.json` file in your project root:

```json
{
  "indexes": [
    {
      "collectionGroup": "spotifyListeningHistory",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "userId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "playedAt",
          "order": "ASCENDING"
        }
      ]
    }
  ]
}
```

Then deploy with:
```bash
firebase deploy --only firestore:indexes
```

### Option 3: Automatic Index Creation (Development)
When running the app in development, Firebase will suggest creating missing indexes. Look for error messages in the logs that include links to automatically create the required indexes.

## Verification

After creating the index, you should see:
1. No more "index required" errors in the logs
2. The query `getTracksForTimeRange` in `SpotifyBackgroundSync.swift` should work correctly
3. Spotify tracks should be retrieved from Firebase for run matching

## Impact

Without this index, the following functionality will not work:
- Background Spotify sync storing tracks to Firebase
- Retrieving historical Spotify tracks for runs beyond the 50 most recent
- Cross-device sync of listening history

## Status

- [ ] Index created in Firebase Console
- [ ] Index deployed and active
- [ ] Functionality verified in app