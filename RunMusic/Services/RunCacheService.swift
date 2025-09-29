import Foundation
import FirebaseAuth

/// Service responsible for caching Strava run data to reduce API calls and improve performance
class RunCacheService {
    static let shared = RunCacheService()
    
    private let firestoreService = FirestoreService.shared
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Attempt to get runs from cache first, falling back to Strava API if needed
    func getCachedRunsOrFetch(
        stravaService: StravaService,
        page: Int = 1,
        perPage: Int = 20,
        maxCacheAge: TimeInterval = 24 * 60 * 60 // 24 hours
    ) async throws -> [RunActivity] {
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🏃 RunCacheService: No authenticated user, fetching from Strava API")
            return try await fetchFromStravaAndCache(stravaService: stravaService, page: page, perPage: perPage)
        }
        
        print("🏃 RunCacheService: Checking cache for user \(userId)")
        
        do {
            // Check cache status
            let cacheStatus = try await firestoreService.getCacheStatus(userId: userId)
            print("🏃 RunCacheService: Cache status - \(cacheStatus.displayText)")
            
            // If cache is empty or too old, fetch from API
            let cacheAge = cacheStatus.lastCacheUpdate?.timeIntervalSinceNow ?? -Double.infinity
            let isCacheValid = abs(cacheAge) < maxCacheAge && cacheStatus.totalCachedRuns > 0
            
            if !isCacheValid {
                print("🏃 RunCacheService: Cache invalid or too old (age: \(abs(cacheAge))s), fetching from Strava API")
                return try await fetchFromStravaAndCache(stravaService: stravaService, page: page, perPage: perPage)
            }
            
            // Return cached runs
            print("🏃 RunCacheService: Returning cached runs")
            let cachedRuns = try await firestoreService.getAllCachedRuns(userId: userId, limit: perPage)
            let runActivities = cachedRuns.map { $0.toRunActivity() }
            
            // Return cached runs with all saved metadata (Spotify tracks, power song, route, weather)
            return runActivities
            
        } catch {
            print("🏃 RunCacheService: Cache access failed (\(error)), falling back to Strava API")
            return try await fetchFromStravaAndCache(stravaService: stravaService, page: page, perPage: perPage)
        }
    }
    
    /// Get a specific cached run by ID
    func getCachedRun(runId: String) async throws -> RunActivity? {
        guard let userId = Auth.auth().currentUser?.uid else {
            return nil
        }
        
        let cachedRun = try await firestoreService.getCachedRun(userId: userId, runId: runId)
        return cachedRun?.toRunActivity()
    }
    
    /// Cache a single run
    func cacheRun(_ runActivity: RunActivity) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🏃 RunCacheService: No authenticated user, skipping cache")
            return
        }
        
        do {
            let cachedRun = CachedRunData(from: runActivity)
            try await firestoreService.storeCachedRun(userId: userId, run: cachedRun)
            print("🏃 RunCacheService: Successfully cached run \(runActivity.id)")
        } catch {
            print("🏃 RunCacheService: Failed to cache run \(runActivity.id): \(error)")
        }
    }
    
    /// Cache multiple runs
    func cacheRuns(_ runActivities: [RunActivity]) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🏃 RunCacheService: No authenticated user, skipping cache")
            return
        }
        
        print("🏃 RunCacheService: Caching \(runActivities.count) runs")
        
        for runActivity in runActivities {
            await cacheRun(runActivity)
        }
        
        print("🏃 RunCacheService: Finished caching \(runActivities.count) runs")
    }
    
    /// Update a cached run with enriched data (Spotify tracks, power song, etc.)
    /// This is called after progressive loading adds metadata to ensure cache stays current
    func updateCachedRun(_ runActivity: RunActivity) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🏃 RunCacheService: No authenticated user, skipping cache update")
            return
        }
        
        do {
            let enrichedCachedRun = CachedRunData(from: runActivity)
            try await firestoreService.storeCachedRun(userId: userId, run: enrichedCachedRun)
            print("🏃 RunCacheService: ✅ Updated cached run \(runActivity.id) with enriched data")
            
            // Log what was cached for debugging
            let spotifyCount = runActivity.spotifyTracks?.count ?? 0
            let hasPowerSong = runActivity.powerSong != nil
            let hasRoute = !runActivity.routeCoordinates.isEmpty
            print("🏃 RunCacheService: Cached metadata - Songs: \(spotifyCount), Power Song: \(hasPowerSong), Route: \(hasRoute)")
        } catch {
            print("🏃 RunCacheService: ❌ Failed to update cached run \(runActivity.id): \(error)")
        }
    }
    
    /// Clear all cached runs for current user
    func clearCache() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🏃 RunCacheService: No authenticated user, nothing to clear")
            return
        }
        
        do {
            let cachedRuns = try await firestoreService.getAllCachedRuns(userId: userId, limit: 1000)
            
            for cachedRun in cachedRuns {
                try await firestoreService.deleteCachedRun(userId: userId, runId: cachedRun.id)
            }
            
            print("🏃 RunCacheService: Cleared \(cachedRuns.count) cached runs")
        } catch {
            print("🏃 RunCacheService: Failed to clear cache: \(error)")
        }
    }
    
    /// Get cache status for display
    func getCacheStatus() async -> RunCacheStatus? {
        guard let userId = Auth.auth().currentUser?.uid else {
            return nil
        }
        
        do {
            return try await firestoreService.getCacheStatus(userId: userId)
        } catch {
            print("🏃 RunCacheService: Failed to get cache status: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchFromStravaAndCache(
        stravaService: StravaService,
        page: Int,
        perPage: Int
    ) async throws -> [RunActivity] {
        
        // Fetch from Strava API
        let stravaActivities = try await stravaService.fetchActivities(page: page, perPage: perPage)
        let runOnlyActivities = stravaActivities.filter { $0.type == "Run" }
        
        // Convert to RunActivity objects (without Spotify data for caching)
        var runActivities: [RunActivity] = []
        
        for activity in runOnlyActivities {
            do {
                let detailedActivity = try await stravaService.fetchDetailedActivity(id: activity.id)
                let streams = try? await stravaService.fetchActivityStreams(id: activity.id, types: ["latlng", "time", "velocity_smooth"])
                let runActivity = await DataConversionService.shared.convertStravaActivityToRunActivity(
                    activity,
                    detailedActivity: detailedActivity,
                    streams: streams
                )
                runActivities.append(runActivity)
                print("🏃 RunCacheService: ✅ Processed activity \(activity.id) with route: \(!runActivity.routeCoordinates.isEmpty)")
            } catch {
                print("🏃 RunCacheService: Failed to process activity \(activity.id): \(error)")
                // Continue with other activities
            }
        }
        
        // Cache the runs in the background
        Task {
            await cacheRuns(runActivities)
        }
        
        return runActivities
    }
}

// MARK: - Cache Configuration

extension RunCacheService {
    /// Configuration for cache behavior
    struct CacheConfig {
        static let defaultMaxAge: TimeInterval = 24 * 60 * 60 // 24 hours
        static let aggressiveMaxAge: TimeInterval = 60 * 60 // 1 hour for frequent users
        static let conservativeMaxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days for occasional users
    }
}