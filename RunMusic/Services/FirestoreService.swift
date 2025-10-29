import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

import CryptoKit

class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - User Profiles
    
    // MARK: - Username Management
    
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        // Check if username exists in usernames collection
        let document = try await db.collection("usernames").document(username.lowercased()).getDocument()
        return !document.exists
    }
    
    func reserveUsername(_ username: String, for userId: String) async throws -> Bool {
        let usernameDoc = db.collection("usernames").document(username.lowercased())
        
        // Use a transaction to ensure atomicity
        let result = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let document: DocumentSnapshot
            do {
                document = try transaction.getDocument(usernameDoc)
            } catch {
                // Set error if errorPointer is provided
                if let errorPointer = errorPointer {
                    errorPointer.pointee = error as NSError
                }
                return false
            }
            
            // Check if username is already taken
            if document.exists {
                return false
            }
            
            // Reserve the username
            transaction.setData([
                "userID": userId,
                "createdAt": FieldValue.serverTimestamp(),
                "reserved": true
            ], forDocument: usernameDoc)
            
            return true
        }
        
        return result as? Bool ?? false
    }
    
    func confirmUsernameReservation(_ username: String, for userId: String) async throws {
        // Remove the reserved flag, making it permanent
        try await db.collection("usernames").document(username.lowercased()).updateData([
            "reserved": false,
            "confirmedAt": FieldValue.serverTimestamp()
        ])
    }
    
    func releaseUsernameReservation(_ username: String) async throws {
        // Delete the reserved username if user cancels
        try await db.collection("usernames").document(username.lowercased()).delete()
    }
    
    func validateUsername(_ username: String) -> (isValid: Bool, error: String?) {
        // Username validation rules
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Length check
        guard trimmed.count >= 3 else {
            return (false, "Username must be at least 3 characters")
        }
        
        guard trimmed.count <= 20 else {
            return (false, "Username must be 20 characters or less")
        }
        
        // Character validation - alphanumeric and underscore only
        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        guard predicate.evaluate(with: trimmed) else {
            return (false, "Username can only contain letters, numbers, and underscores")
        }
        
        // Reserved usernames
        let reserved = ["admin", "runmusic", "runthetunes", "api", "support", "help", "null", "undefined", "root", "user", "test"]
        guard !reserved.contains(trimmed.lowercased()) else {
            return (false, "This username is not available")
        }
        
        return (true, nil)
    }
    
    func userProfileExists(userId: String) async throws -> Bool {
        let document = try await db.collection("users").document(userId).getDocument()
        return document.exists
    }
    
    func checkForExistingAccount(stravaUserId: String) async throws -> Bool {
        // Query users collection for any user with this Strava ID
        let querySnapshot = try await db.collection("users")
            .whereField("stravaUserId", isEqualTo: stravaUserId)
            .getDocuments()
        
        return !querySnapshot.documents.isEmpty
    }
    
    func createUserProfile(_ profile: UserProfile) async throws {
        let data = try Firestore.Encoder().encode(profile)
        try await db.collection("users").document(profile.id).setData(data)
    }
    
    func getUserProfile(userId: String) async throws -> UserProfile? {
        let document = try await db.collection("users").document(userId).getDocument()
        guard document.exists else { return nil }
        return try document.data(as: UserProfile.self)
    }
    
    func updateUserProfile(_ profile: UserProfile) async throws {
        let data = try Firestore.Encoder().encode(profile)
        try await db.collection("users").document(profile.id).setData(data, merge: true)
    }
    
    func updateLastActive(userId: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "lastActiveAt": Timestamp(date: Date())
        ])
    }
    
    // MARK: - Run Customizations
    
    func saveRunCustomization(userId: String, runId: String, customization: RunCustomization) async throws {
        let data = try Firestore.Encoder().encode(customization)
        try await db.collection("users").document(userId)
            .collection("runs").document(runId)
            .setData(data, merge: true)
    }
    
    func getRunCustomization(userId: String, runId: String) async throws -> RunCustomization? {
        let document = try await db.collection("users").document(userId)
            .collection("runs").document(runId).getDocument()
        
        guard document.exists else { return nil }
        return try document.data(as: RunCustomization.self)
    }
    
    func getAllRunCustomizations(userId: String) async throws -> [String: RunCustomization] {
        let querySnapshot = try await db.collection("users").document(userId)
            .collection("runs").getDocuments()
        
        var customizations: [String: RunCustomization] = [:]
        
        for document in querySnapshot.documents {
            if let customization = try? document.data(as: RunCustomization.self) {
                customizations[document.documentID] = customization
            }
        }
        
        return customizations
    }
    
    // MARK: - Secure Token Storage
    
    func storeEncryptedToken(userId: String, service: String, token: EncryptedToken) async throws {
        let data = try Firestore.Encoder().encode(token)
        try await db.collection("users").document(userId)
            .collection("tokens").document(service)
            .setData(data)
    }
    
    func getEncryptedToken(userId: String, service: String) async throws -> EncryptedToken? {
        let document = try await db.collection("users").document(userId)
            .collection("tokens").document(service).getDocument()
        
        guard document.exists else { return nil }
        return try document.data(as: EncryptedToken.self)
    }
    
    func deleteToken(userId: String, service: String) async throws {
        try await db.collection("users").document(userId)
            .collection("tokens").document(service).delete()
    }
    
    func clearUserTokens(userId: String, service: String) async throws {
        print("🗑️ Clearing \(service) tokens for user: \(userId)")
        try await deleteToken(userId: userId, service: service)
        print("✅ Successfully cleared \(service) tokens from Firebase")
    }
    
    // MARK: - Imported Spotify Tracks
    
    func storeImportedSpotifyTracks(userId: String, tracks: [SpotifyTrack]) async throws {
        print("☁️ UNIFIED: Starting storage of \(tracks.count) tracks for user \(userId) using global collection")
        print("☁️ Using path: spotifyListeningHistory/ (same as Cloud Functions)")
        
        let batchSize = 400 // Stay under Firebase's 500 operation limit
        var storedCount = 0
        var batchNumber = 1
        
        // Process tracks in batches to avoid "transaction too big" error
        for chunk in tracks.chunked(into: batchSize) {
            print("☁️ Processing batch \(batchNumber) with \(chunk.count) tracks...")
            let batch = db.batch()
            
            for track in chunk {
                // Use same ID format as Cloud Functions for consistency
                let docId = "\(userId)_\(track.playedAt.timeIntervalSince1970)_\(track.id)"
                let docRef = db.collection("spotifyListeningHistory").document(docId)
                
                // Store in format matching SpotifyListeningHistory model (same as Cloud Functions)
                let trackData: [String: Any] = [
                    "id": docId,
                    "userId": userId,
                    "trackId": track.id,
                    "trackName": track.name,
                    "artistName": track.artist,
                    "albumName": track.album ?? "",
                    "playedAt": Timestamp(date: track.playedAt),
                    "durationMs": track.durationMs,
                    "albumArtURL": track.albumImageURL ?? "",
                    "previewURL": "",
                    "spotifyURL": "",
                    "syncedAt": Timestamp(date: Date()),
                    "source": "app_import" // Tag to distinguish from cloud function sync
                ]
                
                batch.setData(trackData, forDocument: docRef, merge: false)
                storedCount += 1
            }
            
            try await batch.commit()
            print("✅ Stored batch \(batchNumber) of \(chunk.count) tracks (\(storedCount)/\(tracks.count) total)")
            batchNumber += 1
        }
        
        print("✅ UNIFIED: Successfully stored \(storedCount) tracks in global collection (compatible with Cloud Functions)")
    }
    
    // MARK: - Debug Methods
    
    func debugFirebaseConnection() async {
        print("🔍 DEBUG: Testing unified Firebase collection...")
        
        do {
            // Test 1: Try to read users collection (we know this works)
            let usersSnapshot = try await db.collection("users").limit(to: 1).getDocuments()
            print("✅ DEBUG: Users collection accessible - \(usersSnapshot.documents.count) documents")
            
            // Test 2: Check unified spotifyListeningHistory collection
            let tracksSnapshot = try await db.collection("spotifyListeningHistory").limit(to: 5).getDocuments()
            print("✅ DEBUG: spotifyListeningHistory collection exists - \(tracksSnapshot.documents.count) documents (sample)")
            
            // Test 3: Check if we can access the users collection structure
            guard let currentUser = Auth.auth().currentUser else {
                print("❌ DEBUG: No authenticated user")
                return
            }
            let userDocRef = db.collection("users").document(currentUser.uid)
            let userDoc = try await userDocRef.getDocument()
            print("✅ DEBUG: User document exists: \(userDoc.exists), data keys: \(userDoc.data()?.keys.joined(separator: ", ") ?? "none")")
            
            // Test 4: Check unified collection for this user
            let userTracksQuery = db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: currentUser.uid)
                .limit(to: 1)
            let userTracksSnapshot = try await userTracksQuery.getDocuments()
            print("✅ DEBUG: User tracks in unified collection: \(userTracksSnapshot.documents.count) found")
            
        } catch {
            print("❌ DEBUG: Firebase connection test failed: \(error)")
        }
    }
    
    func getImportedSpotifyTracks(userId: String) async throws -> [SpotifyTrack] {
        print("☁️ UNIFIED: Fetching imported tracks for user \(userId) from global collection")
        
        let snapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .order(by: "playedAt", descending: false)
            .getDocuments()
        
        let tracks = snapshot.documents.compactMap { document -> SpotifyTrack? in
            let data = document.data()
            
            guard let trackId = data["trackId"] as? String,
                  let trackName = data["trackName"] as? String,
                  let artistName = data["artistName"] as? String,
                  let playedAtTimestamp = data["playedAt"] as? Timestamp else {
                // Only log occasional invalid documents to avoid spam
                if Int.random(in: 1...100) == 1 {
                    print("❌ Invalid track data found (1 of ~100 shown) - document ID: \(document.documentID)")
                }
                return nil
            }
            
            return SpotifyTrack(
                id: trackId,
                name: trackName,
                artist: artistName,
                album: data["albumName"] as? String,
                playedAt: playedAtTimestamp.dateValue(),
                durationMs: data["durationMs"] as? Int ?? 0,
                albumImageURL: data["albumArtURL"] as? String
            )
        }
        
        print("☁️ UNIFIED: Retrieved \(tracks.count) imported tracks from global collection")
        return tracks
    }
    
    // MARK: - Optimized Date-Range Queries
    
    func getImportedSpotifyTracksForDateRange(userId: String, startDate: Date, endDate: Date) async throws -> [SpotifyTrack] {
        // PERFORMANCE OPTIMIZATION: Minimal logging and direct query approach
        
        // Simple, efficient query with date range filter
        let snapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("playedAt", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("playedAt", isLessThanOrEqualTo: Timestamp(date: endDate))
            .order(by: "playedAt", descending: false)
            .getDocuments()
        
        var validTracks: [SpotifyTrack] = []
        var invalidCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let trackId = data["trackId"] as? String,
                  let trackName = data["trackName"] as? String,
                  let artistName = data["artistName"] as? String,
                  let playedAtTimestamp = data["playedAt"] as? Timestamp else {
                invalidCount += 1
                continue // Skip invalid records silently
            }
            
            let track = SpotifyTrack(
                id: trackId,
                name: trackName,
                artist: artistName,
                album: data["albumName"] as? String,
                playedAt: playedAtTimestamp.dateValue(),
                durationMs: data["durationMs"] as? Int ?? 0,
                albumImageURL: data["albumArtURL"] as? String
            )
            validTracks.append(track)
        }
        
        // Only log summary if there are issues
        if invalidCount > 0 {
            print("⚠️ FIRESTORE: Skipped \(invalidCount) invalid tracks out of \(snapshot.documents.count) total")
        }
        
        print("☁️ Retrieved \(validTracks.count) valid tracks for date range")
        return validTracks
    }
    
    // MARK: - Legacy restoration function (call once on first app launch)
    func performLegacyRestorationIfNeeded(userId: String) async throws {
        // Check if restoration already happened
        let restoreMarkerCheck = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("source", isEqualTo: "legacy_restore")
            .limit(to: 1)
            .getDocuments()
        
        if !restoreMarkerCheck.documents.isEmpty {
            return // Already restored
        }
        
        // Check total tracks in unified collection
        let totalCountQuery = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .count
            .getAggregation(source: .server)
        let totalCount = Int(totalCountQuery.count)
        
        // Only restore if unified collection is suspiciously small
        if totalCount < 50 {
            let legacyCheck = try await db.collection("users").document(userId)
                .collection("importedSpotifyTracks")
                .limit(to: 5)
                .getDocuments()
            
            if legacyCheck.documents.count > 0 {
                print("🚀 AUTO-RESTORE: Starting legacy tracks restoration...")
                try await self.restoreLegacyTracksToUnifiedCollection(userId: userId)
                print("✅ AUTO-RESTORE: Successfully restored legacy tracks")
            }
        }
    }
    
    // MARK: - Original function with all debug info (for manual troubleshooting)
    func getImportedSpotifyTracksForDateRangeWithDebug(userId: String, startDate: Date, endDate: Date) async throws -> [SpotifyTrack] {
        print("☁️ UNIFIED: Fetching tracks for date range: \(startDate) to \(endDate) from global collection")
        
        // Get actual total count for this user
        let totalCountQuery = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .count
            .getAggregation(source: .server)
        let totalCount = Int(totalCountQuery.count)
        print("📊 DEBUG: User has \(totalCount) TOTAL tracks in unified collection")
        
        // Get date range of existing tracks
        if totalCount > 0 {
            let oldestTrack = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .order(by: "playedAt", descending: false)
                .limit(to: 1)
                .getDocuments()
            
            let newestTrack = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .order(by: "playedAt", descending: true)
                .limit(to: 1)
                .getDocuments()
                
            if let oldest = oldestTrack.documents.first?.data()["playedAt"] as? Timestamp,
               let newest = newestTrack.documents.first?.data()["playedAt"] as? Timestamp {
                print("📅 DEBUG: Track date range: \(oldest.dateValue()) to \(newest.dateValue())")
            }
        }
        
        let snapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("playedAt", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("playedAt", isLessThanOrEqualTo: Timestamp(date: endDate))
            .order(by: "playedAt", descending: false)
            .getDocuments()
        
        let tracks = snapshot.documents.compactMap { document -> SpotifyTrack? in
            let data = document.data()
            
            guard let trackId = data["trackId"] as? String,
                  let trackName = data["trackName"] as? String,
                  let artistName = data["artistName"] as? String,
                  let playedAtTimestamp = data["playedAt"] as? Timestamp else {
                // Only log occasional invalid documents to avoid spam
                if Int.random(in: 1...100) == 1 {
                    print("❌ Invalid track data found (1 of ~100 shown) - document ID: \(document.documentID)")
                }
                return nil
            }
            
            return SpotifyTrack(
                id: trackId,
                name: trackName,
                artist: artistName,
                album: data["albumName"] as? String,
                playedAt: playedAtTimestamp.dateValue(),
                durationMs: data["durationMs"] as? Int ?? 0,
                albumImageURL: data["albumArtURL"] as? String
            )
        }
        
        print("☁️ UNIFIED: Retrieved \(tracks.count) tracks for date range from global collection")
        print("🔍 DEBUG: Requested date range: \(startDate) to \(endDate)")
        print("🔍 DEBUG: Query returned \(snapshot.documents.count) documents")
        return tracks
    }
    
    // REMOVED: Legacy function - no longer needed with unified collection architecture
    
    func updateImportedSpotifyTracks(userId: String, tracks: [SpotifyTrack]) async throws {
        // CRITICAL: Do NOT clear existing tracks - only update/add new ones
        // Previous implementation was deleting all historical data!
        print("☁️ UNIFIED: Updating imported tracks for user \(userId) in global collection - preserving existing data")
        
        let batch = db.batch()
        var updateCount = 0
        
        for track in tracks {
            // Use same ID format as Cloud Functions for consistency
            let docId = "\(userId)_\(track.playedAt.timeIntervalSince1970)_\(track.id)"
            let docRef = db.collection("spotifyListeningHistory").document(docId)
            
            // Store in format matching SpotifyListeningHistory model (same as Cloud Functions)
            let trackData: [String: Any] = [
                "id": docId,
                "userId": userId,
                "trackId": track.id,
                "trackName": track.name,
                "artistName": track.artist,
                "albumName": track.album ?? "",
                "playedAt": Timestamp(date: track.playedAt),
                "durationMs": track.durationMs,
                "albumArtURL": track.albumImageURL ?? "",
                "previewURL": "",
                "spotifyURL": "",
                "syncedAt": Timestamp(date: Date()),
                "source": "app_update" // Tag to distinguish from cloud function sync
            ]
            
            batch.setData(trackData, forDocument: docRef, merge: true)
            updateCount += 1
        }
        
        try await batch.commit()
        print("☁️ UNIFIED: Updated \(updateCount) tracks in global collection (preserved existing tracks)")
    }
    
    // MARK: - Data Recovery & Migration Functions
    
    func restoreLegacyTracksToUnifiedCollection(userId: String) async throws {
        print("🚀 RESTORE: Starting restoration of legacy tracks to unified collection for user \(userId)")
        
        // Step 1: Check what's currently in unified collection
        let unifiedSnapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        print("📊 RESTORE: Current unified collection has \(unifiedSnapshot.documents.count) tracks")
        
        // Step 2: Get all tracks from legacy subcollection
        print("📥 RESTORE: Fetching legacy tracks from subcollection...")
        let legacySnapshot = try await db.collection("users").document(userId)
            .collection("importedSpotifyTracks")
            .getDocuments()
        
        print("📊 RESTORE: Found \(legacySnapshot.documents.count) legacy tracks to restore")
        
        if legacySnapshot.documents.isEmpty {
            print("⚠️ RESTORE: No legacy tracks found - nothing to restore")
            return
        }
        
        // Step 3: Convert and batch write to unified collection
        let batchSize = 400 // Stay under Firebase's 500 operation limit
        var restoredCount = 0
        var batchNumber = 1
        
        let legacyTracks = legacySnapshot.documents.compactMap { document -> [String: Any]? in
            let data = document.data()
            
            guard let trackId = data["id"] as? String,
                  let trackName = data["name"] as? String,
                  let artistName = data["artist"] as? String,
                  let playedAtTimestamp = data["playedAt"] as? Timestamp else {
                print("❌ RESTORE: Invalid legacy track data in document \(document.documentID)")
                return nil
            }
            
            // Convert legacy format to unified format
            let docId = "\(userId)_\(playedAtTimestamp.dateValue().timeIntervalSince1970)_\(trackId)"
            
            // Check if this track already exists in unified collection
            let existingTrack = unifiedSnapshot.documents.first { $0.documentID == docId }
            if existingTrack != nil {
                print("⏭️ RESTORE: Track already exists in unified collection: \(docId)")
                return nil // Skip duplicates
            }
            
            return [
                "docId": docId,
                "data": [
                    "id": docId,
                    "userId": userId,
                    "trackId": trackId,
                    "trackName": trackName,
                    "artistName": artistName,
                    "albumName": data["album"] as? String ?? "",
                    "playedAt": playedAtTimestamp,
                    "durationMs": data["durationMs"] as? Int ?? 0,
                    "albumArtURL": data["albumImageURL"] as? String ?? "",
                    "previewURL": "",
                    "spotifyURL": "",
                    "syncedAt": Timestamp(date: Date()),
                    "source": "legacy_restore"
                ]
            ]
        }
        
        print("📊 RESTORE: After deduplication, \(legacyTracks.count) tracks need to be restored")
        
        // Process tracks in batches
        for chunk in legacyTracks.chunked(into: batchSize) {
            print("🔄 RESTORE: Processing batch \(batchNumber) with \(chunk.count) tracks...")
            let batch = db.batch()
            
            for trackInfo in chunk {
                guard let docId = trackInfo["docId"] as? String,
                      let trackData = trackInfo["data"] as? [String: Any] else {
                    continue
                }
                
                let docRef = db.collection("spotifyListeningHistory").document(docId)
                batch.setData(trackData, forDocument: docRef, merge: false)
                restoredCount += 1
            }
            
            try await batch.commit()
            print("✅ RESTORE: Restored batch \(batchNumber) (\(restoredCount)/\(legacyTracks.count) total)")
            batchNumber += 1
        }
        
        print("🎉 RESTORE: Successfully restored \(restoredCount) tracks to unified collection")
        print("📋 RESTORE: Legacy tracks remain in subcollection for safety")
    }
    
    func validateRestoredData(userId: String) async throws -> (legacy: Int, unified: Int, restored: Int) {
        print("🔍 VALIDATION: Checking restoration results...")
        
        // Count legacy tracks
        let legacySnapshot = try await db.collection("users").document(userId)
            .collection("importedSpotifyTracks")
            .getDocuments()
        
        // Count unified tracks
        let unifiedSnapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        // Count restored tracks specifically
        let restoredSnapshot = try await db.collection("spotifyListeningHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("source", isEqualTo: "legacy_restore")
            .getDocuments()
        
        let counts = (
            legacy: legacySnapshot.documents.count,
            unified: unifiedSnapshot.documents.count,
            restored: restoredSnapshot.documents.count
        )
        
        print("📊 VALIDATION RESULTS:")
        print("   Legacy collection: \(counts.legacy) tracks")
        print("   Unified collection: \(counts.unified) tracks")
        print("   Restored tracks: \(counts.restored) tracks")
        
        return counts
    }
    
    func cleanupLegacySpotifyData(userId: String) async throws {
        print("🗑️ CLEANUP: Starting cleanup of legacy Spotify subcollection for user \(userId)")
        
        let legacySnapshot = try await db.collection("users").document(userId)
            .collection("importedSpotifyTracks")
            .getDocuments()
        
        if legacySnapshot.documents.isEmpty {
            print("✅ CLEANUP: No legacy tracks found to clean up")
            return
        }
        
        print("🗑️ CLEANUP: Found \(legacySnapshot.documents.count) legacy documents to delete")
        
        // Delete in batches
        let batchSize = 400
        var deletedCount = 0
        
        for chunk in legacySnapshot.documents.chunked(into: batchSize) {
            let batch = db.batch()
            
            for document in chunk {
                batch.deleteDocument(document.reference)
                deletedCount += 1
            }
            
            try await batch.commit()
            print("🗑️ CLEANUP: Deleted \(deletedCount)/\(legacySnapshot.documents.count) legacy documents")
        }
        
        print("✅ CLEANUP: Successfully deleted \(deletedCount) legacy documents from subcollection")
    }
    
    // MARK: - Run Data Caching
    
    func storeCachedRun(userId: String, run: CachedRunData) async throws {
        let data = try Firestore.Encoder().encode(run)
        try await db.collection("users").document(userId)
            .collection("cachedRuns").document(run.id)
            .setData(data)
    }
    
    func getCachedRun(userId: String, runId: String) async throws -> CachedRunData? {
        let document = try await db.collection("users").document(userId)
            .collection("cachedRuns").document(runId).getDocument()
        
        guard document.exists else { return nil }
        return try document.data(as: CachedRunData.self)
    }
    
    func getCachedRunsModifiedSince(userId: String, since: Date) async throws -> [CachedRunData] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("cachedRuns")
            .whereField("lastModified", isGreaterThan: Timestamp(date: since))
            .order(by: "date", descending: true)
            .getDocuments()
        
        return try snapshot.documents.map { document in
            try document.data(as: CachedRunData.self)
        }
    }
    
    func getAllCachedRuns(userId: String, limit: Int = 50) async throws -> [CachedRunData] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("cachedRuns")
            .order(by: "date", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return try snapshot.documents.map { document in
            try document.data(as: CachedRunData.self)
        }
    }
    
    func deleteCachedRun(userId: String, runId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("cachedRuns").document(runId).delete()
    }
    
    func getCacheStatus(userId: String) async throws -> RunCacheStatus {
        let snapshot = try await db.collection("users").document(userId)
            .collection("cachedRuns")
            .getDocuments()
        
        let runs = try snapshot.documents.map { document in
            try document.data(as: CachedRunData.self)
        }
        
        let lastCacheUpdate = runs.map(\.lastModified).max()
        let oldestRun = runs.map(\.date).min()
        let newestRun = runs.map(\.date).max()
        
        return RunCacheStatus(
            totalCachedRuns: runs.count,
            lastCacheUpdate: lastCacheUpdate,
            dateRange: oldestRun != nil && newestRun != nil ? (oldestRun!, newestRun!) : nil
        )
    }
}

// MARK: - Data Models

struct UserProfile: Codable {
    let id: String
    let email: String
    let displayName: String
    let photoURL: String?
    let createdAt: Date
    var lastActiveAt: Date
    var preferences: FirebaseUserPreferences
    var stravaUserId: String?
    var username: String?
}

struct FirebaseUserPreferences: Codable {
    var unitSystem: String
    var preferredExportFormat: String
    var autoSaveEnabled: Bool
    var notificationsEnabled: Bool
    
    init() {
        self.unitSystem = "metric"
        self.preferredExportFormat = "instagram"
        self.autoSaveEnabled = true
        self.notificationsEnabled = true
    }
}

struct RunCustomization: Codable {
    var colorScheme: String?
    var showCity: Bool?
    var showSongs: Bool?
    var visibleSongs: [String]?
    var photoSettings: PhotoSettings?
    var portraitSettings: LayoutSettings?
    // Landscape settings removed - portrait only now
    var updatedAt: Date
    
    init() {
        self.updatedAt = Date()
    }
}

struct PhotoSettings: Codable {
    var backgroundPhotoPath: String?
    var opacity: Double?
    var brightness: Double?
    var filterType: String?
}

struct LayoutSettings: Codable {
    var colorScheme: String?
    var showCity: Bool?
    var showSongs: Bool?
    var visibleSongs: [String]?
    var photoSettings: PhotoSettings?
}

struct EncryptedToken: Codable {
    let encryptedData: String
    let iv: String
    let tag: String
    let createdAt: Date
    var expiresAt: Date?
    
    init(encryptedData: String, iv: String, tag: String, expiresAt: Date? = nil) {
        self.encryptedData = encryptedData
        self.iv = iv
        self.tag = tag
        self.createdAt = Date()
        self.expiresAt = expiresAt
    }
}

// MARK: - Run Caching Models

struct CachedRunData: Codable {
    let id: String
    let name: String
    let date: Date
    let distance: Double // in meters
    let elapsedTime: TimeInterval // in seconds
    let averagePace: Double // in seconds per kilometer
    let startLocation: CachedLocationData?
    let endLocation: CachedLocationData?
    let routeCoordinates: [CachedLocationData]
    let city: String?
    let neighborhood: String?
    let locationAnalysis: RunLocationAnalysis? // Added for smart location display
    let spotifyTracks: [SpotifyTrack]? // Added for Spotify track persistence
    let powerSong: SpotifyTrack? // Added for Power Song persistence
    let powerSongAveragePace: Double? // Added for Power Song pace persistence
    let weatherData: WeatherData? // Added for weather persistence
    let lastModified: Date
    let cacheVersion: Int // For future compatibility
    
    init(from runActivity: RunActivity) {
        self.id = runActivity.id
        self.name = runActivity.name
        self.date = runActivity.date
        self.distance = runActivity.distance
        self.elapsedTime = runActivity.elapsedTime
        self.averagePace = runActivity.averagePace
        self.startLocation = runActivity.startLocation.map(CachedLocationData.init)
        self.endLocation = runActivity.endLocation.map(CachedLocationData.init)
        self.routeCoordinates = runActivity.routeCoordinates.map(CachedLocationData.init)
        self.city = runActivity.city
        self.neighborhood = runActivity.neighborhood
        self.locationAnalysis = runActivity.locationAnalysis
        self.spotifyTracks = runActivity.spotifyTracks
        self.powerSong = runActivity.powerSong
        self.powerSongAveragePace = runActivity.powerSongAveragePace
        self.weatherData = runActivity.weatherData
        self.lastModified = Date()
        self.cacheVersion = 4 // Incremented for weather data
    }
    
    func toRunActivity() -> RunActivity {
        var runActivity = RunActivity(
            id: id,
            name: name,
            date: date,
            distance: distance,
            elapsedTime: elapsedTime,
            averagePace: averagePace,
            startLocation: startLocation?.toLocationData(),
            endLocation: endLocation?.toLocationData(),
            routeCoordinates: routeCoordinates.map { $0.toLocationData() },
            city: city,
            neighborhood: neighborhood,
            locationAnalysis: locationAnalysis,
            spotifyTracks: spotifyTracks,
            powerSong: powerSong,
            powerSongAveragePace: powerSongAveragePace
        )
        runActivity.weatherData = weatherData
        return runActivity
    }
}

struct CachedLocationData: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?
    
    init(from locationData: LocationData) {
        self.latitude = locationData.latitude
        self.longitude = locationData.longitude
        self.timestamp = locationData.timestamp
    }
    
    func toLocationData() -> LocationData {
        return LocationData(latitude: latitude, longitude: longitude, timestamp: timestamp)
    }
}

struct RunCacheStatus {
    let totalCachedRuns: Int
    let lastCacheUpdate: Date?
    let dateRange: (Date, Date)?
    
    var displayText: String {
        if totalCachedRuns == 0 {
            return "no cached runs"
        }
        
        let runText = totalCachedRuns == 1 ? "run" : "runs"
        if let dateRange = dateRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return "\(totalCachedRuns) cached \(runText) (\(formatter.string(from: dateRange.0)) - \(formatter.string(from: dateRange.1)))"
        } else {
            return "\(totalCachedRuns) cached \(runText)"
        }
    }
}

extension FirestoreService {
    // MARK: - Album Art Caching
    
    func cacheAlbumArt(cacheKey: String, imageData: Data) async throws {
        let docRef = db.collection("albumArtCache").document(cacheKey)
        
        let data: [String: Any] = [
            "imageData": imageData,
            "cachedAt": Timestamp(date: Date()),
            "size": imageData.count
        ]
        
        try await docRef.setData(data)
        print("🎨 FIREBASE: Cached album art '\(cacheKey)' (\(imageData.count) bytes)")
    }
    
    func getCachedAlbumArt(cacheKey: String) async throws -> Data? {
        let docRef = db.collection("albumArtCache").document(cacheKey)
        
        let document = try await docRef.getDocument()
        
        guard document.exists,
              let data = document.data(),
              let imageData = data["imageData"] as? Data else {
            return nil
        }
        
        // Check if cache is not too old (30 days)
        if let cachedAt = data["cachedAt"] as? Timestamp {
            let cacheAge = Date().timeIntervalSince(cachedAt.dateValue())
            let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
            
            if cacheAge > maxAge {
                // Cache is too old, delete it
                try await docRef.delete()
                print("🎨 FIREBASE: Deleted expired cache for '\(cacheKey)'")
                return nil
            }
        }
        
        print("🎨 FIREBASE: Retrieved cached album art '\(cacheKey)' (\(imageData.count) bytes)")
        return imageData
    }
}

// MARK: - Token Storage (using types from TokenEncryption.swift)