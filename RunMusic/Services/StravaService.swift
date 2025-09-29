import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class StravaService: ObservableObject {
    static let shared = StravaService()
    
    private let clientID = "170240"
    private let clientSecret = "3e3088e5a4b2420aa9a0817d9b2010d554896f15"
    private let redirectURI = "runthetunes://runthetunes.app"
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var athlete: StravaAthlete?
    
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    
    private init() {
        loadStoredCredentials()
    }
    
    var authURL: URL? {
        // Use web OAuth for reliability - many apps skip native Strava auth due to issues
        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all")
        ]
        return components?.url
    }
    
    var nativeAuthURL: URL? {
        // Keep native option available but separate
        let urlString = "strava://oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&response_type=code&scope=read,activity:read_all"
        return URL(string: urlString)
    }
    
    private func canOpenStravaApp() -> Bool {
        guard let stravaURL = URL(string: "strava://") else { return false }
        return UIApplication.shared.canOpenURL(stravaURL)
    }
    
    private func stravaAppAuthURL() -> URL? {
        // Strava native app uses a different URL format
        let urlString = "strava://oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&response_type=code&scope=read,activity:read_all"
        return URL(string: urlString)
    }
    
    func authenticate(preferNative: Bool = false) {
        print("🔵 StravaService: Starting authentication (preferNative: \(preferNative))")
        
        if preferNative && canOpenStravaApp() {
            guard let nativeURL = nativeAuthURL else {
                print("❌ StravaService: Failed to create native auth URL")
                return
            }
            print("📱 StravaService: Attempting native Strava app auth with URL: \(nativeURL)")
            UIApplication.shared.open(nativeURL) { success in
                DispatchQueue.main.async {
                    print("📱 StravaService: Native app open result: \(success)")
                    if !success {
                        print("⚠️ StravaService: Native auth failed, should fallback to web")
                    }
                }
            }
        } else {
            print("🌐 StravaService: Using web authentication")
            // This will be handled by AuthenticationView with Safari
        }
    }
    
    func handleAuthCallback(url: URL) {
        print("🔄 StravaService: Handling auth callback with URL: \(url)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("❌ StravaService: Failed to extract code from callback URL")
            return
        }
        
        print("✅ StravaService: Got auth code, exchanging for token")
        exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: "https://www.strava.com/oauth/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let authResponse = try? JSONDecoder().decode(StravaAuthResponse.self, from: data) else {
                print("Failed to decode auth response: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            DispatchQueue.main.async {
                self?.accessToken = authResponse.accessToken
                self?.athlete = authResponse.athlete
                self?.isAuthenticated = true
                self?.storeCredentials(authResponse)
            }
        }.resume()
    }
    
    func fetchActivities(page: Int = 1, perPage: Int = 20) async throws -> [StravaActivity] {
        print("📊 StravaService: Fetching activities (page: \(page), perPage: \(perPage))")
        
        return try await performRequestWithRetry { [self] in
            // Ensure we have a valid access token
            try await self.ensureValidAccessToken()
            
            guard let accessToken = self.accessToken else {
                print("❌ StravaService: No access token available after refresh attempt")
                throw StravaError.notAuthenticated
            }
            
            var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")
            components?.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "per_page", value: "\(perPage)")
            ]
            
            guard let url = components?.url else {
                print("❌ StravaService: Invalid URL for activities")
                throw StravaError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            print("🌐 StravaService: Making request to: \(url)")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ StravaService: Invalid response type for activities")
                throw StravaError.requestFailed
            }
            
            print("📡 StravaService: Received activities response with status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 429 {
                // Parse the Retry-After header if present
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                print("⏱️ StravaService: Rate limited (429), retry after: \(retryAfter ?? 0) seconds")
                throw StravaError.rateLimited(retryAfter: retryAfter)
            } else if httpResponse.statusCode != 200 {
                print("❌ StravaService: HTTP error \(httpResponse.statusCode) for activities")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Response body: \(responseString)")
                }
                throw StravaError.requestFailed
            }
            
            print("✅ StravaService: Successfully received activities data (\(data.count) bytes)")
            
            do {
                let activities = try JSONDecoder().decode([StravaActivity].self, from: data)
                print("✅ StravaService: Successfully decoded \(activities.count) activities")
                
                // Log each activity's basic info (limit to first 5 for debugging)
                let recentRuns = activities.filter { $0.type == "Run" }.prefix(5)
                for activity in recentRuns {
                    print("🏃 Activity: '\(activity.name)' (ID: \(activity.id), Type: \(activity.type))")
                    print("  - Distance: \(activity.distance)m")
                    print("  - Has polyline: \(activity.map?.polyline != nil)")
                    print("  - Start lat/lng: \(activity.startLatlng?.description ?? "nil")")
                }
                
                return activities
            } catch {
                print("❌ StravaService: Failed to decode activities: \(error)")
                throw StravaError.decodingError
            }
        }
    }
    
    func fetchDetailedActivity(id: Int) async throws -> StravaDetailedActivity {
        print("🔍 StravaService: Fetching detailed activity for ID: \(id)")
        
        return try await performRequestWithRetry { [self] in
            // Ensure we have a valid access token
            try await self.ensureValidAccessToken()
            
            guard let accessToken = self.accessToken else {
                print("❌ StravaService: No access token available after refresh attempt")
                throw StravaError.notAuthenticated
            }
            
            guard let url = URL(string: "https://www.strava.com/api/v3/activities/\(id)") else {
                print("❌ StravaService: Invalid URL for activity \(id)")
                throw StravaError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            print("🌐 StravaService: Making request to: \(url)")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ StravaService: Invalid response type for activity \(id)")
                throw StravaError.requestFailed
            }
            
            print("📡 StravaService: Received response with status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 429 {
                // Parse the Retry-After header if present
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                print("⏱️ StravaService: Rate limited (429) for activity \(id), retry after: \(retryAfter ?? 0) seconds")
                throw StravaError.rateLimited(retryAfter: retryAfter)
            } else if httpResponse.statusCode != 200 {
                print("❌ StravaService: HTTP error \(httpResponse.statusCode) for activity \(id)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Response body: \(responseString)")
                }
                throw StravaError.requestFailed
            }
            
            print("✅ StravaService: Successfully received detailed activity data (\(data.count) bytes)")
            
            // Log relevant JSON fields for debugging (only timezone info)
            if let jsonString = String(data: data, encoding: .utf8) {
                let relevantFields = ["start_date", "start_date_local", "timezone", "utc_offset"]
                print("📄 Relevant activity fields:")
                for field in relevantFields {
                    if let range = jsonString.range(of: "\"\(field)\":") {
                        let startIndex = range.upperBound
                        let searchRange = startIndex..<jsonString.endIndex
                        if let commaRange = jsonString.range(of: ",", range: searchRange) {
                            let value = String(jsonString[startIndex..<commaRange.lowerBound])
                            print("  - \(field): \(value)")
                        }
                    }
                }
            }
            
            do {
                let detailedActivity = try JSONDecoder().decode(StravaDetailedActivity.self, from: data)
                print("✅ StravaService: Successfully decoded detailed activity")
                return detailedActivity
            } catch {
                print("❌ StravaService: Failed to decode detailed activity: \(error)")
                throw StravaError.decodingError
            }
        }
    }
    
    func fetchActivityStreams(id: Int, types: [String] = ["latlng", "time"]) async throws -> [StravaStream] {
        return try await performRequestWithRetry { [self] in
            // Ensure we have a valid access token
            try await self.ensureValidAccessToken()
            
            guard let accessToken = self.accessToken else {
                throw StravaError.notAuthenticated
            }
            
            let typeString = types.joined(separator: ",")
            var components = URLComponents(string: "https://www.strava.com/api/v3/activities/\(id)/streams")
            components?.queryItems = [
                URLQueryItem(name: "keys", value: typeString),
                URLQueryItem(name: "key_by_type", value: "true")
            ]
            
            guard let url = components?.url else {
                throw StravaError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaError.requestFailed
            }
            
            if httpResponse.statusCode == 429 {
                // Parse the Retry-After header if present
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                print("⏱️ StravaService: Rate limited (429) for activity streams \(id), retry after: \(retryAfter ?? 0) seconds")
                throw StravaError.rateLimited(retryAfter: retryAfter)
            } else if httpResponse.statusCode == 404 {
                // 404 means the stream data doesn't exist for this activity
                print("📊 StravaService: No stream data available for activity \(id) (404)")
                return [] // Return empty array instead of throwing
            } else if httpResponse.statusCode != 200 {
                throw StravaError.requestFailed
            }
            
            // Try to decode the stream data
            do {
                // First, try to decode as array format (when key_by_type=false)
                return try JSONDecoder().decode([StravaStream].self, from: data)
            } catch {
                // If that fails, try to decode as dictionary format (when key_by_type=true)
                do {
                    // Create a custom decoder for the dictionary format
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                    var streams: [StravaStream] = []
                    
                    for (streamType, streamData) in json {
                        if let streamDict = streamData as? [String: Any],
                           let dataArray = streamDict["data"] as? [Any] {
                            
                            // Convert the data array to StreamData enum values
                            let streamDataValues = dataArray.compactMap { element -> StreamData? in
                                if let coordArray = element as? [Double], coordArray.count == 2 {
                                    return .coordinate(coordArray)
                                } else if let doubleVal = element as? Double {
                                    return .double(doubleVal)
                                } else if let intVal = element as? Int {
                                    return .int(intVal)
                                }
                                return nil
                            }
                            
                            let stream = StravaStream(
                                type: streamType,
                                data: streamDataValues,
                                seriesType: streamDict["series_type"] as? String ?? "distance",
                                originalSize: streamDict["original_size"] as? Int ?? streamDataValues.count,
                                resolution: streamDict["resolution"] as? String ?? "high"
                            )
                            
                            streams.append(stream)
                        }
                    }
                    
                    print("✅ StravaService: Successfully decoded stream data using dictionary format for activity \(id) - found \(streams.count) streams")
                    return streams
                } catch {
                    // If both formats fail, log the raw data for debugging and return empty array
                    if let dataString = String(data: data, encoding: .utf8) {
                        print("📊 StravaService: Failed to decode stream data for activity \(id). Raw response: \(dataString.prefix(300))")
                    }
                    print("📊 StravaService: Stream decode error (both formats): \(error)")
                    return [] // Return empty array instead of throwing to prevent retries
                }
            }
        }
    }
    
    // MARK: - Retry Logic with Exponential Backoff
    
    /// Performs a network request with exponential backoff retry logic
    /// - Parameter operation: The async operation to retry
    /// - Returns: The result of the operation
    /// - Throws: The final error after all retries are exhausted
    private func performRequestWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let maxRetries = 3
        let baseDelay: TimeInterval = 1.0 // Start with 1 second
        let maxDelay: TimeInterval = 30.0 // Cap at 30 seconds
        let jitterRange: TimeInterval = 0.25 // ±25% jitter to avoid thundering herd
        
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                let result = try await operation()
                if attempt > 0 {
                    print("✅ StravaService: Request succeeded on attempt \(attempt + 1)")
                }
                return result
            } catch {
                lastError = error
                let isLastAttempt = attempt == maxRetries - 1
                
                // Don't retry for certain errors
                switch error {
                case StravaError.notAuthenticated, StravaError.invalidURL, StravaError.decodingError:
                    print("❌ StravaService: Non-retryable error on attempt \(attempt + 1): \(error.localizedDescription)")
                    throw error
                case StravaError.rateLimited(let retryAfter):
                    if isLastAttempt {
                        print("❌ StravaService: Rate limit reached, no more retries")
                        throw error
                    }
                    // Use Strava's suggested retry delay if provided, otherwise use exponential backoff
                    let delaySeconds = TimeInterval(retryAfter ?? Int(baseDelay * pow(2.0, Double(attempt))))
                    let cappedDelay = min(delaySeconds, maxDelay)
                    print("⏳ StravaService: Rate limited, waiting \(cappedDelay)s before retry \(attempt + 1)/\(maxRetries)")
                    try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
                case StravaError.requestFailed:
                    if isLastAttempt {
                        print("❌ StravaService: Request failed after \(maxRetries) attempts")
                        throw error
                    }
                    // Exponential backoff with jitter for network errors
                    let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
                    let jitter = Double.random(in: -jitterRange...jitterRange) * exponentialDelay
                    let delayWithJitter = exponentialDelay + jitter
                    let cappedDelay = min(max(delayWithJitter, 0.1), maxDelay) // Minimum 0.1s, maximum 30s
                    
                    print("⏳ StravaService: Request failed (attempt \(attempt + 1)/\(maxRetries)), retrying in \(String(format: "%.1f", cappedDelay))s")
                    try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
                default:
                    if isLastAttempt {
                        print("❌ StravaService: Unknown error after \(maxRetries) attempts: \(error.localizedDescription)")
                        throw error
                    }
                    print("⚠️ StravaService: Unknown error on attempt \(attempt + 1): \(error.localizedDescription)")
                    let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
                    let cappedDelay = min(exponentialDelay, maxDelay)
                    try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
                }
            }
        }
        
        // This should never be reached due to the isLastAttempt checks above, but just in case
        throw lastError ?? StravaError.requestFailed
    }
    
    // MARK: - Token Management
    
    private func ensureValidAccessToken() async throws {
        // Check if token is expired
        if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
            print("🔄 StravaService: Access token expired, refreshing...")
            try await refreshAccessToken()
        } else if accessToken != nil {
            print("✅ StravaService: Access token is still valid")
        } else {
            print("❌ StravaService: No access token available")
            throw StravaError.notAuthenticated
        }
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            print("❌ StravaService: No refresh token available")
            await MainActor.run {
                self.logout()
            }
            throw StravaError.notAuthenticated
        }
        
        print("🔄 StravaService: Refreshing access token...")
        
        guard let url = URL(string: "https://www.strava.com/oauth/token") else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaError.requestFailed
            }
            
            if httpResponse.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(StravaTokenRefreshResponse.self, from: data)
                
                await MainActor.run {
                    self.accessToken = tokenResponse.accessToken
                    self.refreshToken = tokenResponse.refreshToken
                    self.tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
                    
                    // Store the refreshed tokens
                    UserDefaults.standard.set(tokenResponse.accessToken, forKey: "strava_access_token")
                    UserDefaults.standard.set(tokenResponse.refreshToken, forKey: "strava_refresh_token")
                    UserDefaults.standard.set(self.tokenExpiresAt, forKey: "strava_expires_at")
                    
                    print("✅ StravaService: Successfully refreshed access token, expires at: \(self.tokenExpiresAt!)")
                }
                
                // Store to Firebase for cross-device sync
                await self.storeTokensToFirebase(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
                )
            } else {
                print("❌ StravaService: Token refresh failed with status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Response: \(responseString)")
                }
                
                await MainActor.run {
                    self.logout()
                }
                throw StravaError.notAuthenticated
            }
        } catch {
            print("❌ StravaService: Token refresh error: \(error)")
            await MainActor.run {
                self.logout()
            }
            throw StravaError.notAuthenticated
        }
    }
    
    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        athlete = nil
        isAuthenticated = false
        clearStoredCredentials()
    }
    
    private func storeCredentials(_ authResponse: StravaAuthResponse) {
        UserDefaults.standard.set(authResponse.accessToken, forKey: "strava_access_token")
        UserDefaults.standard.set(authResponse.refreshToken, forKey: "strava_refresh_token")
        
        // expiresAt is a Unix timestamp, convert to Date
        let expirationDate = Date(timeIntervalSince1970: TimeInterval(authResponse.expiresAt))
        UserDefaults.standard.set(expirationDate, forKey: "strava_expires_at")
        
        if let athleteData = try? JSONEncoder().encode(authResponse.athlete) {
            UserDefaults.standard.set(athleteData, forKey: "strava_athlete")
        }
        
        print("💾 StravaService: Stored credentials, expires at: \(expirationDate)")
        
        // Store to Firebase for cross-device sync
        storeCredentialsToFirebase(authResponse)
    }
    
    private func storeCredentialsToFirebase(_ authResponse: StravaAuthResponse) {
        Task {
            await storeTokensToFirebase(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date(timeIntervalSince1970: TimeInterval(authResponse.expiresAt))
            )
        }
    }
    
    // CRITICAL FIX: Upload tokens to Firebase when Firebase auth becomes available
    func uploadLocalTokensIfFirebaseAvailable() async {
        // Only proceed if we have local tokens but Firebase user is now available
        guard Auth.auth().currentUser != nil,
              let localAccessToken = UserDefaults.standard.string(forKey: "strava_access_token"),
              let localRefreshToken = UserDefaults.standard.string(forKey: "strava_refresh_token"),
              let localExpiresAt = UserDefaults.standard.object(forKey: "strava_expires_at") as? Date else {
            return
        }
        
        print("🔄 StravaService: Firebase user detected, uploading local tokens...")
        await storeTokensToFirebase(
            accessToken: localAccessToken,
            refreshToken: localRefreshToken,
            expiresAt: localExpiresAt
        )
        print("✅ StravaService: Local tokens uploaded to Firebase")
    }
    
    private func loadStoredCredentials() {
        print("🔍 StravaService: Loading stored credentials...")
        
        accessToken = UserDefaults.standard.string(forKey: "strava_access_token")
        refreshToken = UserDefaults.standard.string(forKey: "strava_refresh_token")
        tokenExpiresAt = UserDefaults.standard.object(forKey: "strava_expires_at") as? Date
        
        if let athleteData = UserDefaults.standard.data(forKey: "strava_athlete"),
           let storedAthlete = try? JSONDecoder().decode(StravaAthlete.self, from: athleteData) {
            athlete = storedAthlete
        }
        
        print("🔍 StravaService: Local credentials status:")
        print("  - Access token exists: \(accessToken != nil)")
        print("  - Refresh token exists: \(refreshToken != nil)")
        print("  - Athlete data exists: \(athlete != nil)")
        
        // Check if token is expired
        if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
            print("⚠️ StravaService: Stored token is expired, will need refresh")
            // Don't set isAuthenticated to false here - we'll try to refresh when needed
        }
        
        isAuthenticated = accessToken != nil
        
        if let expiresAt = tokenExpiresAt {
            print("📅 StravaService: Loaded credentials, expires at: \(expiresAt)")
        } else {
            print("📅 StravaService: No expiration date found in local storage")
        }
        
        // CRITICAL: Also try to load from Firebase if Firebase user is available
        Task {
            // Check if Firebase user is available and try to sync
            if Auth.auth().currentUser != nil {
                print("🔄 StravaService: Firebase user detected, attempting to sync tokens...")
                await syncWithFirebase()
            } else {
                print("📱 StravaService: No Firebase user, skipping Firebase token sync")
            }
        }
    }
    
    private func clearStoredCredentials() {
        UserDefaults.standard.removeObject(forKey: "strava_access_token")
        UserDefaults.standard.removeObject(forKey: "strava_refresh_token")
        UserDefaults.standard.removeObject(forKey: "strava_expires_at")
        UserDefaults.standard.removeObject(forKey: "strava_athlete")
        print("🗑️ StravaService: Cleared stored credentials")
        
        // Also clear from Firebase
        Task {
            await clearTokensFromFirebase()
        }
    }
    
    // MARK: - Firebase Token Sync
    
    private func storeTokensToFirebase(accessToken: String, refreshToken: String, expiresAt: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("📱 StravaService: No Firebase user, skipping token sync")
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
            
            // Store to Firebase (encrypted for main app security)
            try await FirestoreService.shared.storeEncryptedToken(
                userId: userId,
                service: "strava",
                token: encryptedToken
            )
            
            // ALSO store unencrypted copy specifically for public homepage endpoint
            // This only affects the public endpoint, not the main app security
            try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("tokens")
                .document("strava_public")
                .setData([
                    "accessToken": accessToken,
                    "refreshToken": refreshToken,
                    "expiresAt": Timestamp(date: expiresAt),
                    "service": "strava",
                    "isPublicEndpoint": true,
                    "createdAt": Timestamp(date: Date()),
                    "athleteId": self.athlete?.id ?? 0
                ], merge: true)
            
            print("✅ StravaService: Tokens stored to Firebase (encrypted + public endpoint copy)")
        } catch {
            print("❌ StravaService: Failed to store tokens to Firebase: \(error.localizedDescription)")
        }
    }
    
    // One-time migration function to create unencrypted tokens for homepage endpoint
    func migrateToPublicTokens() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ StravaService: No Firebase user for migration")
            return
        }
        
        do {
            // Check if public tokens already exist
            let publicTokenDoc = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("tokens")
                .document("strava_public")
                .getDocument()
            
            if publicTokenDoc.exists {
                print("✅ StravaService: Public tokens already exist, skipping migration")
                return
            }
            
            // Load existing encrypted tokens
            guard let encryptedToken = try await FirestoreService.shared.getEncryptedToken(
                userId: userId,
                service: "strava"
            ) else {
                print("❌ StravaService: No encrypted tokens found for migration")
                return
            }
            
            // Decrypt existing tokens
            let decryptedString = try TokenEncryption.shared.decryptTokenString(
                encryptedToken: encryptedToken,
                userId: userId
            )
            let tokens = try JSONDecoder().decode(StorableTokens.self, from: Data(decryptedString.utf8))
            
            // Store unencrypted copy for public endpoint
            try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("tokens")
                .document("strava_public")
                .setData([
                    "accessToken": tokens.accessToken,
                    "refreshToken": tokens.refreshToken,
                    "expiresAt": tokens.expiresAt != nil ? Timestamp(date: tokens.expiresAt!) : nil,
                    "service": "strava",
                    "isPublicEndpoint": true,
                    "migratedAt": Timestamp(date: Date()),
                    "athleteId": self.athlete?.id ?? 0
                ], merge: true)
            
            print("✅ StravaService: Successfully migrated tokens for public endpoint")
        } catch {
            print("❌ StravaService: Migration failed: \(error.localizedDescription)")
        }
    }
    
    private func loadTokensFromFirebase() async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("📱 StravaService: No Firebase user, skipping token load")
            return false
        }
        
        do {
            // Load encrypted tokens from Firebase
            guard let encryptedToken = try await FirestoreService.shared.getEncryptedToken(
                userId: userId,
                service: "strava"
            ) else {
                print("📱 StravaService: No stored tokens in Firebase")
                return false
            }
            
            // Decrypt the tokens
            let tokensString = try TokenEncryption.shared.decryptTokenString(
                encryptedToken: encryptedToken,
                userId: userId
            )
            
            guard let tokensData = tokensString.data(using: .utf8),
                  let tokens = try? JSONDecoder().decode(StorableTokens.self, from: tokensData) else {
                print("❌ StravaService: Failed to decode tokens from Firebase")
                return false
            }
            
            // Update local credentials
            await MainActor.run {
                self.accessToken = tokens.accessToken
                self.refreshToken = tokens.refreshToken
                self.tokenExpiresAt = tokens.expiresAt
                self.isAuthenticated = true
            }
            
            // Store locally as backup
            UserDefaults.standard.set(tokens.accessToken, forKey: "strava_access_token")
            UserDefaults.standard.set(tokens.refreshToken ?? "", forKey: "strava_refresh_token")
            if let expiresAt = tokens.expiresAt {
                UserDefaults.standard.set(expiresAt, forKey: "strava_expires_at")
            }
            
            // Try to load athlete data from UserDefaults if available
            if let athleteData = UserDefaults.standard.data(forKey: "strava_athlete"),
               let storedAthlete = try? JSONDecoder().decode(StravaAthlete.self, from: athleteData) {
                await MainActor.run {
                    self.athlete = storedAthlete
                }
                print("✅ StravaService: Athlete data loaded from UserDefaults")
            } else {
                // If no local athlete data, fetch it from API
                do {
                    try await fetchAthleteData()
                    print("✅ StravaService: Athlete data fetched from API")
                } catch {
                    print("⚠️ StravaService: Failed to fetch athlete data: \(error)")
                }
            }
            
            print("✅ StravaService: Tokens loaded from Firebase")
            
            // Check if tokens are expired
            if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
                print("⚠️ StravaService: Loaded tokens are expired, attempting refresh...")
                do {
                    try await refreshAccessToken()
                    print("✅ StravaService: Successfully refreshed expired tokens")
                    return true
                } catch {
                    print("❌ StravaService: Failed to refresh tokens: \(error)")
                    await MainActor.run {
                        self.clearStoredCredentials()
                        self.isAuthenticated = false
                    }
                    return false
                }
            }
            
            // Validate the loaded tokens by attempting a simple API call
            let isValid = await validateTokens()
            if !isValid {
                print("⚠️ StravaService: Loaded tokens appear to be invalid, attempting refresh...")
                // Try to refresh if we have a refresh token
                if refreshToken != nil {
                    do {
                        try await refreshAccessToken()
                        print("✅ StravaService: Successfully refreshed invalid tokens")
                        return true
                    } catch {
                        print("❌ StravaService: Failed to refresh tokens: \(error)")
                        await MainActor.run {
                            self.clearStoredCredentials()
                            self.isAuthenticated = false
                        }
                        return false
                    }
                } else {
                    print("❌ StravaService: No refresh token available, clearing...")
                    await MainActor.run {
                        self.clearStoredCredentials()
                        self.isAuthenticated = false
                    }
                    return false
                }
            }
            
            return true
        } catch {
            print("❌ StravaService: Failed to load tokens from Firebase: \(error.localizedDescription)")
            
            // If it's a CryptoKit error (likely due to old token format), clear the corrupted tokens
            if error.localizedDescription.contains("CryptoKit") {
                print("🔧 StravaService: Detected old token format, clearing corrupted tokens...")
                await clearTokensFromFirebase()
            }
            
            return false
        }
    }
    
    // Fetch athlete data from Strava API
    private func fetchAthleteData() async throws {
        guard let accessToken = accessToken else {
            throw StravaError.notAuthenticated
        }
        
        let url = URL(string: "https://www.strava.com/api/v3/athlete")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.requestFailed
        }
        
        if httpResponse.statusCode == 200 {
            let fetchedAthlete = try JSONDecoder().decode(StravaAthlete.self, from: data)
            
            await MainActor.run {
                self.athlete = fetchedAthlete
            }
            
            // Store athlete data locally for future use
            if let athleteData = try? JSONEncoder().encode(fetchedAthlete) {
                UserDefaults.standard.set(athleteData, forKey: "strava_athlete")
            }
            
            print("✅ StravaService: Fetched and stored athlete data for \(fetchedAthlete.firstname ?? "Unknown") \(fetchedAthlete.lastname ?? "")")
        } else {
            print("❌ StravaService: Failed to fetch athlete data - Status: \(httpResponse.statusCode)")
            throw StravaError.requestFailed
        }
    }
    
    // Validate tokens by making a simple API call
    private func validateTokens() async -> Bool {
        guard let accessToken = accessToken else { return false }
        
        let url = URL(string: "https://www.strava.com/api/v3/athlete")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let isValid = httpResponse.statusCode == 200
                print("🔐 StravaService: Token validation - Status: \(httpResponse.statusCode), Valid: \(isValid)")
                return isValid
            }
        } catch {
            print("❌ StravaService: Token validation failed: \(error.localizedDescription)")
        }
        
        return false
    }
    
    private func clearTokensFromFirebase() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await FirestoreService.shared.deleteToken(userId: userId, service: "strava")
            print("✅ StravaService: Tokens cleared from Firebase")
        } catch {
            print("❌ StravaService: Failed to clear tokens from Firebase: \(error.localizedDescription)")
        }
    }
    
    // Public method to sync tokens when Firebase user signs in
    public func syncWithFirebase() async {
        print("🔄 StravaService: Syncing with Firebase...")
        print("🔍 StravaService: Current authentication state before sync: \(isAuthenticated)")
        
        // Try to load tokens from Firebase first
        if await loadTokensFromFirebase() {
            print("✅ StravaService: Successfully loaded tokens from Firebase")
            // Successfully loaded from Firebase - update authentication state
            await MainActor.run {
                self.isAuthenticated = self.accessToken != nil
            }
            print("🔍 StravaService: Authentication state after Firebase load: \(isAuthenticated)")
            return
        }
        
        print("📱 StravaService: No tokens found in Firebase, checking local tokens...")
        
        // If no Firebase tokens but we have local tokens, upload to Firebase
        if let localAccessToken = UserDefaults.standard.string(forKey: "strava_access_token"),
           let localRefreshToken = UserDefaults.standard.string(forKey: "strava_refresh_token"),
           let localExpiresAt = UserDefaults.standard.object(forKey: "strava_expires_at") as? Date {
            
            print("📤 StravaService: Found local tokens, uploading to Firebase...")
            await storeTokensToFirebase(
                accessToken: localAccessToken,
                refreshToken: localRefreshToken,
                expiresAt: localExpiresAt
            )
            
            // Ensure authentication state reflects local tokens
            await MainActor.run {
                self.accessToken = localAccessToken
                self.refreshToken = localRefreshToken
                self.tokenExpiresAt = localExpiresAt
                self.isAuthenticated = true
            }
            print("✅ StravaService: Local tokens uploaded to Firebase and authentication restored")
        } else {
            print("📱 StravaService: No local tokens found either - user needs to reconnect")
        }
        
        print("🔍 StravaService: Final authentication state after sync: \(isAuthenticated)")
    }
}

enum StravaError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case requestFailed
    case decodingError
    case rateLimited(retryAfter: Int?)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "not authenticated with strava"
        case .invalidURL:
            return "invalid url"
        case .requestFailed:
            return "request failed"
        case .decodingError:
            return "failed to decode response"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "strava api rate limit reached. please try again in \(retryAfter) seconds."
            } else {
                return "strava api rate limit reached. please try again in a few minutes."
            }
        }
    }
}
