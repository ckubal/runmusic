import Foundation
import SwiftUI
import FirebaseAuth

class SpotifyService: ObservableObject {
    static let shared = SpotifyService()
    
    private let clientID = "c38b1724640d4af6b13aec892cf01a2c"
    private let clientSecret = "2e15a2c6cff24158baf48a68ba769fa4"
    private let redirectURI = "runthetunes://spotify-auth"
    
    @Published var isAuthenticated = false {
        didSet {
            print("🔐 SPOTIFY AUTH STATE CHANGE: \(oldValue) → \(isAuthenticated)")
            if let trace = Thread.callStackSymbols.first {
                print("🔐   Called from: \(trace)")
            }
        }
    }
    @Published var accessToken: String?
    @Published var userProfile: SpotifyUserProfile?
    
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private let firebaseAuth = FirebaseAuthService.shared
    
    private init() {
        loadStoredCredentials()
        
        // DEBUG: Log initial auth state
        print("🔐 SPOTIFY INIT: isAuthenticated = \(isAuthenticated)")
        print("🔐 SPOTIFY INIT: accessToken = \(accessToken != nil ? "EXISTS" : "NIL")")
        print("🔐 SPOTIFY INIT: tokenExpiresAt = \(tokenExpiresAt?.description ?? "NIL")")
    }
    
    // DEBUG: Force clear all authentication state
    public func debugClearAllAuth() {
        print("🔧 DEBUG: Force clearing all Spotify authentication state")
        
        // Clear all properties
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userProfile = nil
        isAuthenticated = false
        
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "spotify_access_token")
        UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
        UserDefaults.standard.removeObject(forKey: "spotify_expires_at")
        UserDefaults.standard.synchronize()
        
        print("✅ DEBUG: All Spotify auth state cleared")
    }
    
    var authURL: URL? {
        // Use web OAuth for reliability
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-recently-played user-read-playback-state user-read-currently-playing user-top-read streaming"),
            URLQueryItem(name: "show_dialog", value: "true"),
            URLQueryItem(name: "state", value: UUID().uuidString) // Add state for security
        ]
        print("🎵 SpotifyService: Generated auth URL: \(components?.url?.absoluteString ?? "nil")")
        return components?.url
    }
    
    private func canOpenSpotifyApp() -> Bool {
        guard let spotifyURL = URL(string: "spotify://") else { return false }
        return UIApplication.shared.canOpenURL(spotifyURL)
    }
    
    private func spotifyAppAuthURL() -> URL? {
        var components = URLComponents(string: "spotify://authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-recently-played user-read-playback-state user-read-currently-playing user-top-read streaming"),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        return components?.url
    }
    
    
    func handleAuthCallback(url: URL) async {
        print("🎵 SpotifyService: Handling auth callback with URL: \(url)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("❌ SpotifyService: Failed to extract code from callback URL")
            return
        }
        
        print("✅ SpotifyService: Got auth code, exchanging for token")
        await exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let credentials = "\(clientID):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // DEBUG: Log the raw response
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 SPOTIFY AUTH DEBUG: Response status: \(httpResponse.statusCode)")
            }
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 SPOTIFY AUTH DEBUG: Raw response: \(responseString)")
            }
            
            let authResponse = try JSONDecoder().decode(SpotifyAuthResponse.self, from: data)
            
            // DEBUG: Log what we received
            print("🔍 SPOTIFY AUTH DEBUG: Got access token: \(authResponse.accessToken.prefix(10))...")
            print("🔍 SPOTIFY AUTH DEBUG: Got refresh token: \(authResponse.refreshToken != nil ? "YES" : "NO")")
            print("🔍 SPOTIFY AUTH DEBUG: Token expires in: \(authResponse.expiresIn) seconds")
            
            await MainActor.run {
                self.accessToken = authResponse.accessToken
                self.refreshToken = authResponse.refreshToken
                self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
                self.isAuthenticated = true
                print("🔐 SPOTIFY: Setting isAuthenticated = true after successful token exchange")
                self.storeCredentials(authResponse)
                self.fetchUserProfile()
            }
            print("🎵 SpotifyService: Successfully authenticated!")
            
            // Store to Firebase in background (don't block UI updates)
            Task.detached(priority: .background) {
                await self.storeTokensToFirebase(
                    accessToken: authResponse.accessToken,
                    refreshToken: authResponse.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
                )
                print("✅ SpotifyService: Tokens stored to Firebase for cross-device sync")
                
                // AUTO-ENABLE background sync when Spotify connects
                print("🔄 SpotifyService: Auto-enabling background sync for connected Spotify account...")
                await SpotifyBackgroundSync.shared.enableBackgroundSyncAutomatically()
            }
        } catch {
            print("❌ SpotifyService: Failed to exchange code for token: \(error.localizedDescription)")
        }
    }
    
    func fetchRecentlyPlayed(startTime: Date, endTime: Date) async throws -> [SpotifyTrack] {
        print("🎵 SpotifyService: Fetching recently played tracks")
        print("🎵 Time range: \(startTime) to \(endTime)")
        
        // Try to refresh token if needed
        guard await refreshTokenIfNeeded() else {
            print("❌ SpotifyService: No access token available after refresh attempt")
            throw SpotifyError.notAuthenticated
        }
        
        guard let accessToken = accessToken else {
            print("❌ SpotifyService: No access token available")
            throw SpotifyError.notAuthenticated
        }
        
        let startTimestamp = Int(startTime.timeIntervalSince1970 * 1000)
        let endTimestamp = Int(endTime.timeIntervalSince1970 * 1000)
        
        print("🎵 Timestamp range: \(startTimestamp) to \(endTimestamp)")
        print("🎵 Time range: \(startTime) to \(endTime)")
        
        // Check if the time range is recent enough - Spotify only keeps ~50 recent tracks
        let now = Date()
        let daysSinceRun = now.timeIntervalSince(endTime) / (24 * 60 * 60)
        print("🎵 Days since run ended: \(daysSinceRun)")
        
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")
        
        // Note: Spotify API doesn't support 'before' parameter, only 'after'
        // We'll fetch tracks after the start time and filter client-side
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "after", value: "\(startTimestamp)")
        ]
        
        guard let url = components?.url else {
            print("❌ SpotifyService: Invalid URL for recently played")
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🌐 SpotifyService: Making request to: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ SpotifyService: Invalid response type")
            throw SpotifyError.requestFailed
        }
        
        print("📡 SpotifyService: Received response with status code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            print("❌ SpotifyService: HTTP error \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Response body: \(responseString)")
            }
            throw SpotifyError.requestFailed
        }
        
        print("✅ SpotifyService: Successfully received recently played data (\(data.count) bytes)")
        
        do {
            let recentlyPlayedResponse = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
            print("✅ SpotifyService: Successfully decoded \(recentlyPlayedResponse.items.count) tracks")
            
            let tracks = recentlyPlayedResponse.items.map { item in
                DataConversionService.shared.convertSpotifyTrackToSpotifyTrack(item)
            }
            
            // Log album art status for tracks
            let tracksWithoutArt = tracks.filter { $0.albumImageURL == nil }
            print("🎵 Found \(tracks.count) Spotify tracks")
            if !tracksWithoutArt.isEmpty {
                print("⚠️ \(tracksWithoutArt.count)/\(tracks.count) tracks missing album art")
            } else {
                print("✅ All tracks have album art")
            }
            
            // Check if any tracks are missing album art and enrich if needed
            let tracksNeedingEnrichment = tracks.filter { $0.albumImageURL == nil }
            if !tracksNeedingEnrichment.isEmpty {
                print("⚠️ Found \(tracksNeedingEnrichment.count) recent tracks without album art - attempting enrichment...")
                let enrichedTracks = await enrichRecentTracksWithAlbumArt(tracks)
                // CRITICAL: Sort chronologically (oldest first) for correct listening sequence
                return enrichedTracks.sorted { $0.playedAt < $1.playedAt }
            }
            
            // CRITICAL: Sort chronologically (oldest first) for correct listening sequence
            // Spotify API returns newest first, but we need oldest first for listening order
            return tracks.sorted { $0.playedAt < $1.playedAt }
        } catch {
            print("❌ SpotifyService: Failed to decode recently played: \(error)")
            throw SpotifyError.decodingError
        }
    }
    
    func fetchRecentTracks(limit: Int = 5) async throws -> [SpotifyTrack] {
        print("🎵 SpotifyService: Fetching \(limit) most recent tracks (no time filter)")
        
        // Try to refresh token if needed
        guard await refreshTokenIfNeeded() else {
            print("❌ SpotifyService: No access token available after refresh attempt")
            throw SpotifyError.notAuthenticated
        }
        
        guard let accessToken = accessToken else {
            print("❌ SpotifyService: No access token available")
            throw SpotifyError.notAuthenticated
        }
        
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = components?.url else {
            print("❌ SpotifyService: Invalid URL for recent tracks")
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🌐 SpotifyService: Making request to: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ SpotifyService: Invalid response type")
            throw SpotifyError.requestFailed
        }
        
        print("📡 SpotifyService: Received response with status code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            print("❌ SpotifyService: HTTP error \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Response body: \(responseString)")
            }
            throw SpotifyError.requestFailed
        }
        
        print("✅ SpotifyService: Successfully received recent tracks data (\(data.count) bytes)")
        
        do {
            let recentlyPlayedResponse = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
            print("✅ SpotifyService: Successfully decoded \(recentlyPlayedResponse.items.count) tracks")
            
            let tracks = recentlyPlayedResponse.items.map { item in
                DataConversionService.shared.convertSpotifyTrackToSpotifyTrack(item)
            }
            
            // Log tracks with missing album art
            let tracksWithoutArt = tracks.filter { $0.albumImageURL == nil }
            if !tracksWithoutArt.isEmpty {
                print("⚠️ \(tracksWithoutArt.count)/\(tracks.count) recent tracks missing album art")
            } else {
                print("✅ All \(tracks.count) recent tracks have album art")
            }
            
            // Check if any tracks are missing album art and enrich if needed
            let tracksNeedingEnrichment = tracks.filter { $0.albumImageURL == nil }
            if !tracksNeedingEnrichment.isEmpty {
                print("⚠️ Found \(tracksNeedingEnrichment.count) recent tracks without album art - attempting enrichment...")
                let enrichedTracks = await enrichRecentTracksWithAlbumArt(tracks)
                // CRITICAL: Sort chronologically (oldest first) for correct listening sequence
                return enrichedTracks.sorted { $0.playedAt < $1.playedAt }
            }
            
            // CRITICAL: Sort chronologically (oldest first) for correct listening sequence  
            // Spotify API returns newest first, but we need oldest first for listening order
            return tracks.sorted { $0.playedAt < $1.playedAt }
        } catch {
            print("❌ SpotifyService: Failed to decode recent tracks: \(error)")
            throw SpotifyError.decodingError
        }
    }
    
    // Experimental: Try to get more historical data using different approaches
    func fetchExtendedHistory(targetDate: Date) async throws -> [SpotifyTrack] {
        print("🎵 SpotifyService: Attempting to fetch extended history for \(targetDate)")
        
        guard let accessToken = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        // Approach 1: Try recently played with maximum historical range
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "after", value: "\(Int(threeDaysAgo.timeIntervalSince1970 * 1000))")
        ]
        
        guard let url = components?.url else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🌐 SpotifyService: Trying extended history request: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ Extended history request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }
        
        do {
            let recentlyPlayedResponse = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
            let tracks = recentlyPlayedResponse.items.map { item in
                DataConversionService.shared.convertSpotifyTrackToSpotifyTrack(item)
            }
            
            print("✅ Extended history found \(tracks.count) tracks")
            return tracks
        } catch {
            print("❌ Failed to decode extended history: \(error)")
            return []
        }
    }
    
    // MARK: - Alternative Historical Data Methods (Stats.fm approach)
    
    func fetchTopTracks(timeRange: String = "medium_term") async throws -> [SpotifyTrack] {
        print("🎵 SpotifyService: Fetching top tracks (\(timeRange)) for historical context")
        
        guard let accessToken = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        var components = URLComponents(string: "https://api.spotify.com/v1/me/top/tracks")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "time_range", value: timeRange) // short_term, medium_term, long_term
        ]
        
        guard let url = components?.url else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ Top tracks request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw SpotifyError.requestFailed
        }
        
        print("✅ Top tracks data received (\(data.count) bytes)")
        
        do {
            let response = try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data)
            let tracks = response.items.map { item in
                SpotifyTrack(
                    id: item.id,
                    name: item.name,
                    artist: item.artists.first?.name ?? "Unknown Artist",
                    album: item.album?.name,
                    playedAt: Date(), // Default to current date for top tracks
                    durationMs: item.durationMs,
                    albumImageURL: item.album?.images.first?.url
                )
            }
            
            print("🎵 Parsed \(tracks.count) top tracks")
            return tracks
        } catch {
            print("❌ Failed to parse top tracks: \(error)")
            return []
        }
    }
    
    func fetchCurrentlyPlaying() async throws -> SpotifyTrack? {
        print("🎵 SpotifyService: Fetching currently playing track")
        
        guard let accessToken = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.requestFailed
        }
        
        if httpResponse.statusCode == 204 {
            print("🎵 No track currently playing")
            return nil
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ Currently playing request failed with status: \(httpResponse.statusCode)")
            throw SpotifyError.requestFailed
        }
        
        print("✅ Currently playing data received (\(data.count) bytes)")
        
        do {
            let response = try JSONDecoder().decode(SpotifyCurrentlyPlayingResponse.self, from: data)
            
            guard let item = response.item else {
                print("🎵 No track currently playing")
                return nil
            }
            
            let track = SpotifyTrack(
                id: item.id,
                name: item.name,
                artist: item.artists.first?.name ?? "Unknown Artist",
                album: item.album?.name,
                playedAt: Date(), // Current time since it's playing now
                durationMs: item.durationMs,
                albumImageURL: item.album?.images.first?.url
            )
            
            print("🎵 Currently playing: '\(track.name)' by \(track.artist)")
            
            // Store for historical data
            storeTrackForHistoricalData(track)
            
            return track
        } catch {
            print("❌ Failed to parse currently playing: \(error)")
            return nil
        }
    }
    
    // MARK: - Real-time Tracking for Building Historical Data
    
    func startRealtimeTracking() {
        print("🎵 Starting real-time Spotify tracking for historical data...")
        
        // This approach builds historical data going forward
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task {
                do {
                    if let currentTrack = try await self.fetchCurrentlyPlaying() {
                        // Store this track with current timestamp in local database
                        self.storeTrackForHistoricalData(currentTrack)
                    }
                } catch {
                    print("❌ Error in real-time tracking: \(error)")
                }
            }
        }
    }
    
    private func storeTrackForHistoricalData(_ track: SpotifyTrack) {
        // Store track in Firebase for historical data
        Task {
            await SpotifyBackgroundSync.shared.storeTrackFromAPI(track)
        }
        print("💾 Storing track for historical data: \(track.name)")
    }
    
    // MARK: - Extended Streaming History Import (Stats.fm approach)
    
    func importExtendedStreamingHistory(from fileData: Data) async throws -> [SpotifyTrack] {
        print("📥 SpotifyService: Importing extended streaming history from JSON file")
        print("📥 File size: \(fileData.count) bytes")
        
        // Debug: Show raw JSON structure for first few characters
        if let jsonString = String(data: fileData.prefix(500), encoding: .utf8) {
            print("🔍 Raw JSON sample (first 500 chars):")
            print(jsonString)
        }
        
        do {
            let decoder = JSONDecoder()
            
            // Spotify extended history uses ISO8601 format with timezone
            decoder.dateDecodingStrategy = .iso8601
            
            print("🔍 Attempting to decode JSON...")
            
            let streamingHistory = try decoder.decode([SpotifyExtendedStreamingHistoryItem].self, from: fileData)
            print("✅ Successfully parsed \(streamingHistory.count) streaming history items")
            
            // Debug: Show first few items to understand structure
            if streamingHistory.count > 0 {
                print("🔍 Sample items from import:")
                for (index, item) in streamingHistory.prefix(3).enumerated() {
                    print("  Item \(index):")
                    print("    ts: \(item.ts?.description ?? "nil")")
                    print("    msPlayed: \(item.msPlayed ?? -1)")
                    print("    trackName: \(item.masterMetadataTrackName ?? "nil")")
                    print("    artistName: \(item.masterMetadataAlbumArtistName ?? "nil")")
                    print("    albumName: \(item.masterMetadataAlbumAlbumName ?? "nil")")
                    print("    spotifyTrackUri: \(item.spotifyTrackUri ?? "nil")")
                    print("    skipped: \(item.skipped ?? false)")
                }
            }
            
            var filteredOutCount = 0
            _ = 0 // skippedCount placeholder
            var shortPlayCount = 0
            var missingDataCount = 0
            
            let tracks = streamingHistory.compactMap { item -> SpotifyTrack? in
                // Skip non-music items (podcasts, audiobooks)
                if item.spotifyTrackUri == nil || item.masterMetadataTrackName == nil {
                    if item.episodeName != nil || item.audiobookTitle != nil {
                        // This is a podcast or audiobook, skip silently
                        return nil
                    }
                    missingDataCount += 1
                    return nil
                }
                
                // Debug each filtering step
                if item.ts == nil {
                    missingDataCount += 1
                    return nil
                }
                
                if item.msPlayed == nil {
                    missingDataCount += 1
                    return nil
                }
                
                if let msPlayed = item.msPlayed, msPlayed < 30000 {
                    shortPlayCount += 1
                    return nil
                }
                
                guard let endTime = item.ts,
                      let msPlayed = item.msPlayed else {
                    filteredOutCount += 1
                    return nil
                }
                
                var track = SpotifyTrack(
                    id: item.spotifyTrackUri?.components(separatedBy: ":").last ?? UUID().uuidString,
                    name: item.masterMetadataTrackName ?? "Unknown Track",
                    artist: item.masterMetadataAlbumArtistName ?? "Unknown Artist",
                    album: item.masterMetadataAlbumAlbumName,
                    playedAt: endTime,
                    durationMs: msPlayed,
                    albumImageURL: nil // Extended history doesn't include album images
                )
                track.isFavorite = false
                track.isVisible = true
                return track
            }
            
            print("📊 IMPORT SUMMARY:")
            print("  Total items parsed: \(streamingHistory.count)")
            print("  Valid tracks created: \(tracks.count)")
            print("  Filtered out:")
            print("    - Too short (<30s): \(shortPlayCount)")
            print("    - Missing data: \(missingDataCount)")
            print("    - Podcasts/audiobooks: \(streamingHistory.count - tracks.count - shortPlayCount - missingDataCount)")
            
            // Store in local database for future use
            let storedTracks = await storeImportedTracks(tracks)
            
            // DISABLED: Automatic album art enrichment to prevent API abuse
            // User can manually trigger enrichment from settings if desired
            print("💡 Album art enrichment available in Settings → Import History → 'enrich album art'")
            
            return storedTracks
        } catch {
            print("❌ Failed to import extended streaming history: \(error)")
            
            // Provide more specific error messages
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("❌ Data corrupted at: \(context.debugDescription)")
                    throw NSError(domain: "SpotifyImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "The JSON file appears to be corrupted or invalid. Please check that you selected the correct Spotify extended streaming history files."])
                case .keyNotFound(let key, let context):
                    print("❌ Missing key '\(key.stringValue)' at: \(context.debugDescription)")
                    throw NSError(domain: "SpotifyImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "The JSON file is missing expected data fields. This may not be a Spotify extended streaming history file."])
                case .typeMismatch(let type, let context):
                    print("❌ Type mismatch for \(type) at: \(context.debugDescription)")
                    throw NSError(domain: "SpotifyImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "The JSON file has unexpected data types. Please ensure you selected Spotify extended streaming history files."])
                case .valueNotFound(let type, let context):
                    print("❌ Value not found for \(type) at: \(context.debugDescription)")
                    throw NSError(domain: "SpotifyImportError", code: 4, userInfo: [NSLocalizedDescriptionKey: "The JSON file is missing required values. This may not be a valid Spotify streaming history file."])
                @unknown default:
                    throw NSError(domain: "SpotifyImportError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON file: \(error.localizedDescription)"])
                }
            } else {
                throw NSError(domain: "SpotifyImportError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to process file: \(error.localizedDescription)"])
            }
        }
    }
    
    func fetchImportedTracksForTimeRange(startTime: Date, endTime: Date) async -> [SpotifyTrack] {
        print("🎵 Fetching imported tracks for time range: \(startTime) to \(endTime)")
        
        // Use optimized date-range query from Firebase first
        if let userId = await firebaseAuth.currentUser?.uid {
            print("☁️ Using optimized date-range query for user: \(userId)")
            do {
                let tracks = try await FirestoreService.shared.getImportedSpotifyTracksForDateRange(
                    userId: userId,
                    startDate: startTime,
                    endDate: endTime
                )
                print("☁️ Found \(tracks.count) tracks for time range via Firebase")
                return tracks
            } catch {
                print("⚠️ Failed to fetch from Firebase, falling back to local: \(error)")
                // Fall back to UserDefaults search
            }
        }
        
        // Fallback: Search local tracks for time range
        print("📱 Searching local tracks for time range...")
        guard let data = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
              let allTracks = try? JSONDecoder().decode([SpotifyTrack].self, from: data) else {
            print("📱 No local tracks found")
            return []
        }
        
        // Filter local tracks by time range
        let filteredTracks = allTracks.filter { track in
            track.playedAt >= startTime && track.playedAt <= endTime
        }.sorted { $0.playedAt < $1.playedAt }
        
        print("📱 Found \(filteredTracks.count) local tracks for time range")
        return filteredTracks
    }
    
    // MARK: - Enhanced Import with Progress Tracking
    
    func importExtendedStreamingHistoryWithProgress(from fileData: Data, progressCallback: @escaping (Double) -> Void) async throws -> [SpotifyTrack] {
        // For now, this wraps the existing method and simulates progress
        // In the future, we can enhance this to provide real granular progress
        
        print("📥 SpotifyService: Importing extended streaming history with progress tracking")
        
        // Simulate progress during different phases
        await MainActor.run { progressCallback(0.1) } // Starting
        
        // Parse JSON (this is the heavy operation)
        let tracks = try await importExtendedStreamingHistory(from: fileData)
        
        await MainActor.run { progressCallback(1.0) } // Complete
        
        return tracks
    }
    
    // MARK: - Efficient Import with Track Limits
    
    func importExtendedStreamingHistoryWithLimit(
        from fileData: Data, 
        trackLimit: Int, 
        progressCallback: @escaping (Double) -> Void
    ) async throws -> [SpotifyTrack] {
        print("📊 SpotifyService: Importing streaming history with track limit: \(trackLimit) (taking MOST RECENT tracks)")
        
        await MainActor.run { progressCallback(0.1) } // Starting
        
        // Parse JSON efficiently
        let decoder = JSONDecoder()
        
        struct SpotifyImportedTrack: Codable {
            let ts: String
            let ms_played: Int
            let master_metadata_track_name: String?
            let master_metadata_album_artist_name: String?
            let master_metadata_album_album_name: String?
            let spotify_track_uri: String?
        }
        
        let importedData = try decoder.decode([SpotifyImportedTrack].self, from: fileData)
        print("📦 Parsed \(importedData.count) raw track entries from file")
        
        await MainActor.run { progressCallback(0.3) } // Parsed data
        
        // For Spotify exports: tracks are in chronological order, so LAST tracks are most recent
        // Take the last N tracks (most recent) up to our limit
        // Use reasonable buffer (max 20,000 extra tracks) to account for filtering
        let bufferSize = min(trackLimit, 20000)
        let tracksToProcess = Array(importedData.suffix(min(trackLimit + bufferSize, importedData.count)))
        print("🔍 Processing last \(tracksToProcess.count) tracks from file (most recent)")
        
        // Convert to SpotifyTrack format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        var convertedTracks: [SpotifyTrack] = []
        
        for (index, item) in tracksToProcess.enumerated() {
            // Progress callback during conversion
            if index % 500 == 0 {
                let progress = 0.3 + (Double(index) / Double(tracksToProcess.count)) * 0.4
                await MainActor.run { progressCallback(progress) }
            }
            
            // Skip tracks with insufficient data
            guard let trackName = item.master_metadata_track_name,
                  let artistName = item.master_metadata_album_artist_name,
                  !trackName.isEmpty,
                  !artistName.isEmpty else {
                continue
            }
            
            // Parse timestamp
            let playedAt = formatter.date(from: item.ts) ?? fallbackFormatter.date(from: item.ts) ?? Date()
            
            let track = SpotifyTrack(
                id: UUID().uuidString,
                name: trackName,
                artist: artistName,
                album: item.master_metadata_album_album_name,
                playedAt: playedAt,
                durationMs: item.ms_played,
                albumImageURL: nil
            )
            
            convertedTracks.append(track)
        }
        
        // Sort by date (newest first) and take exactly what we need
        convertedTracks.sort { $0.playedAt > $1.playedAt }
        let limitedTracks = Array(convertedTracks.prefix(trackLimit))
        
        await MainActor.run { progressCallback(0.8) } // Converted and limited
        
        print("📊 Final track count: \(limitedTracks.count) MOST RECENT tracks (limit: \(trackLimit))")
        if let newest = limitedTracks.first, let oldest = limitedTracks.last {
            print("📅 Date range: \(oldest.playedAt.formatted()) to \(newest.playedAt.formatted())")
        }
        
        // Store in Firebase efficiently if we have authentication
        if let userId = await firebaseAuth.currentUser?.uid {
            try await FirestoreService.shared.storeImportedSpotifyTracks(userId: userId, tracks: limitedTracks)
            print("✅ Stored \(limitedTracks.count) tracks in Firebase")
        } else {
            // Store locally as backup
            let encoder = JSONEncoder()
            let data = try encoder.encode(limitedTracks)
            UserDefaults.standard.set(data, forKey: "imported_spotify_tracks")
            print("💾 Stored \(limitedTracks.count) tracks locally (no Firebase auth)")
        }
        
        await MainActor.run { progressCallback(1.0) } // Complete
        
        return limitedTracks
    }
    
    // MARK: - Album Art Enrichment for Recent Tracks
    
    // Public method for enriching any set of tracks with album art
    func enrichTracksWithAlbumArt(_ tracks: [SpotifyTrack]) async -> [SpotifyTrack] {
        guard await refreshTokenIfNeeded(), let accessToken = accessToken else {
            print("❌ Cannot enrich tracks: Not authenticated")
            return tracks
        }
        
        let tracksNeedingArt = tracks.filter { ($0.albumImageURL == nil || $0.albumImageURL?.isEmpty == true) && $0.album != nil }
        if tracksNeedingArt.isEmpty {
            return tracks
        }
        
        print("🎨 Auto-enriching \(tracksNeedingArt.count) tracks with album art...")
        
        // Group by unique album+artist to minimize API calls
        let albumGroups = Dictionary(grouping: tracksNeedingArt) { track in
            "\(track.album ?? "Unknown")||\(track.artist)"
        }
        
        var updatedTracks = tracks
        var successCount = 0
        
        for (albumKey, tracksForAlbum) in albumGroups {
            let components = albumKey.components(separatedBy: "||")
            let albumName = components[0]
            let artistName = components.count > 1 ? components[1] : ""
            
            print("🎨 DEBUG: Searching for album art - Album: '\(albumName)' Artist: '\(artistName)'")
            
            do {
                // Rate limiting - 0.5 seconds between requests
                try await Task.sleep(nanoseconds: 500_000_000)
                
                let albumImageURL = try await searchForAlbumArt(album: albumName, artist: artistName, accessToken: accessToken)
                
                if let albumImageURL = albumImageURL {
                    print("🎨 DEBUG: Found album art URL: \(albumImageURL)")
                    // Update all tracks for this album
                    for track in tracksForAlbum {
                        if let index = updatedTracks.firstIndex(where: { $0.id == track.id && $0.playedAt == track.playedAt }) {
                            updatedTracks[index] = SpotifyTrack(
                                id: track.id,
                                name: track.name,
                                artist: track.artist,
                                album: track.album,
                                playedAt: track.playedAt,
                                durationMs: track.durationMs,
                                albumImageURL: albumImageURL,
                                isFavorite: track.isFavorite,
                                isVisible: track.isVisible
                            )
                            successCount += 1
                        }
                    }
                    print("✅ Enriched '\(albumName)' with album art")
                } else {
                    print("🎨 DEBUG: No album art found for '\(albumName)' by '\(artistName)'")
                }
            } catch {
                print("⚠️ Failed to enrich '\(albumName)': \(error)")
            }
        }
        
        print("🎨 Album art enrichment complete: \(successCount)/\(tracksNeedingArt.count) tracks enriched")
        return updatedTracks
    }
    
    private func enrichRecentTracksWithAlbumArt(_ tracks: [SpotifyTrack]) async -> [SpotifyTrack] {
        guard await refreshTokenIfNeeded(), let accessToken = accessToken else {
            print("❌ Cannot enrich recent tracks: Not authenticated")
            return tracks
        }
        
        print("🎨 Enriching \(tracks.count) recent tracks with album art...")
        
        var enrichedTracks = tracks
        var successCount = 0
        
        // Process each track that needs album art
        for (index, track) in tracks.enumerated() {
            guard track.albumImageURL == nil, let album = track.album else { continue }
            
            do {
                // Small delay to respect rate limits
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                if let albumImageURL = try await searchForAlbumArt(album: album, artist: track.artist, accessToken: accessToken) {
                    // Create enriched track with album art
                    enrichedTracks[index] = SpotifyTrack(
                        id: track.id,
                        name: track.name,
                        artist: track.artist,
                        album: track.album,
                        playedAt: track.playedAt,
                        durationMs: track.durationMs,
                        albumImageURL: albumImageURL,
                        isFavorite: track.isFavorite,
                        isVisible: track.isVisible
                    )
                    successCount += 1
                    print("✅ Enriched '\(track.name)' with album art")
                } else {
                    print("⚠️ No album art found for '\(track.name)' by \(track.artist)")
                }
            } catch {
                print("❌ Failed to enrich '\(track.name)': \(error)")
            }
        }
        
        print("🎨 Recent tracks enrichment complete: \(successCount)/\(tracks.filter { $0.albumImageURL == nil }.count) tracks enriched")
        return enrichedTracks
    }
    
    // MARK: - Album Art Enrichment for Imported Tracks
    
    private func enrichSpecificTracks(_ tracksToEnrich: [SpotifyTrack]) async {
        print("🎨 Auto-enriching \(tracksToEnrich.count) specific tracks with album art...")
        
        // Check if we're authenticated
        guard await refreshTokenIfNeeded(), let accessToken = accessToken else {
            print("❌ Album art enrichment: Not authenticated")
            return
        }
        
        // Group by unique album+artist to minimize API calls
        let albumGroups = Dictionary(grouping: tracksToEnrich) { track in
            "\(track.album ?? "Unknown")||\(track.artist)"
        }
        
        print("🎯 Need to search for \(albumGroups.count) unique albums for these tracks")
        
        // Get all tracks to update the full dataset
        guard let data = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
              let allTracks = try? JSONDecoder().decode([SpotifyTrack].self, from: data) else {
            print("⚠️ No stored tracks found for enrichment")
            return
        }
        
        var updatedTracks = allTracks
        var successCount = 0
        let rateLimitDelay: Double = 1.0 // Start with 1 second delay for auto-enrichment
        
        // Process each unique album
        for (albumKey, tracksForAlbum) in albumGroups {
            let components = albumKey.components(separatedBy: "||")
            let albumName = components[0]
            let artistName = components[1]
            
            print("🔍 Auto-searching for album art: '\(albumName)' by \(artistName)")
            
            do {
                // Rate limiting - be more conservative for auto-enrichment
                try await Task.sleep(nanoseconds: UInt64(rateLimitDelay * 1_000_000_000))
                
                if let albumImageURL = try await searchForAlbumArt(album: albumName, artist: artistName, accessToken: accessToken) {
                    // Update all tracks for this album
                    for track in tracksForAlbum {
                        if let index = updatedTracks.firstIndex(where: { $0.id == track.id && $0.playedAt == track.playedAt }) {
                            let updatedTrack = updatedTracks[index]
                            let newTrack = SpotifyTrack(
                                id: updatedTrack.id,
                                name: updatedTrack.name,
                                artist: updatedTrack.artist,
                                album: updatedTrack.album,
                                playedAt: updatedTrack.playedAt,
                                durationMs: updatedTrack.durationMs,
                                albumImageURL: albumImageURL,
                                isFavorite: updatedTrack.isFavorite,
                                isVisible: updatedTrack.isVisible
                            )
                            updatedTracks[index] = newTrack
                        }
                    }
                    successCount += tracksForAlbum.count
                    print("✅ Auto-enriched '\(albumName)' - updated \(tracksForAlbum.count) tracks")
                } else {
                    print("⚠️ No album art found for '\(albumName)' by \(artistName)")
                }
                
            } catch {
                print("❌ Error auto-searching for '\(albumName)': \(error)")
                
                // If we hit rate limits, increase delay and break to avoid more failures
                if error.localizedDescription.contains("429") || error.localizedDescription.contains("rate limit") {
                    print("⏰ Rate limited - stopping auto-enrichment for now")
                    break
                }
            }
        }
        
        // Store updated tracks in Firebase and UserDefaults
        do {
            if let userId = await firebaseAuth.currentUser?.uid {
                try await FirestoreService.shared.updateImportedSpotifyTracks(userId: userId, tracks: updatedTracks)
                print("☁️ Auto-enrichment: Updated \(successCount) tracks in Firebase")
            }
            
            // Also update local cache
            let encodedData = try JSONEncoder().encode(updatedTracks)
            UserDefaults.standard.set(encodedData, forKey: "imported_spotify_tracks")
            print("✅ Auto-enrichment complete! Updated \(successCount) tracks with album art")
        } catch {
            print("❌ Failed to save auto-enriched tracks: \(error)")
        }
    }
    
    // DEPRECATED: Use enrichTracksWithAlbumArt() for on-demand enrichment instead
    func enrichImportedTracksWithAlbumArt() async {
        print("⚠️ DEPRECATED: This function processes too many tracks.")
        print("💡 Use enrichTracksWithAlbumArt() for selective enrichment instead.")
        print("🎨 Album art is now enriched on-demand when viewing run details.")
        
        // Don't process all imported tracks - this was the source of the API abuse
        return
    }
    
    private func searchForAlbumArt(album: String, artist: String, accessToken: String) async throws -> String? {
        // Clean up search terms
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Build search query - prioritize exact matches
        let query = "album:\"\(cleanAlbum)\" artist:\"\(cleanArtist)\""
        
        var components = URLComponents(string: "https://api.spotify.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "limit", value: "1") // We only need the first result
        ]
        
        guard let url = components?.url else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.requestFailed
        }
        
        if httpResponse.statusCode == 429 {
            // Rate limited - throw specific error
            throw SpotifyError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            throw SpotifyError.requestFailed
        }
        
        // Parse search results
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let albums = json["albums"] as? [String: Any],
           let items = albums["items"] as? [[String: Any]],
           let firstAlbum = items.first,
           let images = firstAlbum["images"] as? [[String: Any]],
           let firstImage = images.first,
           let imageURL = firstImage["url"] as? String {
            return imageURL
        }
        
        return nil
    }
    
    private func storeImportedTracks(_ newTracks: [SpotifyTrack]) async -> [SpotifyTrack] {
        print("💾 Storing \(newTracks.count) imported tracks...")
        
        do {
            // Get existing tracks from Firebase or UserDefaults
            var allTracks: [SpotifyTrack] = []
            
            // Try Firebase first if authenticated
            if let userId = await firebaseAuth.currentUser?.uid {
                print("☁️ Using Firebase storage for user: \(userId)")
                allTracks = try await FirestoreService.shared.getImportedSpotifyTracks(userId: userId)
                print("📊 Found \(allTracks.count) existing tracks in Firebase")
            } else {
                print("📱 Using local storage (not authenticated)")
                if let existingData = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
                   let existingTracks = try? JSONDecoder().decode([SpotifyTrack].self, from: existingData) {
                    allTracks = existingTracks
                    print("📊 Found \(existingTracks.count) existing tracks locally")
                }
            }
            
            // Add new tracks (avoiding duplicates based on track ID and timestamp)
            let existingIDs = Set(allTracks.map { "\($0.id)-\($0.playedAt.timeIntervalSince1970)" })
            let uniqueNewTracks = newTracks.filter { track in
                !existingIDs.contains("\(track.id)-\(track.playedAt.timeIntervalSince1970)")
            }
            
            allTracks.append(contentsOf: uniqueNewTracks)
            print("📊 Added \(uniqueNewTracks.count) unique tracks (total now: \(allTracks.count))")
            
            // Apply subscription-based track limits
            let subscriptionService = SubscriptionService.shared
            let limitedTracks = subscriptionService.limitedTrackCount(allTracks)
            if allTracks.count != limitedTracks.count {
                print("📊 Track limit applied: \(allTracks.count) tracks available, \(limitedTracks.count) tracks allowed (\(subscriptionService.trackLimitText()))")
            }
            
            // Store tracks in Firebase or UserDefaults
            if let userId = await firebaseAuth.currentUser?.uid {
                try await FirestoreService.shared.storeImportedSpotifyTracks(userId: userId, tracks: limitedTracks)
                print("☁️ Successfully stored \(limitedTracks.count) tracks in Firebase")
            } else {
                let data = try JSONEncoder().encode(limitedTracks)
                UserDefaults.standard.set(data, forKey: "imported_spotify_tracks")
                print("📱 Successfully stored \(limitedTracks.count) tracks locally")
            }
            
            return limitedTracks
        } catch {
            print("❌ Failed to store imported tracks: \(error)")
            return newTracks // Return original tracks if storage fails
        }
    }
    
    func hasImportedTracks() -> Bool {
        // For UI responsiveness, just check UserDefaults
        // The actual Firebase sync will happen during data fetching
        return UserDefaults.standard.data(forKey: "imported_spotify_tracks") != nil
    }
    
    func getImportedTracksFromLocal() -> [SpotifyTrack] {
        guard let data = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
              let tracks = try? JSONDecoder().decode([SpotifyTrack].self, from: data) else {
            return []
        }
        return tracks
    }
    
    func getDateRange(for tracks: [SpotifyTrack]) -> String {
        guard !tracks.isEmpty else { return "No tracks" }
        
        let sortedTracks = tracks.sorted { $0.playedAt < $1.playedAt }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        let startDate = formatter.string(from: sortedTracks.first!.playedAt)
        let endDate = formatter.string(from: sortedTracks.last!.playedAt)
        
        return "\(startDate) - \(endDate)"
    }
    
    func getImportedTracksInfo() -> (count: Int, dateRange: String) {
        // Try to get from local cache first for responsiveness
        guard let data = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
              let tracks = try? JSONDecoder().decode([SpotifyTrack].self, from: data) else {
            return (0, "No imported tracks")
        }
        
        if let earliestTrack = tracks.min(by: { $0.playedAt < $1.playedAt }),
           let latestTrack = tracks.max(by: { $0.playedAt < $1.playedAt }) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            let startDate = formatter.string(from: earliestTrack.playedAt)
            let endDate = formatter.string(from: latestTrack.playedAt)
            
            // Calculate years spanned
            let years = Calendar.current.dateComponents([.year], from: earliestTrack.playedAt, to: latestTrack.playedAt).year ?? 0
            let yearsText = years > 0 ? " (\(years + 1) year\(years > 0 ? "s" : ""))" : ""
            
            return (tracks.count, "\(startDate) to \(endDate)\(yearsText)")
        }
        
        return (tracks.count, "Unknown date range")
    }
    
    func clearImportedTracks() async {
        // Clear from UserDefaults only - Firebase data now handled by cleanup function
        UserDefaults.standard.removeObject(forKey: "imported_spotify_tracks")
        print("🗑️ Cleared local imported tracks")
        print("💡 Use cleanup function in Settings to remove Firebase data")
    }
    
    func debugImportStatus() {
        if hasImportedTracks() {
            let info = getImportedTracksInfo()
            print("📊 SPOTIFY IMPORT STATUS:")
            print("   ✅ Import successful!")
            print("   📈 Total tracks: \(info.count)")
            print("   📅 Date range: \(info.dateRange)")
            
            // Load a few sample tracks for verification
            guard let data = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
                  let tracks = try? JSONDecoder().decode([SpotifyTrack].self, from: data) else { return }
            
            print("   🎵 Sample tracks:")
            for (index, track) in tracks.prefix(5).enumerated() {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                print("      \(index + 1). '\(track.name)' by \(track.artist) - \(formatter.string(from: track.playedAt))")
            }
        } else {
            print("📊 SPOTIFY IMPORT STATUS:")
            print("   ❌ No imported tracks found")
            print("   💡 Try importing your Spotify extended history JSON files")
        }
    }
    
    func syncImportedTracksFromFirebase() async {
        guard let userId = await firebaseAuth.currentUser?.uid else {
            print("📱 No Firebase user - cannot sync imported tracks")
            return
        }
        
        print("☁️ Syncing imported tracks from Firebase...")
        
        do {
            let firebaseTracks = try await FirestoreService.shared.getImportedSpotifyTracks(userId: userId)
            print("☁️ Found \(firebaseTracks.count) tracks in Firebase")
            
            if !firebaseTracks.isEmpty {
                // Sync to local cache
                let data = try JSONEncoder().encode(firebaseTracks)
                UserDefaults.standard.set(data, forKey: "imported_spotify_tracks")
                print("💾 Synced \(firebaseTracks.count) tracks to local cache")
                
                await MainActor.run {
                    // Trigger UI update if needed
                    objectWillChange.send()
                }
            }
        } catch {
            print("⚠️ Failed to sync imported tracks from Firebase: \(error)")
        }
    }
    
    // CRITICAL FIX: Bidirectional sync to handle both directions
    func syncImportedTracksBidirectional() async {
        guard let userId = await firebaseAuth.currentUser?.uid else {
            print("📱 No Firebase user - cannot sync imported tracks")
            return
        }
        
        print("🔄 CRITICAL FIX: Starting bidirectional imported tracks sync...")
        
        do {
            // First, check what's in Firebase
            let firebaseTracks = try await FirestoreService.shared.getImportedSpotifyTracks(userId: userId)
            print("☁️ Found \(firebaseTracks.count) tracks in Firebase")
            
            // Check what's in local storage
            var localTracks: [SpotifyTrack] = []
            if let localData = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
               let decodedTracks = try? JSONDecoder().decode([SpotifyTrack].self, from: localData) {
                localTracks = decodedTracks
            }
            print("📱 Found \(localTracks.count) tracks in local storage")
            
            if firebaseTracks.isEmpty && !localTracks.isEmpty {
                // Case 1: Firebase empty, local has data → Upload local to Firebase
                print("🔼 MIGRATION: Uploading \(localTracks.count) local tracks to Firebase...")
                try await FirestoreService.shared.storeImportedSpotifyTracks(userId: userId, tracks: localTracks)
                print("✅ Successfully migrated local tracks to Firebase!")
                
            } else if !firebaseTracks.isEmpty && localTracks.isEmpty {
                // Case 2: Firebase has data, local empty → Download from Firebase
                print("🔽 SYNC: Downloading \(firebaseTracks.count) tracks from Firebase...")
                let data = try JSONEncoder().encode(firebaseTracks)
                UserDefaults.standard.set(data, forKey: "imported_spotify_tracks")
                print("✅ Successfully synced tracks from Firebase to local!")
                
            } else if !firebaseTracks.isEmpty && !localTracks.isEmpty {
                // Case 3: Both have data → Merge (Firebase takes precedence)
                print("🔄 MERGE: Both sources have data, using Firebase as source of truth")
                let data = try JSONEncoder().encode(firebaseTracks)
                UserDefaults.standard.set(data, forKey: "imported_spotify_tracks")
                print("✅ Successfully merged with Firebase data!")
                
            } else {
                // Case 4: Both empty
                print("📭 Both Firebase and local storage are empty - no sync needed")
            }
            
            await MainActor.run {
                // Trigger UI update
                objectWillChange.send()
            }
            
        } catch {
            print("❌ CRITICAL ERROR: Bidirectional sync failed: \(error)")
            // Fallback to the old one-way sync
            await syncImportedTracksFromFirebase()
        }
    }
    
    // MARK: - Migration Utility
    
    func migrateLocalTracksToFirebase() async -> Bool {
        guard let userId = await firebaseAuth.currentUser?.uid else {
            print("❌ No Firebase user - cannot migrate local tracks")
            return false
        }
        
        // Check if we have local tracks to migrate
        guard let localData = UserDefaults.standard.data(forKey: "imported_spotify_tracks"),
              let localTracks = try? JSONDecoder().decode([SpotifyTrack].self, from: localData),
              !localTracks.isEmpty else {
            print("📱 No local tracks found to migrate")
            return false
        }
        
        print("🔄 Starting migration of \(localTracks.count) local tracks to Firebase...")
        
        do {
            // Check if tracks already exist in Firebase
            let existingFirebaseTracks = try await FirestoreService.shared.getImportedSpotifyTracks(userId: userId)
            
            if !existingFirebaseTracks.isEmpty {
                print("☁️ Firebase already has \(existingFirebaseTracks.count) tracks - skipping migration")
                return true
            }
            
            // Upload local tracks to Firebase
            try await FirestoreService.shared.storeImportedSpotifyTracks(userId: userId, tracks: localTracks)
            
            print("✅ Successfully migrated \(localTracks.count) tracks to Firebase!")
            return true
            
        } catch {
            print("❌ Failed to migrate tracks to Firebase: \(error)")
            return false
        }
    }
    
    private func fetchUserProfile() {
        guard let accessToken = accessToken else { return }
        
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let profile = try? JSONDecoder().decode(SpotifyUserProfile.self, from: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self?.userProfile = profile
            }
        }.resume()
    }
    
    func logout() {
        print("🎵 SpotifyService: Logging out...")
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userProfile = nil
        isAuthenticated = false
        clearStoredCredentials()
        
        // AUTO-DISABLE background sync when Spotify disconnects
        Task {
            print("🔄 SpotifyService: Auto-disabling background sync for disconnected Spotify account...")
            await SpotifyBackgroundSync.shared.disableBackgroundSyncAutomatically()
        }
    }
    
    // MARK: - Refresh Token Recovery
    
    /// Diagnoses authentication issues and provides recovery options
    func diagnoseAuthenticationIssues() -> AuthDiagnosis {
        let hasAccessToken = accessToken != nil
        let hasRefreshToken = refreshToken != nil
        
        let isExpired = tokenExpiresAt.map { Date() >= $0 } ?? false
        
        if !hasAccessToken {
            return .notAuthenticated
        }
        
        if !hasRefreshToken {
            return .missingRefreshToken
        }
        
        if isExpired {
            return .tokenExpired
        }
        
        return .healthy
    }
    
    /// Forces a complete re-authentication flow by clearing all stored credentials
    func forceReAuthentication() {
        print("🔄 SpotifyService: Forcing complete re-authentication...")
        print("🔄 This will clear all stored tokens and require user to log in again")
        
        // Clear all tokens and state
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userProfile = nil
        isAuthenticated = false
        
        // Clear local storage
        clearStoredCredentials()
        
        // Clear Firebase storage (if authenticated) - do this in background
        Task {
            let userId = await MainActor.run { FirebaseAuthService.shared.currentUser?.uid }
            if let userId = userId {
                do {
                    try await FirestoreService.shared.clearUserTokens(userId: userId, service: "spotify")
                    print("✅ Cleared Spotify tokens from Firebase")
                } catch {
                    print("⚠️ Failed to clear Spotify tokens from Firebase: \(error)")
                }
            }
        }
        
        print("✅ SpotifyService: Forced re-authentication complete - user must authenticate again")
    }
    
    enum AuthDiagnosis {
        case healthy
        case notAuthenticated  
        case missingRefreshToken
        case tokenExpired
        
        var userMessage: String {
            switch self {
            case .healthy:
                return "Authentication is working properly"
            case .notAuthenticated:
                return "Not connected to Spotify"
            case .missingRefreshToken:
                return "Connection to Spotify needs to be refreshed. Please reconnect your account."
            case .tokenExpired:
                return "Spotify connection has expired and will be refreshed automatically"
            }
        }
        
        var needsReAuthentication: Bool {
            switch self {
            case .healthy, .tokenExpired:
                return false
            case .notAuthenticated, .missingRefreshToken:
                return true
            }
        }
    }
    
    private func storeCredentials(_ authResponse: SpotifyAuthResponse) {
        print("🔐 STORING CREDENTIALS:")
        print("🔐   accessToken length: \(authResponse.accessToken.count)")
        print("🔐   refreshToken provided: \(authResponse.refreshToken != nil)")
        if let refreshToken = authResponse.refreshToken {
            print("🔐   refreshToken length: \(refreshToken.count)")
            print("🔐   refreshToken prefix: \(String(refreshToken.prefix(10)))...")
        } else {
            print("🚨   WARNING: No refresh token in auth response!")
        }
        
        UserDefaults.standard.set(authResponse.accessToken, forKey: "spotify_access_token")
        if let refreshToken = authResponse.refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: "spotify_refresh_token")
            print("✅   Stored refresh token to UserDefaults")
        } else {
            print("⚠️   No refresh token to store - this might cause future authentication issues")
        }
        
        let expirationDate = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
        UserDefaults.standard.set(expirationDate, forKey: "spotify_expires_at")
        print("✅   Stored expiration date: \(expirationDate)")
        
        // Store to Firebase for cross-device sync
        storeCredentialsToFirebase(authResponse)
    }
    
    private func storeCredentialsToFirebase(_ authResponse: SpotifyAuthResponse) {
        Task {
            await storeTokensToFirebase(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
            )
        }
    }
    
    private func loadStoredCredentials() {
        print("🔐 LOADING STORED CREDENTIALS:")
        
        accessToken = UserDefaults.standard.string(forKey: "spotify_access_token")
        refreshToken = UserDefaults.standard.string(forKey: "spotify_refresh_token")
        tokenExpiresAt = UserDefaults.standard.object(forKey: "spotify_expires_at") as? Date
        
        print("🔐   accessToken loaded: \(accessToken != nil)")
        if let accessToken = accessToken {
            print("🔐   accessToken length: \(accessToken.count)")
            print("🔐   accessToken prefix: \(String(accessToken.prefix(10)))...")
        }
        
        print("🔐   refreshToken loaded: \(refreshToken != nil)")
        if let refreshToken = refreshToken {
            print("🔐   refreshToken length: \(refreshToken.count)")
            print("🔐   refreshToken prefix: \(String(refreshToken.prefix(10)))...")
        } else {
            print("🚨   CRITICAL: No refresh token found in UserDefaults!")
        }
        
        print("🔐   tokenExpiresAt loaded: \(tokenExpiresAt != nil)")
        if let expiresAt = tokenExpiresAt {
            print("🔐   Expires at: \(expiresAt)")
            let isExpired = Date() >= expiresAt
            print("🔐   Is expired: \(isExpired)")
            if isExpired {
                print("⚠️ SpotifyService: Stored token is expired, will need refresh")
                // Don't clear credentials here - we'll try to refresh when needed
            }
        }
        
        // CRITICAL CHECK: Access token without refresh token
        if accessToken != nil && refreshToken == nil {
            print("🚨 PROBLEMATIC STATE: Have access token but no refresh token!")
            print("🚨 This will cause authentication failures when token expires")
            print("🚨 User will need to re-authenticate to get a new refresh token")
        }
        
        isAuthenticated = accessToken != nil
        
        // If we have valid credentials, load user profile
        if isAuthenticated {
            fetchUserProfile()
        }
        
        print("🎵 SpotifyService: Loaded stored credentials - authenticated: \(isAuthenticated)")
    }
    
    func refreshTokenIfNeeded() async -> Bool {
        print("🔐 SpotifyService: Checking token refresh need...")
        print("🔐   accessToken exists: \(accessToken != nil)")
        print("🔐   refreshToken exists: \(refreshToken != nil)")
        print("🔐   tokenExpiresAt: \(tokenExpiresAt?.description ?? "nil")")
        
        // CRITICAL: If we have no refresh token but think we're authenticated, this is problematic
        if accessToken != nil && refreshToken == nil {
            print("🚨 CRITICAL: Have access token but no refresh token - user needs to re-authenticate!")
            print("🚨 This indicates refresh token was lost or never properly stored")
            
            // Mark as not authenticated to force re-authentication
            await MainActor.run {
                self.isAuthenticated = false
            }
            return false
        }
        
        guard let tokenExpiresAt = tokenExpiresAt else {
            print("🔐 No expiration time - returning token status: \(accessToken != nil)")
            return accessToken != nil
        }
        
        let now = Date()
        let isExpired = now >= tokenExpiresAt
        print("🔐 Token expired check: \(isExpired) (now: \(now), expires: \(tokenExpiresAt))")
        
        // If token is not expired, we're good
        if !isExpired {
            print("🔐 Token not expired - returning: \(accessToken != nil)")
            return accessToken != nil
        }
        
        // Token is expired - we need to refresh
        guard let refreshToken = refreshToken else {
            print("🚨 Token expired but no refresh token available - user needs to re-authenticate!")
            await MainActor.run {
                self.isAuthenticated = false
            }
            return false
        }
        
        print("🔄 SpotifyService: Token expired, attempting refresh...")
        
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let credentials = "\(clientID):\(clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 SpotifyService: Token refresh response: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    let authResponse = try JSONDecoder().decode(SpotifyAuthResponse.self, from: data)
                    
                    DispatchQueue.main.async {
                        self.accessToken = authResponse.accessToken
                        self.isAuthenticated = true
                        
                        // Update refresh token if provided
                        if let newRefreshToken = authResponse.refreshToken {
                            self.refreshToken = newRefreshToken
                        }
                        
                        // CRITICAL: Update token expiration time to prevent immediate re-expiry
                        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
                        
                        self.storeCredentials(authResponse)
                        print("✅ SpotifyService: Token refreshed successfully, expires at: \(self.tokenExpiresAt!)")
                    }
                    return true
                } else {
                    print("❌ SpotifyService: Token refresh failed with status: \(httpResponse.statusCode)")
                    if let errorData = String(data: data, encoding: .utf8) {
                        print("❌ Error response: \(errorData)")
                    }
                    DispatchQueue.main.async {
                        self.clearStoredCredentials()
                        self.isAuthenticated = false
                        self.accessToken = nil
                        self.refreshToken = nil
                    }
                    return false
                }
            }
        } catch {
            print("❌ SpotifyService: Token refresh error: \(error.localizedDescription)")
            return false
        }
        
        return false
    }
    
    private func clearStoredCredentials() {
        UserDefaults.standard.removeObject(forKey: "spotify_access_token")
        UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
        UserDefaults.standard.removeObject(forKey: "spotify_expires_at")
        
        refreshToken = nil
        tokenExpiresAt = nil
        
        // Also clear from Firebase
        Task {
            await clearTokensFromFirebase()
        }
    }
    
    // MARK: - Firebase Token Sync
    
    private func storeTokensToFirebase(accessToken: String, refreshToken: String?, expiresAt: Date) async {
        guard let userId = await firebaseAuth.currentUser?.uid else {
            print("📱 SpotifyService: No Firebase user, skipping token sync")
            return
        }
        
        do {
            // Create tokens object for encryption
            let tokens = StorableTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
            
            // Encrypt the tokens
            let tokensData = try JSONEncoder().encode(tokens)
            let tokensString = String(data: tokensData, encoding: .utf8) ?? ""
            let encryptedToken = try TokenEncryption.shared.encryptTokenString(tokensString, userId: userId)
            
            // Store to Firebase
            try await FirestoreService.shared.storeEncryptedToken(
                userId: userId,
                service: "spotify",
                token: encryptedToken
            )
            
            print("✅ SpotifyService: Tokens stored to Firebase for cross-device sync")
        } catch {
            print("❌ SpotifyService: Failed to store tokens to Firebase: \(error.localizedDescription)")
        }
    }
    
    private func loadTokensFromFirebase() async -> Bool {
        guard let userId = await firebaseAuth.currentUser?.uid else {
            print("📱 SpotifyService: No Firebase user, skipping token load")
            return false
        }
        
        do {
            // Load encrypted tokens from Firebase
            guard let encryptedToken = try await FirestoreService.shared.getEncryptedToken(
                userId: userId,
                service: "spotify"
            ) else {
                print("📱 SpotifyService: No stored tokens in Firebase")
                return false
            }
            
            // Decrypt the tokens
            let tokensString = try TokenEncryption.shared.decryptTokenString(
                encryptedToken: encryptedToken,
                userId: userId
            )
            
            guard let tokensData = tokensString.data(using: .utf8),
                  let tokens = try? JSONDecoder().decode(StorableTokens.self, from: tokensData) else {
                print("❌ SpotifyService: Failed to decode tokens from Firebase")
                return false
            }
            
            // Update local credentials
            print("🔐 Firebase tokens loaded:")
            print("🔐   accessToken: EXISTS (\(tokens.accessToken.count) chars)")
            print("🔐   refreshToken: \(tokens.refreshToken != nil ? "EXISTS (\(tokens.refreshToken!.count) chars)" : "NIL")")
            print("🔐   expiresAt: \(tokens.expiresAt?.description ?? "NIL")")
            
            await MainActor.run {
                self.accessToken = tokens.accessToken
                self.refreshToken = tokens.refreshToken
                self.tokenExpiresAt = tokens.expiresAt
                self.isAuthenticated = true
            }
            
            // Store locally as backup
            UserDefaults.standard.set(tokens.accessToken, forKey: "spotify_access_token")
            if let refreshToken = tokens.refreshToken {
                UserDefaults.standard.set(refreshToken, forKey: "spotify_refresh_token")
            }
            if let expiresAt = tokens.expiresAt {
                UserDefaults.standard.set(expiresAt, forKey: "spotify_expires_at")
            }
            
            print("✅ SpotifyService: Tokens loaded from Firebase")
            
            // Check if tokens are expired
            if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
                print("⚠️ SpotifyService: Loaded tokens are expired, attempting refresh...")
                do {
                    let refreshSuccess = await refreshTokenIfNeeded()
                    if refreshSuccess {
                        print("✅ SpotifyService: Successfully refreshed expired tokens")
                        // Load user profile data after successful refresh
                        await MainActor.run {
                            self.fetchUserProfile()
                        }
                        return true
                    } else {
                        print("❌ SpotifyService: Failed to refresh tokens")
                        await MainActor.run {
                            self.clearStoredCredentials()
                            self.isAuthenticated = false
                        }
                        return false
                    }
                } catch {
                    print("❌ SpotifyService: Failed to refresh tokens: \(error)")
                    await MainActor.run {
                        self.clearStoredCredentials()
                        self.isAuthenticated = false
                    }
                    return false
                }
            }
            
            // Load user profile data
            await MainActor.run {
                self.fetchUserProfile()
            }
            
            // Validate the loaded tokens by attempting a simple API call
            let isValid = await validateTokens()
            if !isValid {
                print("⚠️ SpotifyService: Loaded tokens appear to be invalid, attempting refresh...")
                // Try to refresh if we have a refresh token
                if refreshToken != nil {
                    do {
                        let refreshSuccess = await refreshTokenIfNeeded()
                        if refreshSuccess {
                            print("✅ SpotifyService: Successfully refreshed invalid tokens")
                            return true
                        } else {
                            print("❌ SpotifyService: Failed to refresh tokens")
                            await MainActor.run {
                                self.clearStoredCredentials()
                                self.isAuthenticated = false
                            }
                            return false
                        }
                    } catch {
                        print("❌ SpotifyService: Failed to refresh tokens: \(error)")
                        await MainActor.run {
                            self.clearStoredCredentials()
                            self.isAuthenticated = false
                        }
                        return false
                    }
                } else {
                    print("❌ SpotifyService: No refresh token available, clearing...")
                    await MainActor.run {
                        self.clearStoredCredentials()
                        self.isAuthenticated = false
                    }
                    return false
                }
            } else {
                // CRITICAL FIX: Set isAuthenticated = true when tokens are valid
                print("✅ SpotifyService: Token validation successful, updating authentication state")
                await MainActor.run {
                    self.isAuthenticated = true
                }
            }
            
            return true
        } catch {
            print("❌ SpotifyService: Failed to load tokens from Firebase: \(error.localizedDescription)")
            
            // FALLBACK: Try to use local credentials if Firebase fails
            print("🔄 SpotifyService: Attempting fallback to local credentials...")
            if let localAccessToken = accessToken,
               let localRefreshToken = refreshToken,
               let localExpiresAt = tokenExpiresAt,
               localExpiresAt > Date() {
                
                print("✅ SpotifyService: Using valid local credentials as fallback")
                await MainActor.run {
                    self.isAuthenticated = true
                }
                
                // Try to validate the local tokens
                let isValid = await validateTokens()
                if isValid {
                    print("✅ SpotifyService: Local fallback tokens validated successfully")
                    return true
                } else {
                    print("❌ SpotifyService: Local fallback tokens are invalid")
                    await MainActor.run {
                        self.isAuthenticated = false
                    }
                }
            }
            
            // If it's a CryptoKit error (likely due to old token format), clear the corrupted tokens
            if error.localizedDescription.contains("CryptoKit") {
                print("🔧 SpotifyService: Detected old token format, clearing corrupted tokens...")
                await clearTokensFromFirebase()
            }
            
            return false
        }
    }
    
    // Validate tokens by making a simple API call
    private func validateTokens() async -> Bool {
        guard let accessToken = accessToken else { return false }
        
        let url = URL(string: "https://api.spotify.com/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let isValid = httpResponse.statusCode == 200
                print("🔐 SpotifyService: Token validation - Status: \(httpResponse.statusCode), Valid: \(isValid)")
                return isValid
            }
        } catch {
            print("❌ SpotifyService: Token validation failed: \(error.localizedDescription)")
        }
        
        return false
    }
    
    private func clearTokensFromFirebase() async {
        guard let userId = await firebaseAuth.currentUser?.uid else { return }
        
        do {
            try await FirestoreService.shared.deleteToken(userId: userId, service: "spotify")
            print("✅ SpotifyService: Tokens cleared from Firebase")
        } catch {
            print("❌ SpotifyService: Failed to clear tokens from Firebase: \(error.localizedDescription)")
        }
    }
    
    // Public method to sync tokens when Firebase user signs in
    public func syncWithFirebase() async {
        print("🔄 SpotifyService: Syncing with Firebase...")
        
        // Try to load tokens from Firebase first
        if await loadTokensFromFirebase() {
            // Successfully loaded from Firebase
            print("✅ Loaded Spotify tokens from Firebase")
        } else {
            // If no Firebase tokens but we have local tokens, upload to Firebase
            if let localAccessToken = UserDefaults.standard.string(forKey: "spotify_access_token"),
               let localRefreshToken = UserDefaults.standard.string(forKey: "spotify_refresh_token"),
               let localExpiresAt = UserDefaults.standard.object(forKey: "spotify_expires_at") as? Date {
                
                await storeTokensToFirebase(
                    accessToken: localAccessToken,
                    refreshToken: localRefreshToken,
                    expiresAt: localExpiresAt
                )
            }
        }
        
        // CRITICAL FIX: Sync imported tracks bidirectionally (local ↔ Firebase)
        await syncImportedTracksBidirectional()
    }
}

enum SpotifyError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case requestFailed
    case decodingError
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Spotify"
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed:
            return "Request failed"
        case .decodingError:
            return "Failed to decode response"
        case .rateLimited:
            return "Rate limited by Spotify API"
        }
    }
}