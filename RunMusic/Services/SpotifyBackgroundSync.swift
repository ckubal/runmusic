import Foundation
import FirebaseFirestore
import BackgroundTasks

// MARK: - Background Sync Models

struct SpotifyListeningHistory: Codable {
    let id: String
    let userId: String
    let trackId: String?
    let trackName: String
    let artistName: String
    let albumName: String?
    let playedAt: Date
    let durationMs: Int?
    let albumArtURL: String?
    let previewURL: String?
    let spotifyURL: String?
    let syncedAt: Date
    
    init(from spotifyTrack: SpotifyTrack, userId: String) {
        self.id = "\(userId)_\(spotifyTrack.playedAt.timeIntervalSince1970)_\(spotifyTrack.id)"
        self.userId = userId
        self.trackId = spotifyTrack.id
        self.trackName = spotifyTrack.name
        self.artistName = spotifyTrack.artist
        self.albumName = spotifyTrack.album
        self.playedAt = spotifyTrack.playedAt
        self.durationMs = spotifyTrack.durationMs
        self.albumArtURL = spotifyTrack.albumImageURL
        self.previewURL = nil // Not available in simplified model
        self.spotifyURL = nil // Not available in simplified model
        self.syncedAt = Date()
    }
    
    func toSpotifyTrack() -> SpotifyTrack {
        // Convert to simplified model format
        
        return SpotifyTrack(
            id: trackId ?? UUID().uuidString,
            name: trackName,
            artist: artistName,
            album: albumName,
            playedAt: playedAt,
            durationMs: durationMs ?? 0,
            albumImageURL: albumArtURL
        )
    }
}

struct UserSyncSettings: Codable {
    let userId: String
    let isBackgroundSyncEnabled: Bool
    let syncFrequencyMinutes: Int
    let lastSyncAt: Date?
    let totalTracksCollected: Int
    let syncErrors: [String] // Recent error messages
    let createdAt: Date
    let updatedAt: Date
    
    static let defaultSyncFrequency = 15 // 15 minutes
}

enum BackgroundSyncStatus: Equatable {
    case idle
    case syncing
    case completed(tracksAdded: Int)
    case failed(error: Error)
    case rateLimited(retryAfter: Date)
    case disabled
    
    static func == (lhs: BackgroundSyncStatus, rhs: BackgroundSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.disabled, .disabled):
            return true
        case let (.completed(lhsTracks), .completed(rhsTracks)):
            return lhsTracks == rhsTracks
        case let (.failed(lhsError), .failed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case let (.rateLimited(lhsDate), .rateLimited(rhsDate)):
            return lhsDate == rhsDate
        default:
            return false
        }
    }
}

// MARK: - Background Sync Service

@MainActor
class SpotifyBackgroundSync: ObservableObject {
    static let shared = SpotifyBackgroundSync()
    
    @Published var syncStatus: BackgroundSyncStatus = .idle
    @Published var syncSettings: UserSyncSettings?
    @Published var totalHistoricalTracks: Int = 0
    
    private let db = Firestore.firestore()
    private let spotifyService = SpotifyService.shared
    private let firebaseAuth = FirebaseAuthService.shared
    
    // Background task identifier
    private let backgroundTaskIdentifier = "com.runmusic.spotify-sync"
    
    private init() {
        registerBackgroundTask()
        loadUserSyncSettings()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 Background sync task registered successfully")
            print("🔍 BACKGROUND SYNC DEBUG: Task scheduled for: \(request.earliestBeginDate!)")
            print("🔍 BACKGROUND SYNC DEBUG: Task identifier: \(backgroundTaskIdentifier)")
        } catch {
            print("❌ Failed to register background task: \(error)")
            print("🔍 BACKGROUND SYNC DEBUG: Error type: \(type(of: error))")
            print("🔍 BACKGROUND SYNC DEBUG: Error details: \(error.localizedDescription)")
        }
    }
    
    func handleBackgroundAppRefresh(task: BGAppRefreshTask) {
        print("🔄 Background app refresh triggered")
        
        // Schedule the next background task
        registerBackgroundTask()
        
        // Perform sync if conditions are met
        Task {
            await performBackgroundSync()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Sync Settings Management
    
    func loadUserSyncSettings() {
        guard let userId = firebaseAuth.currentUser?.uid else {
            print("⚠️ No authenticated user for sync settings")
            return
        }
        
        db.collection("userSyncSettings").document(userId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Failed to load sync settings: \(error)")
                return
            }
            
            if let document = document, document.exists {
                do {
                    let settings = try document.data(as: UserSyncSettings.self)
                    Task { @MainActor in
                        self?.syncSettings = settings
                    }
                } catch {
                    print("❌ Failed to decode sync settings: \(error)")
                }
            } else {
                // Create default settings
                Task {
                    await self?.createDefaultSyncSettings(for: userId)
                }
            }
        }
    }
    
    private func createDefaultSyncSettings(for userId: String) async {
        let defaultSettings = UserSyncSettings(
            userId: userId,
            isBackgroundSyncEnabled: true,
            syncFrequencyMinutes: UserSyncSettings.defaultSyncFrequency,
            lastSyncAt: nil,
            totalTracksCollected: 0,
            syncErrors: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        do {
            try db.collection("userSyncSettings").document(userId).setData(from: defaultSettings)
            self.syncSettings = defaultSettings
            print("✅ Created default sync settings for user: \(userId)")
        } catch {
            print("❌ Failed to create default sync settings: \(error)")
        }
    }
    
    func updateSyncSettings(_ settings: UserSyncSettings) async {
        do {
            try db.collection("userSyncSettings").document(settings.userId).setData(from: settings)
            self.syncSettings = settings
            print("✅ Updated sync settings for user: \(settings.userId)")
        } catch {
            print("❌ Failed to update sync settings: \(error)")
        }
    }
    
    func toggleBackgroundSync(enabled: Bool) async {
        guard var settings = syncSettings else { return }
        
        settings = UserSyncSettings(
            userId: settings.userId,
            isBackgroundSyncEnabled: enabled,
            syncFrequencyMinutes: settings.syncFrequencyMinutes,
            lastSyncAt: settings.lastSyncAt,
            totalTracksCollected: settings.totalTracksCollected,
            syncErrors: settings.syncErrors,
            createdAt: settings.createdAt,
            updatedAt: Date()
        )
        
        await updateSyncSettings(settings)
        
        if enabled {
            registerBackgroundTask()
        }
    }
    
    // MARK: - Automatic Sync Management
    
    /// Automatically enables background sync when Spotify connects (called from SpotifyService)
    func enableBackgroundSyncAutomatically() async {
        guard let userId = firebaseAuth.currentUser?.uid else {
            print("⚠️ Cannot auto-enable sync: No authenticated Firebase user")
            return
        }
        
        print("🔄 Auto-enabling background sync for user: \(userId)")
        
        // Create or update sync settings to enabled
        let enabledSettings = UserSyncSettings(
            userId: userId,
            isBackgroundSyncEnabled: true,
            syncFrequencyMinutes: UserSyncSettings.defaultSyncFrequency,
            lastSyncAt: nil,
            totalTracksCollected: 0,
            syncErrors: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await updateSyncSettings(enabledSettings)
        registerBackgroundTask()
        
        print("✅ Background sync automatically enabled for Spotify connection")
    }
    
    /// Automatically disables background sync when Spotify disconnects (called from SpotifyService)
    func disableBackgroundSyncAutomatically() async {
        guard var settings = syncSettings else {
            print("⚠️ No sync settings to disable")
            return
        }
        
        print("🔄 Auto-disabling background sync for Spotify disconnection")
        
        settings = UserSyncSettings(
            userId: settings.userId,
            isBackgroundSyncEnabled: false,
            syncFrequencyMinutes: settings.syncFrequencyMinutes,
            lastSyncAt: settings.lastSyncAt,
            totalTracksCollected: settings.totalTracksCollected,
            syncErrors: settings.syncErrors,
            createdAt: settings.createdAt,
            updatedAt: Date()
        )
        
        await updateSyncSettings(settings)
        
        print("✅ Background sync automatically disabled for Spotify disconnection")
    }
    
    // MARK: - Background Sync Logic
    
    func performBackgroundSync() async {
        guard let settings = syncSettings,
              settings.isBackgroundSyncEnabled,
              firebaseAuth.isAuthenticated else {
            syncStatus = .disabled
            print("⚠️ Background sync disabled or Firebase not authenticated")
            return
        }
        
        // CRITICAL FIX: Sync tokens from Firebase first (background execution may not have loaded them)
        print("🔄 Background sync: Loading Spotify tokens from Firebase...")
        await spotifyService.syncWithFirebase()
        
        // CRITICAL FIX: Refresh Spotify token before checking authentication
        guard await spotifyService.refreshTokenIfNeeded(),
              spotifyService.isAuthenticated else {
            syncStatus = .disabled
            print("⚠️ Background sync: Spotify not authenticated or token refresh failed")
            return
        }
        
        // Check if it's time to sync based on frequency
        if let lastSync = settings.lastSyncAt {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            let requiredInterval = TimeInterval(settings.syncFrequencyMinutes * 60)
            
            if timeSinceLastSync < requiredInterval {
                print("⏰ Too soon to sync. Last sync: \(lastSync), frequency: \(settings.syncFrequencyMinutes)m")
                return
            }
        }
        
        await performActualSync(settings: settings)
    }
    
    private func performActualSync(settings: UserSyncSettings) async {
        syncStatus = .syncing
        print("🔄 Starting Spotify sync...")
        
        do {
            // Get the latest track date from our history to avoid duplicates
            let latestTrackDate = await getLatestTrackDate(for: settings.userId)
            let startTime = latestTrackDate ?? Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
            let endTime = Date()
            
            print("🔄 Fetching Spotify tracks from \(startTime) to \(endTime)")
            
            // Fetch recent tracks from Spotify
            let recentTracks = try await spotifyService.fetchRecentlyPlayed(
                startTime: startTime,
                endTime: endTime
            )
            
            print("🔍 SYNC DEBUG: Fetched \(recentTracks.count) recent tracks from Spotify")
            if !recentTracks.isEmpty {
                print("🔍 SYNC DEBUG: First track: \(recentTracks.first!.name) at \(recentTracks.first!.playedAt)")
                print("🔍 SYNC DEBUG: Last track: \(recentTracks.last!.name) at \(recentTracks.last!.playedAt)")
            }
            
            // Store new tracks in Firestore
            let newTracksCount = await storeSpotifyTracks(recentTracks, for: settings.userId)
            print("🔍 SYNC DEBUG: Stored \(newTracksCount) new tracks to Firebase")
            
            // Update sync settings
            let updatedSettings = UserSyncSettings(
                userId: settings.userId,
                isBackgroundSyncEnabled: settings.isBackgroundSyncEnabled,
                syncFrequencyMinutes: settings.syncFrequencyMinutes,
                lastSyncAt: Date(),
                totalTracksCollected: settings.totalTracksCollected + newTracksCount,
                syncErrors: [], // Clear errors on successful sync
                createdAt: settings.createdAt,
                updatedAt: Date()
            )
            
            await updateSyncSettings(updatedSettings)
            await updateTotalTracksCount()
            
            syncStatus = .completed(tracksAdded: newTracksCount)
            print("✅ Sync completed: \(newTracksCount) new tracks added")
            
        } catch {
            syncStatus = .failed(error: error)
            print("❌ Sync failed: \(error)")
            
            // Update settings with error
            var errorMessages = settings.syncErrors
            errorMessages.append(error.localizedDescription)
            if errorMessages.count > 5 {
                errorMessages = Array(errorMessages.suffix(5)) // Keep last 5 errors
            }
            
            let updatedSettings = UserSyncSettings(
                userId: settings.userId,
                isBackgroundSyncEnabled: settings.isBackgroundSyncEnabled,
                syncFrequencyMinutes: settings.syncFrequencyMinutes,
                lastSyncAt: settings.lastSyncAt,
                totalTracksCollected: settings.totalTracksCollected,
                syncErrors: errorMessages,
                createdAt: settings.createdAt,
                updatedAt: Date()
            )
            
            await updateSyncSettings(updatedSettings)
        }
    }
    
    // MARK: - Manual Sync for Testing
    
    /// Manually trigger a sync for testing (ignores frequency limits)
    func performManualSync() async {
        print("🔧 Manual sync triggered for testing...")
        print("🔍 MANUAL SYNC DEBUG: Firebase user: \(firebaseAuth.currentUser?.uid ?? "nil")")
        print("🔍 MANUAL SYNC DEBUG: Spotify authenticated (before sync): \(spotifyService.isAuthenticated)")
        print("🔍 MANUAL SYNC DEBUG: Sync settings exist: \(syncSettings != nil)")
        
        guard let settings = syncSettings,
              settings.isBackgroundSyncEnabled,
              firebaseAuth.isAuthenticated else {
            syncStatus = .disabled
            print("⚠️ Manual sync: disabled or Firebase not authenticated")
            print("🔍 MANUAL SYNC DEBUG: settings exists: \(syncSettings != nil)")
            print("🔍 MANUAL SYNC DEBUG: settings enabled: \(syncSettings?.isBackgroundSyncEnabled ?? false)")
            print("🔍 MANUAL SYNC DEBUG: Firebase auth: \(firebaseAuth.isAuthenticated)")
            
            // Try to create settings if missing
            if syncSettings == nil, let userId = firebaseAuth.currentUser?.uid {
                print("🔍 MANUAL SYNC DEBUG: Creating default sync settings...")
                await createDefaultSyncSettings(for: userId)
            }
            return
        }
        
        // Force sync regardless of frequency
        syncStatus = .syncing
        print("🔄 Starting manual Spotify sync...")
        
        // CRITICAL: Sync tokens from Firebase first
        print("🔄 Manual sync: Loading Spotify tokens from Firebase...")
        await spotifyService.syncWithFirebase()
        
        // Check authentication after Firebase sync
        guard await spotifyService.refreshTokenIfNeeded(),
              spotifyService.isAuthenticated else {
            syncStatus = .failed(error: NSError(domain: "SpotifyBackgroundSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Spotify not authenticated"]))
            print("⚠️ Manual sync: Spotify not authenticated after Firebase sync")
            return
        }
        
        await performActualSync(settings: settings)
    }
    
    // MARK: - Firestore Operations
    
    func storeTrackFromAPI(_ track: SpotifyTrack) async {
        guard let userId = firebaseAuth.currentUser?.uid else { return }
        await storeSpotifyTracks([track], for: userId)
    }
    
    private func storeSpotifyTracks(_ tracks: [SpotifyTrack], for userId: String) async -> Int {
        guard !tracks.isEmpty else { return 0 }
        
        let batch = db.batch()
        var newTracksCount = 0
        
        for track in tracks {
            let historyTrack = SpotifyListeningHistory(from: track, userId: userId)
            let docRef = db.collection("spotifyListeningHistory").document(historyTrack.id)
            
            do {
                try batch.setData(from: historyTrack, forDocument: docRef, merge: false)
                newTracksCount += 1
            } catch {
                print("❌ Failed to prepare track for batch: \(error)")
            }
        }
        
        do {
            try await batch.commit()
            print("📦 Successfully stored \(newTracksCount) tracks in Firestore")
            return newTracksCount
        } catch {
            print("❌ Failed to commit tracks batch: \(error)")
            return 0
        }
    }
    
    func getTracksForTimeRange(startTime: Date, endTime: Date) async -> [SpotifyTrack] {
        guard let userId = firebaseAuth.currentUser?.uid else {
            print("⚠️ No authenticated user for track query")
            return []
        }
        
        print("🔍 Querying tracks for time range: \(startTime) to \(endTime)")
        
        var allTracks: [SpotifyTrack] = []
        
        do {
            // Query background sync tracks from spotifyListeningHistory
            let backgroundSnapshot = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            let backgroundTracks = backgroundSnapshot.documents.compactMap { document -> SpotifyTrack? in
                do {
                    let historyTrack = try document.data(as: SpotifyListeningHistory.self)
                    
                    // Filter by time range in memory to avoid index requirement
                    if historyTrack.playedAt >= startTime && historyTrack.playedAt <= endTime {
                        return historyTrack.toSpotifyTrack()
                    }
                    return nil
                } catch {
                    print("❌ Failed to decode background sync track: \(error)")
                    return nil
                }
            }
            
            print("📦 Found \(backgroundTracks.count) background sync tracks in time range")
            allTracks.append(contentsOf: backgroundTracks)
            
            // All tracks (including legacy imported) are now in unified spotifyListeningHistory collection
            print("📦 Using unified collection - all data queried in single collection above")
            
            // Sort all tracks by played time and remove duplicates
            let sortedTracks = allTracks.sorted { $0.playedAt < $1.playedAt }
            let uniqueTracks = removeDuplicateTracks(sortedTracks)
            
            print("📦 Total unique tracks retrieved: \(uniqueTracks.count) (all from unified collection)")
            return uniqueTracks
            
        } catch {
            print("❌ Failed to query tracks: \(error)")
            return []
        }
    }
    
    // Helper method to remove duplicate tracks based on name, artist, and played time
    private func removeDuplicateTracks(_ tracks: [SpotifyTrack]) -> [SpotifyTrack] {
        var uniqueTracks: [SpotifyTrack] = []
        var seen = Set<String>()
        
        for track in tracks {
            let key = "\(track.name)_\(track.artist)_\(track.playedAt.timeIntervalSince1970)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueTracks.append(track)
            }
        }
        
        return uniqueTracks
    }
    
    private func getLatestTrackDate(for userId: String) async -> Date? {
        do {
            let snapshot = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .order(by: "playedAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            
            if let document = snapshot.documents.first {
                let historyTrack = try document.data(as: SpotifyListeningHistory.self)
                return historyTrack.playedAt
            }
            
            return nil
        } catch {
            print("❌ Failed to get latest track date: \(error)")
            return nil
        }
    }
    
    private func updateTotalTracksCount() async {
        guard let userId = firebaseAuth.currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .count
                .getAggregation(source: .server)
            
            self.totalHistoricalTracks = Int(truncating: snapshot.count)
        } catch {
            print("❌ Failed to get total tracks count: \(error)")
        }
    }
    
    // MARK: - Comprehensive Track Statistics
    
    struct ComprehensiveTrackStats {
        let totalTracks: Int
        let backgroundSyncTracks: Int
        let importedTracks: Int
        let earliestDate: Date?
        
        var formattedTotalTracks: String {
            return totalTracks.formatted()
        }
        
        var formattedEarliestDate: String {
            guard let earliestDate = earliestDate else { return "No tracks" }
            
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            return "since \(formatter.string(from: earliestDate))"
        }
        
        var displayText: String {
            guard totalTracks > 0 else { return "No tracks available" }
            
            if earliestDate != nil {
                return "\(formattedTotalTracks) tracks \(formattedEarliestDate)"
            } else {
                return "\(formattedTotalTracks) tracks imported"
            }
        }
    }
    
    func getComprehensiveTrackStats() async -> ComprehensiveTrackStats {
        guard let userId = firebaseAuth.currentUser?.uid else {
            return ComprehensiveTrackStats(totalTracks: 0, backgroundSyncTracks: 0, importedTracks: 0, earliestDate: nil)
        }
        
        do {
            // Get background sync tracks count and earliest date
            let backgroundSnapshot = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .order(by: "playedAt", descending: false)
                .getDocuments()
            
            let backgroundSyncTracks = backgroundSnapshot.documents.count
            let earliestBackgroundDate = backgroundSnapshot.documents.first?.data()["playedAt"] as? Date
            
            // All tracks (including legacy imported) are now in unified collection
            // The backgroundSnapshot already contains all tracks, so total = background tracks
            let totalTracks = backgroundSyncTracks
            let earliestDate = earliestBackgroundDate
            
            print("📊 Comprehensive track stats: \(totalTracks) total (all in unified collection)")
            if let earliest = earliestDate {
                print("📊 Earliest track date: \(earliest)")
            }
            
            return ComprehensiveTrackStats(
                totalTracks: totalTracks,
                backgroundSyncTracks: backgroundSyncTracks,
                importedTracks: 0, // All tracks now in unified collection
                earliestDate: earliestDate
            )
            
        } catch {
            print("❌ Failed to get comprehensive track stats: \(error)")
            return ComprehensiveTrackStats(totalTracks: 0, backgroundSyncTracks: 0, importedTracks: 0, earliestDate: nil)
        }
    }
    
    // MARK: - Data Management
    
    func clearAllHistoricalData() async {
        guard let userId = firebaseAuth.currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("spotifyListeningHistory")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            await updateTotalTracksCount()
            
            // Reset sync settings
            if var settings = syncSettings {
                settings = UserSyncSettings(
                    userId: settings.userId,
                    isBackgroundSyncEnabled: settings.isBackgroundSyncEnabled,
                    syncFrequencyMinutes: settings.syncFrequencyMinutes,
                    lastSyncAt: nil,
                    totalTracksCollected: 0,
                    syncErrors: [],
                    createdAt: settings.createdAt,
                    updatedAt: Date()
                )
                await updateSyncSettings(settings)
            }
            
            print("🗑️ Cleared all historical listening data")
            
        } catch {
            print("❌ Failed to clear historical data: \(error)")
        }
    }
}

// MARK: - SpotifyService Extension for Background Sync

extension SpotifyService {
    @MainActor
    func hasHistoricalTracks() -> Bool {
        return SpotifyBackgroundSync.shared.totalHistoricalTracks > 0
    }
    
    func fetchHistoricalTracksForTimeRange(startTime: Date, endTime: Date) async -> [SpotifyTrack] {
        // First try to get from Firebase historical data
        let historicalTracks = await SpotifyBackgroundSync.shared.getTracksForTimeRange(
            startTime: startTime,
            endTime: endTime
        )
        
        if !historicalTracks.isEmpty {
            print("📦 Using \(historicalTracks.count) historical tracks from Firebase")
            return historicalTracks
        }
        
        // Fallback to imported tracks if no historical data
        if hasImportedTracks() {
            print("📥 Falling back to imported tracks")
            return await fetchImportedTracksForTimeRange(startTime: startTime, endTime: endTime)
        }
        
        // Final fallback to API
        do {
            print("🌐 Falling back to Spotify API")
            return try await fetchRecentlyPlayed(startTime: startTime, endTime: endTime)
        } catch {
            print("❌ All track sources failed: \(error)")
            return []
        }
    }
}