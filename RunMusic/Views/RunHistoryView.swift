import SwiftUI
import CoreLocation
import os.log

struct RunHistoryView: View {
    private let logger = Logger(subsystem: "com.charliekubal.runmusic", category: "RunHistoryView")
    
    // Optional binding for deep-linking to specific runs
    @Binding var selectedRunId: String?
    
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @StateObject private var userPreferences = UserPreferences.shared
    // Use FirestoreService directly for now instead of separate cache service
    private let firestoreService = FirestoreService.shared
    @State private var runs: [RunActivity] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingRateLimitAlert = false
    @State private var rateLimitRetryAfter: Int?
    @State private var isUsingCachedData = false
    @State private var refreshTimer: Timer?
    @State private var showSignInPrompt = false
    @State private var hasShownMultipleRunsPrompt = false
    @State private var currentPage = 1
    @State private var hasMoreRuns = true
    @State private var showFirebasePrompt = false
    @State private var hasExistingFirebaseAccount = false
    @State private var userUsername: String?
    @State private var selectedRun: RunActivity?
    @State private var navigationPath = NavigationPath()
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    
    var body: some View {
        let backgroundColors = [
            Color.orange.opacity(0.05),
            Color.pink.opacity(0.03),
            Color.white
        ]
        
        return NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                mainContentView
            }
            .navigationTitle(userUsername != nil ? "@\(userUsername!)'s runs" : "runs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSignInPrompt) {
            SignInPromptView(
                context: .multipleRuns,
                onSignIn: {
                    showSignInPrompt = false
                    Task {
                        await firebaseAuth.signInWithGoogle()
                    }
                },
                onDismiss: {
                    showSignInPrompt = false
                },
                onContinueWithoutSignIn: {
                    showSignInPrompt = false
                }
            )
        }
        .sheet(isPresented: $showFirebasePrompt) {
            LoginPromptView {
                showFirebasePrompt = false
            }
            .environmentObject(firebaseAuth)
        }
        .alert("strava api limit reached", isPresented: $showingRateLimitAlert) {
            Button("got it") { }
        } message: {
            if let retryAfter = rateLimitRetryAfter, retryAfter > 0 {
                Text("you've reached the strava api limit. please try again in \(retryAfter) seconds.")
            } else {
                Text("you've reached the strava api limit. please try again in a few minutes.")
            }
        }
        .refreshable {
            await loadRuns(isRefresh: true)
        }
        .onAppear {
            logger.info("RunHistoryView appeared - Spotify authenticated: \(spotifyService.isAuthenticated)")
            
            // Debug Spotify import status
            spotifyService.debugImportStatus()
            
            Task {
                await loadRuns()
                
                // Load username if Firebase authenticated
                if firebaseAuth.isAuthenticated, let userId = firebaseAuth.currentUser?.uid {
                    if let profile = try? await FirestoreService.shared.getUserProfile(userId: userId) {
                        userUsername = profile.username
                    }
                    
                    // CRITICAL: Load Spotify tokens from Firebase on app startup
                    print("🔄 Loading Spotify tokens from Firebase on app startup...")
                    await spotifyService.syncWithFirebase()
                }
                
                // Note: Only use actual usernames from Firebase for @username format
                // Strava doesn't provide username data suitable for this format
                
                // Check for existing Firebase account based on Strava ID
                if stravaService.isAuthenticated, let stravaUserId = stravaService.athlete?.id {
                    await checkForExistingFirebaseAccount(stravaUserId: String(stravaUserId))
                }
                
                // Show sign-in prompt for multiple runs (only once)
                // Only show after both Strava and Spotify are connected
                if !hasShownMultipleRunsPrompt && 
                   runs.count >= 3 && 
                   !firebaseAuth.isAuthenticated &&
                   stravaService.isAuthenticated &&
                   spotifyService.isAuthenticated {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        hasShownMultipleRunsPrompt = true
                        showSignInPrompt = true
                    }
                }
            }
        }
        .onChange(of: spotifyService.isAuthenticated) { oldValue, newValue in
            // Refresh runs when Spotify authentication state changes from false to true
            if !oldValue && newValue {
                logger.info("Spotify connected - refreshing runs to show music indicators")
                Task {
                    await loadRuns(isRefresh: true)
                }
            }
        }
        .onChange(of: selectedRunId) { _, runId in
            // Handle deep-link navigation to specific runs
            if let runId = runId {
                print("📱 Deep-linking to run: \(runId)")
                // Find the run in our current list
                if let run = runs.first(where: { $0.id == runId }) {
                    selectedRun = run
                } else {
                    // Run not in current list, might need to fetch it
                    print("⚠️ Run \(runId) not found in current list")
                }
                // Clear the selectedRunId after handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedRunId = nil
                }
            }
        }
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                RunDetailView(run: run)
            }
        }
    }
    
    private var mainContentView: some View {
        VStack {
            firebaseBannerSection
            stravaBannerSection
            spotifyBannerSection
            firebaseUpsellBannerSection
            runListSection
        }
    }
    
    private var firebaseBannerSection: some View {
        Group {
            // Show Firebase prompt only after BOTH Strava and Spotify are connected
            // and user doesn't already have a Firebase account
            let shouldShowFirebaseBanner = stravaService.isAuthenticated && 
                                          spotifyService.isAuthenticated && 
                                          !firebaseAuth.isAuthenticated &&
                                          hasExistingFirebaseAccount
            
            if shouldShowFirebaseBanner {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("welcome back! sign in to sync")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("we found your existing account")
                                .font(.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("sign in") {
                            showFirebasePrompt = true
                        }
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(20)
                    }
                    .padding(16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var stravaBannerSection: some View {
        Group {
            // Show Strava reconnect banner if user is not authenticated but has cached runs
            let shouldShowStravaBanner = !stravaService.isAuthenticated && !runs.isEmpty
            
            if shouldShowStravaBanner {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("reconnect strava")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("your session expired - reconnect to load new runs")
                                .font(.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("reconnect") {
                            if let authURL = stravaService.authURL {
                                print("🟠 RunHistoryView: Opening Strava auth for reconnection")
                                UIApplication.shared.open(authURL)
                            }
                        }
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(20)
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var spotifyBannerSection: some View {
        Group {
            // Show banner if Strava is connected but Spotify is not, OR if user had Spotify before but now disconnected
            let shouldShowSpotifyBanner = stravaService.isAuthenticated && !spotifyService.isAuthenticated
            let hasSpotifyHistory = !runs.isEmpty && runs.contains { !($0.spotifyTracks?.isEmpty ?? true) }
            let isSpotifyReconnect = shouldShowSpotifyBanner && hasSpotifyHistory
            
            if shouldShowSpotifyBanner {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isSpotifyReconnect ? "reconnect spotify" : "connect spotify for music data")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(isSpotifyReconnect ? "your session expired - reconnect to see music" : "see what songs powered your runs")
                                .font(.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(isSpotifyReconnect ? "reconnect" : "connect") {
                            // DEBUG: Clear state first if there's stale data
                            spotifyService.debugClearAllAuth()
                            
                            if let authURL = spotifyService.authURL {
                                print("🔵 RunHistoryView: Opening Spotify auth in system Safari")
                                UIApplication.shared.open(authURL)
                            }
                        }
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(20)
                    }
                    .padding(16)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var firebaseUpsellBannerSection: some View {
        Group {
            // Show Google/Apple upsell ONLY when both Strava AND Spotify are connected
            // but user hasn't created a Firebase account yet
            let shouldShowUpsell = stravaService.isAuthenticated && 
                                 spotifyService.isAuthenticated && 
                                 !firebaseAuth.isAuthenticated
            
            if shouldShowUpsell {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("save your runs & settings")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("create an account via apple or google to sync across devices")
                                .font(.custom("Helvetica Neue", size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("sign up") {
                            showFirebasePrompt = true
                        }
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(20)
                    }
                    .padding(16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var runListSection: some View {
        return Group {
            if isLoading {
                LottieLoadingStateView(message: "loading runs...", size: 40)
                    .transition(.opacity.combined(with: .scale))
            } else if runs.isEmpty {
                VStack(spacing: 24) {
                    // Animated running icon with gradient
                    let circleGradientColors = [Color.orange.opacity(0.2), Color.pink.opacity(0.1)]
                    let circleGradient = LinearGradient(
                        colors: circleGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    ZStack {
                        Circle()
                            .fill(circleGradient)
                            .frame(width: 120, height: 120)
                        
                        let iconGradientColors = [Color.orange, Color.pink]
                        let iconGradient = LinearGradient(
                            colors: iconGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        Image(systemName: "figure.run")
                            .font(.system(size: 50))
                            .foregroundStyle(iconGradient)
                    }
                    
                    VStack(spacing: 12) {
                        Text("no runs found")
                            .font(.custom("Helvetica Neue", size: 22))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("your strava running activities will appear here once you complete a run.")
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            
                        // Spotify connection prompt in empty state
                        if !spotifyService.isAuthenticated {
                            SpotifyConnectionBanner(context: .generalMusic)
                                .padding(.top, 20)
                        }
                    }
                    
                    Button {
                        Task {
                            await loadRuns()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout)
                            Text("refresh")
                                .font(.custom("Helvetica Neue", size: 16))
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(1.0)
                }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(runs, id: \.id) { run in
                                Button(action: {
                                    HapticFeedbackService.shared.lightTap()
                                    selectedRun = run
                                }) {
                                    RunRowView(run: run)
                                        .id(run.id) // Explicit stable ID
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                            removal: .opacity.combined(with: .scale(scale: 0.8))
                                        ))
                                        .animation(.easeInOut(duration: 0.3), value: run.id)
                                        .onAppear {
                                            // Debug logging for blank card detection  
                                            let hasPhoto = run.backgroundPhoto != nil
                                            let hasPhotoData = run.backgroundPhoto?.photoData != nil
                                            let hasRoute = !run.routeCoordinates.isEmpty
                                            print("🐛 CARD DEBUG: '\(run.name)' - Photo: \(hasPhoto), Data: \(hasPhotoData), Route: \(hasRoute)")
                                            
                                            // Calculate Power Song on-demand if not already calculated
                                            if run.powerSong == nil && !run.routeCoordinates.isEmpty && !(run.spotifyTracks?.isEmpty ?? true) {
                                                Task.detached(priority: .userInitiated) {
                                                    await calculatePowerSongOnDemand(for: run)
                                                }
                                            }
                                            
                                            // Load more runs when approaching the end
                                            if run.id == runs.last?.id && hasMoreRuns && !isLoadingMore {
                                                Task {
                                                    await loadMoreRuns()
                                                }
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    RunContextMenu(run: run) {
                                        // Refresh the run list after any context menu action
                                        Task {
                                            await loadRuns(isRefresh: true)
                                        }
                                    }
                                }
                            }
                            
                            // Spotify History Import Banner for Old Runs
                            SpotifyHistoryListBanner(runs: runs)
                            
                            // Load More section
                            if hasMoreRuns {
                                if isLoadingMore {
                                    VStack(spacing: 12) {
                                        CompactLottieRunner(size: 40)
                                        Text("loading more runs...")
                                            .font(.custom("Helvetica Neue", size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 16)
                                } else {
                                    Button(action: {
                                        Task {
                                            await loadMoreRuns()
                                        }
                                    }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .font(.callout)
                                                Text("load more runs")
                                                    .font(.custom("Helvetica Neue", size: 15))
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.orange.opacity(0.1), Color.pink.opacity(0.1)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .foregroundColor(.primary)
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.3)],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                        }
                                        .padding(.vertical, 16)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    
    // MARK: - Helper Functions
    
    private func calculatePowerSongOnDemand(for run: RunActivity) async {
        guard let activityId = Int(run.id) else { 
            logger.info("⚠️ Cannot calculate Power Song: invalid activity ID for run \(run.name)")
            return 
        }
        
        logger.info("🔥 Calculating Power Song on-demand for '\(run.name)'...")
        
        do {
            // Fetch detailed streams for Power Song calculation
            let streams = try await stravaService.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
            
            await MainActor.run {
                // Find the run in our array and update it
                if let runIndex = self.runs.firstIndex(where: { $0.id == run.id }) {
                    var updatedRun = self.runs[runIndex]
                    
                    // Calculate Power Song using DataConversionService
                    DataConversionService.shared.calculatePowerSong(for: &updatedRun, from: streams)
                    
                    // Update the run in our array to trigger UI refresh
                    self.runs[runIndex] = updatedRun
                    
                    // Log results
                    if let powerSong = updatedRun.powerSong {
                        let pace = updatedRun.powerSongPacePerMile ?? "Unknown"
                        logger.info("🔥 ON-DEMAND POWER SONG: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace) per mile")
                    } else {
                        logger.info("💭 No Power Song calculated for '\(run.name)' (no suitable data)")
                    }
                    
                    // Cache the updated run with Power Song
                    if let userId = firebaseAuth.currentUser?.uid {
                        Task {
                            do {
                                let cachedRun = CachedRunData(from: updatedRun)
                                try await firestoreService.storeCachedRun(userId: userId, run: cachedRun)
                                logger.info("💾 Cached Power Song for '\(updatedRun.name)'")
                            } catch {
                                logger.error("Failed to cache Power Song for \(updatedRun.id): \(error)")
                            }
                        }
                    }
                }
            }
        } catch {
            logger.info("⚠️ Could not calculate Power Song for '\(run.name)': \(error.localizedDescription)")
        }
    }
    
    private func checkForExistingFirebaseAccount(stravaUserId: String) async {
        do {
            // Check if there's an existing Firebase account associated with this Strava ID
            let existingAccount = try await firestoreService.checkForExistingAccount(stravaUserId: stravaUserId)
            await MainActor.run {
                hasExistingFirebaseAccount = existingAccount
            }
        } catch {
            print("Error checking for existing Firebase account: \(error)")
        }
    }
    
    private func loadRuns(isRefresh: Bool = false) async {
        logger.info("Starting to load runs (refresh: \(isRefresh))")
        
        if isRefresh {
            currentPage = 1
            hasMoreRuns = true
            isLoading = true
        } else {
            isLoading = true
        }
        errorMessage = nil
        
        // PROGRESSIVE LOADING: Start with 10 runs for better initial display
        await loadRunsForPage(page: 1, isRefresh: isRefresh, initialLoadLimit: 10)
    }
    
    private func loadMoreRuns() async {
        guard hasMoreRuns && !isLoadingMore else { return }
        
        logger.info("Loading more runs (page: \(currentPage + 1))")
        isLoadingMore = true
        currentPage += 1
        
        await loadRunsForPage(page: currentPage, isRefresh: false)
    }
    
    private func loadRunsForPage(page: Int, isRefresh: Bool, initialLoadLimit: Int? = nil) async {
        Task {
            var runActivities: [RunActivity] = []
            var originalStravaActivitiesCount = 0
            var cacheAge: TimeInterval = -Double.infinity
            
            do {
                logger.info("Loading runs for page \(page) (using cache when available)...")
                
                // FIREBASE-FIRST STRATEGY: Always try cache first, especially on refresh
                if page == 1, let userId = firebaseAuth.currentUser?.uid {
                    do {
                        let cacheStatus = try await firestoreService.getCacheStatus(userId: userId)
                        cacheAge = cacheStatus.lastCacheUpdate?.timeIntervalSinceNow ?? -Double.infinity
                        
                        if cacheStatus.totalCachedRuns > 0 {
                            logger.info("📱 Loading cached runs first (count: \(cacheStatus.totalCachedRuns), age: \(abs(cacheAge))s)")
                            let cachedRuns = try await firestoreService.getAllCachedRuns(userId: userId, limit: 20)
                            runActivities = cachedRuns.map { $0.toRunActivity() }
                            
                            // Check and upgrade cached runs for missing features
                            await upgradeCachedRunsIfNeeded(userId: userId, runActivities: &runActivities)
                            
                            // If cache is fresh (< 4 hours), skip API completely during refresh
                            let isCacheFresh = abs(cacheAge) < (4 * 60 * 60) // 4 hours instead of 24
                            if isRefresh && isCacheFresh {
                                logger.info("🚀 REFRESH: Using fresh cache, skipping Strava API to avoid rate limits")
                                originalStravaActivitiesCount = runActivities.count
                                await MainActor.run { self.isUsingCachedData = true }
                            } else if !isRefresh {
                                logger.info("📱 INITIAL LOAD: Using cached runs, will supplement with API if needed")
                                originalStravaActivitiesCount = runActivities.isEmpty ? 0 : 20
                                await MainActor.run { self.isUsingCachedData = true }
                            }
                        }
                    } catch {
                        logger.info("Cache access failed (\(error.localizedDescription)), falling back to API")
                    }
                } else if page > 1 {
                    logger.info("Page \(page): Skipping cache, fetching from Strava API (cache doesn't support pagination)")
                }
                
                // Smart API usage: Only fetch from Strava if really needed
                let shouldFetchFromAPI = runActivities.isEmpty || 
                                       (!isRefresh && page > 1) ||
                                       (isRefresh && abs(cacheAge) > (4 * 60 * 60))
                
                if shouldFetchFromAPI {
                    if isRefresh && !runActivities.isEmpty {
                        logger.info("🔄 REFRESH: Cache is stale (\(abs(cacheAge))s old), checking for new runs...")
                    } else {
                        logger.info("📡 Fetching runs from Strava API...")
                    }
                    let stravaActivities = try await stravaService.fetchActivities(page: page)
                    originalStravaActivitiesCount = stravaActivities.count
                    let runOnlyActivities = stravaActivities.filter { $0.type == "Run" }
                    
                    // PROGRESSIVE LOADING: For initial load, limit to first few runs for speed
                    let activitiesToProcess = if let limit = initialLoadLimit, page == 1 {
                        Array(runOnlyActivities.prefix(limit))
                    } else {
                        runOnlyActivities
                    }
                    
                    logger.info("Processing \(activitiesToProcess.count) activities (out of \(runOnlyActivities.count) total runs, \(stravaActivities.count) total activities)")
                    
                    // Smart merging: If we have cached runs, only process new activities
                    var newActivities: [StravaActivity] = []
                    if !runActivities.isEmpty && isRefresh {
                        // Filter out activities we already have cached
                        let cachedIds = Set(runActivities.map { $0.id })
                        newActivities = activitiesToProcess.filter { !cachedIds.contains(String($0.id)) }
                        logger.info("🔄 REFRESH: Found \(newActivities.count) new activities (out of \(activitiesToProcess.count) total)")
                    } else {
                        newActivities = activitiesToProcess
                    }
                    
                    // Convert to RunActivity objects with basic data first
                    for activity in newActivities {
                        do {
                            let detailedActivity = try await stravaService.fetchDetailedActivity(id: activity.id)
                            let streams = try? await stravaService.fetchActivityStreams(id: activity.id, types: ["latlng", "time", "velocity_smooth"])
                            let runActivity = await DataConversionService.shared.convertStravaActivityToRunActivity(
                                activity,
                                detailedActivity: detailedActivity,
                                streams: streams
                            )
                            
                            // Debug location information
                            logger.info("🌍 LOCATION DEBUG for '\(runActivity.name)':")
                            logger.info("  - City: '\(runActivity.city ?? "nil")'")
                            logger.info("  - Location analysis: '\(runActivity.locationAnalysis?.displayText ?? "nil")'")
                            logger.info("  - Smart location display: '\(runActivity.smartLocationDisplay ?? "nil")'")
                            logger.info("  - Route coordinates: \(runActivity.routeCoordinates.count)")
                            
                            runActivities.append(runActivity)
                        } catch {
                            logger.error("Failed to process activity \(activity.id): \(error)")
                        }
                    }
                    
                    // Skip automatic background loading - user will use "Load More" button instead
                    if let limit = initialLoadLimit, page == 1 && runOnlyActivities.count > limit {
                        logger.info("Found \(runOnlyActivities.count - limit) additional runs available via 'Load More' button")
                    }
                    
                    // Cache the runs in background if user is authenticated
                    if let userId = firebaseAuth.currentUser?.uid {
                        Task {
                            for runActivity in runActivities {
                                do {
                                    let cachedRun = CachedRunData(from: runActivity)
                                    try await firestoreService.storeCachedRun(userId: userId, run: cachedRun)
                                } catch {
                                    logger.error("Failed to cache run \(runActivity.id): \(error)")
                                }
                            }
                            logger.info("Cached \(runActivities.count) runs")
                        }
                    }
                }
                
                logger.info("Got \(runActivities.count) run activities from \(originalStravaActivitiesCount) total Strava activities")
                
                // Set hasMoreRuns based on original Strava activities count, not filtered run count
                // This fixes the issue where users with many non-run activities couldn't load more runs
                if originalStravaActivitiesCount == 0 {
                    hasMoreRuns = false
                    logger.info("No Strava activities returned - no more available")
                } else if originalStravaActivitiesCount < 20 {
                    hasMoreRuns = false
                    logger.info("Page \(page) returned only \(originalStravaActivitiesCount) Strava activities - reached end")
                } else {
                    // Full page of 20 activities returned, likely more available
                    hasMoreRuns = true
                    logger.info("Full page of \(originalStravaActivitiesCount) activities - more likely available")
                }
                
                // Add Spotify tracks to runs
                if spotifyService.isAuthenticated {
                    logger.info("Adding Spotify tracks to \(runActivities.count) runs...")
                    
                    for i in 0..<runActivities.count {
                        let endTime = runActivities[i].date.addingTimeInterval(runActivities[i].elapsedTime)
                        
                        var tracks: [SpotifyTrack] = []
                        
                        // Use optimized SpotifyService method (tries Firebase first with date-range query, then local fallback)
                        tracks = await spotifyService.fetchImportedTracksForTimeRange(
                            startTime: runActivities[i].date,
                            endTime: endTime
                        )
                        
                        // If still no tracks, get recent tracks from API (for recent runs only)
                        if tracks.isEmpty && runActivities[i].date > Date().addingTimeInterval(-7 * 24 * 60 * 60) {
                            do {
                                let recentTracks = try await spotifyService.fetchRecentTracks(limit: 50)
                                tracks = recentTracks.filter { track in
                                    let trackTime = track.playedAt
                                    return trackTime >= runActivities[i].date && trackTime <= endTime
                                }
                            } catch {
                                self.logger.error("❌ Failed to fetch recent tracks for run \(runActivities[i].id): \(error)")
                            }
                        }
                        
                        runActivities[i].spotifyTracks = tracks
                        
                        // Calculate Power Song if we have velocity data - for recent runs to avoid performance issues
                        let runAge = Date().timeIntervalSince(runActivities[i].date)
                        let maxAgeForPowerSong = 30 * 24 * 60 * 60.0 // 30 days in seconds (increased from 7)
                        
                        if let activityId = Int(runActivities[i].id), runAge <= maxAgeForPowerSong {
                            // Process power songs in background to avoid blocking UI
                            Task.detached(priority: .background) {
                                do {
                                    let streams = try await stravaService.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
                                    
                                    await MainActor.run {
                                        DataConversionService.shared.calculatePowerSong(for: &runActivities[i], from: streams)
                                        
                                        // Update the runs array to trigger UI refresh with PowerSong
                                        if let runIndex = self.runs.firstIndex(where: { $0.id == runActivities[i].id }) {
                                            self.runs[runIndex] = runActivities[i]
                                        }
                                        
                                        // Log Power Song results
                                        if let powerSong = runActivities[i].powerSong {
                                            let pace = runActivities[i].powerSongPacePerMile ?? "Unknown"
                                            logger.info("🔥 POWER SONG: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace) per mile")
                                        } else {
                                            logger.info("💭 No Power Song calculated for run \(runActivities[i].name) (no suitable coordinate data)")
                                        }
                                        
                                        // Save the updated run with power song to Firebase cache
                                        Task {
                                            await RunCacheService.shared.cacheRun(runActivities[i])
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        logger.info("⚠️ Skipping Power Song for run \(runActivities[i].id): streams unavailable")
                                        // Continue without Power Song - this is normal for many older runs
                                    }
                                }
                            }
                        } else if runAge > maxAgeForPowerSong {
                            logger.info("⏭️ Skipping Power Song for older run \(runActivities[i].name) (performance optimization)")
                        }
                    }
                    
                    logger.info("Finished adding Spotify tracks to runs")
                }
                
                // Automatically assign photo backgrounds to runs without custom backgrounds
                logger.info("Assigning automatic photo backgrounds to \(runActivities.count) runs...")
                for i in 0..<runActivities.count {
                    // Skip if run already has a custom background photo
                    guard runActivities[i].backgroundPhoto == nil else { continue }
                    
                    // Fetch photos from the run timeframe
                    let photos = await PhotoService.shared.fetchPhotosForRun(
                        date: runActivities[i].date,
                        duration: runActivities[i].elapsedTime
                    )
                    
                    // If photos are available, use the first one as background
                    if let firstPhoto = photos.first {
                        if let photoBackground = await PhotoService.shared.createPhotoBackground(
                            from: firstPhoto,
                            filterType: .blur, // Default filter for auto-assigned backgrounds
                            opacity: 0.6 // Subtle opacity for readability
                        ) {
                            runActivities[i].portraitSettings.backgroundPhoto = photoBackground
                            logger.info("📷 Auto-assigned background photo to run '\(runActivities[i].name)'")
                        } else {
                            logger.info("⚠️ Failed to create background photo for run '\(runActivities[i].name)'")
                        }
                    }
                }
                logger.info("Finished auto-assigning photo backgrounds")
                
                await MainActor.run {
                    if isRefresh || page == 1 {
                        self.runs = runActivities.sorted { $0.date > $1.date }
                    } else {
                        // Append new runs and maintain sort order
                        let newRuns = runActivities.filter { newRun in
                            !self.runs.contains { existingRun in existingRun.id == newRun.id }
                        }
                        self.runs.append(contentsOf: newRuns)
                        self.runs.sort { $0.date > $1.date }
                        
                        // Reset cache indicator when we've fetched fresh data
                        if !newRuns.isEmpty {
                            self.isUsingCachedData = false
                        }
                    }
                    
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    // Handle specific rate limit errors with user-friendly alerts
                    if let stravaError = error as? StravaError,
                       case .rateLimited(let retryAfter) = stravaError {
                        self.rateLimitRetryAfter = retryAfter
                        self.showingRateLimitAlert = true
                        self.errorMessage = nil
                        
                        // If we have cached runs, show them instead of failing completely
                        if !runActivities.isEmpty {
                            logger.info("🚀 RATE LIMIT FALLBACK: Showing cached runs to avoid blank screen")
                            self.runs = runActivities.sorted { $0.date > $1.date }
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { await loadRuns() }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func syncAllRunsToCloud() {
        // Implementation for syncing runs to Firebase
    }
    
    // MARK: - Progressive Loading
    
    private func loadRemainingRunsInBackground(_ activities: [StravaActivity]) async {
        logger.info("Background loading \(activities.count) remaining runs...")
        
        var newRunActivities: [RunActivity] = []
        
        for activity in activities {
            do {
                let detailedActivity = try await stravaService.fetchDetailedActivity(id: activity.id)
                let streams = try? await stravaService.fetchActivityStreams(id: activity.id, types: ["latlng", "time", "velocity_smooth"])
                let runActivity = await DataConversionService.shared.convertStravaActivityToRunActivity(
                    activity,
                    detailedActivity: detailedActivity,
                    streams: streams
                )
                newRunActivities.append(runActivity)
                
                // Add Spotify tracks if authenticated
                if spotifyService.isAuthenticated {
                    await addSpotifyTracksToRun(&newRunActivities[newRunActivities.count - 1])
                }
                
            } catch {
                logger.error("Failed to process background activity \(activity.id): \(error)")
            }
        }
        
        // Update UI with new runs
        await MainActor.run {
            // Add new runs to existing list and maintain sort order
            self.runs.append(contentsOf: newRunActivities)
            self.runs.sort { $0.date > $1.date }
            
            logger.info("Background loading complete - added \(newRunActivities.count) runs")
        }
        
        // Cache the new runs in background if user is authenticated
        if let userId = firebaseAuth.currentUser?.uid {
            for runActivity in newRunActivities {
                do {
                    let cachedRun = CachedRunData(from: runActivity)
                    try await firestoreService.storeCachedRun(userId: userId, run: cachedRun)
                } catch {
                    logger.error("Failed to cache background run \(runActivity.id): \(error)")
                }
            }
        }
    }
    
    private func addSpotifyTracksToRun(_ run: inout RunActivity) async {
        let endTime = run.date.addingTimeInterval(run.elapsedTime)
        
        // Use optimized SpotifyService method
        let tracks = await spotifyService.fetchImportedTracksForTimeRange(
            startTime: run.date,
            endTime: endTime
        )
        
        run.spotifyTracks = tracks
        
        // Calculate Power Song for recent runs
        let runAge = Date().timeIntervalSince(run.date)
        let maxAgeForPowerSong = 30 * 24 * 60 * 60.0 // 30 days
        
        if let activityId = Int(run.id), runAge <= maxAgeForPowerSong {
            do {
                let streams = try await stravaService.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
                DataConversionService.shared.calculatePowerSong(for: &run, from: streams)
            } catch {
                // Continue without Power Song - this is normal for many runs
            }
        }
    }
    
    // MARK: - Cache Upgrade System
    
    private func upgradeCachedRunsIfNeeded(userId: String, runActivities: inout [RunActivity]) async {
        let currentCacheVersion = 4 // Should match FirestoreService.CachedRunData.cacheVersion
        var runsNeedingUpgrade: [(Int, RunActivity, [String])] = [] // (index, run, missing features)
        
        // Check each run for missing features
        for (index, run) in runActivities.enumerated() {
            var missingFeatures: [String] = []
            
            // Check for missing weather data (added in cache version 4)
            if run.weatherData == nil && !run.routeCoordinates.isEmpty {
                missingFeatures.append("weather")
            }
            
            // Check for missing power song (should be calculated for all runs with songs)
            if run.powerSong == nil && !(run.spotifyTracks?.isEmpty ?? true) && !run.routeCoordinates.isEmpty {
                missingFeatures.append("powerSong")
            }
            
            // Check for missing location analysis (neighborhood data)
            if run.locationAnalysis == nil && !run.routeCoordinates.isEmpty {
                missingFeatures.append("locationAnalysis")
            }
            
            if !missingFeatures.isEmpty {
                runsNeedingUpgrade.append((index, run, missingFeatures))
            }
        }
        
        guard !runsNeedingUpgrade.isEmpty else {
            print("✅ All cached runs are up to date with latest features")
            return
        }
        
        print("🔄 Upgrading \(runsNeedingUpgrade.count) cached runs with missing features...")
        
        for (runIndex, run, missingFeatures) in runsNeedingUpgrade {
            print("🔄 Upgrading '\(run.name)' - missing: \(missingFeatures.joined(separator: ", "))")
            
            var updatedRun = run
            var wasUpdated = false
            
            // Add missing weather data
            if missingFeatures.contains("weather"), let startLocation = run.startLocation {
                do {
                    let weatherData = try await WeatherService.shared.fetchWeatherData(
                        for: startLocation.coordinate,
                        on: run.date
                    )
                    updatedRun.weatherData = weatherData
                    wasUpdated = true
                    print("  ✅ Added weather: \(weatherData.temperature)°F, \(weatherData.condition.rawValue)")
                } catch {
                    print("  ⚠️ Failed to fetch weather: \(error.localizedDescription)")
                    print("  ⚠️ Skipping weather for this run (testing real data only)")
                }
            }
            
            // Add missing power song calculation
            if missingFeatures.contains("powerSong") {
                do {
                    // Fetch streams for power song calculation
                    let streams = try await stravaService.fetchActivityStreams(id: Int(run.id) ?? 0)
                    DataConversionService.shared.calculatePowerSong(for: &updatedRun, from: streams)
                    wasUpdated = true
                    if let powerSong = updatedRun.powerSong {
                        print("  ✅ Added power song: \(powerSong.name) by \(powerSong.artist)")
                    } else {
                        print("  ℹ️ No power song found for this run")
                    }
                } catch {
                    print("  ⚠️ Could not calculate power song: \(error.localizedDescription)")
                }
            }
            
            // Add missing location analysis
            if missingFeatures.contains("locationAnalysis") {
                let locationAnalysis = await LocationAnalysisService.shared.analyzeRunLocation(for: run.routeCoordinates)
                if let locationAnalysis = locationAnalysis {
                    updatedRun.locationAnalysis = locationAnalysis
                    wasUpdated = true
                    print("  ✅ Added location analysis: \(locationAnalysis.displayText)")
                } else {
                    print("  ℹ️ No location analysis available for this run")
                }
            }
            
            // Update the run in the array
            if wasUpdated {
                runActivities[runIndex] = updatedRun
                
                // Update the cache in Firebase
                let updatedCachedRun = CachedRunData(from: updatedRun)
                try? await firestoreService.storeCachedRun(userId: userId, run: updatedCachedRun)
                
                // Rate limit to avoid API abuse
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 second delay
            }
        }
        
        print("🔄 Cache upgrade complete!")
    }
    
    // MARK: - Legacy Weather Enrichment (replaced by upgradeCachedRunsIfNeeded)
    
    private func enrichCachedRunsWithWeather(userId: String, runActivities: inout [RunActivity]) async {
        var runsNeedingWeather: [RunActivity] = []
        var runsToUpdate: [Int] = []
        
        // Find runs missing weather data
        for (index, run) in runActivities.enumerated() {
            if run.weatherData == nil && !run.routeCoordinates.isEmpty {
                runsNeedingWeather.append(run)
                runsToUpdate.append(index)
            }
        }
        
        guard !runsNeedingWeather.isEmpty else {
            print("✅ All cached runs already have weather data")
            return
        }
        
        print("🌤️ Enriching \(runsNeedingWeather.count) cached runs with weather data...")
        
        // Process runs in parallel with rate limiting
        for (runIndex, run) in runsNeedingWeather.enumerated() {
            guard let startLocation = run.startLocation else { continue }
            
            do {
                let weatherData = try await WeatherService.shared.fetchWeatherData(
                    for: startLocation.coordinate,
                    on: run.date
                )
                
                // Update the run in the array
                let arrayIndex = runsToUpdate[runIndex]
                runActivities[arrayIndex].weatherData = weatherData
                
                // Update the cache in Firebase
                let updatedCachedRun = CachedRunData(from: runActivities[arrayIndex])
                try await firestoreService.storeCachedRun(userId: userId, run: updatedCachedRun)
                
                print("✅ Added weather to '\(run.name)': \(weatherData.temperature)°F, \(weatherData.condition.rawValue)")
                
                // Rate limit to avoid API abuse (small delay between requests)
                if runIndex < runsNeedingWeather.count - 1 {
                    try await Task.sleep(nanoseconds: 250_000_000) // 0.25 second delay
                }
                
            } catch {
                print("⚠️ Failed to fetch weather for '\(run.name)': \(error.localizedDescription)")
                print("⚠️ Skipping weather for this run (testing real data only)")
            }
        }
        
        print("🌤️ Weather enrichment complete!")
    }
    
    // MARK: - Initializers
    
    init(selectedRunId: Binding<String?> = .constant(nil)) {
        self._selectedRunId = selectedRunId
    }
}

// MARK: - Supporting Views

struct RunRowView: View {
    let run: RunActivity
    
    var body: some View {
        ZStack {
            // Background layer - photo background with fallback gradient
            Group {
                if let photoBackground = run.backgroundPhoto,
                   photoBackground.photoData != nil {
                    // Only use PhotoBackgroundView if we have actual photo data
                    PhotoBackgroundView(photoBackground: photoBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .onAppear {
                            print("📷 CARD BACKGROUND: Found photo background for '\(run.name)'")
                            print("📷   - Photo ID: \(photoBackground.photoId)")
                            print("📷   - Photo data: \(photoBackground.photoData?.count ?? 0) bytes")
                            print("📷   - Filter: \(photoBackground.filterType)")
                            print("📷   - Opacity: \(photoBackground.opacity)")
                        }
                } else {
                    // Fallback gradient background when no photo or no photo data
                    fallbackGradientForRun(run)
                        .onAppear {
                            let reason = run.backgroundPhoto == nil ? "No photo background" : "Photo background has no data"
                            print("📷 CARD BACKGROUND: \(reason) for '\(run.name)' - using gradient fallback")
                        }
                }
            }
            
            // Route line as background element - positioned on right side
            HStack {
                Spacer()
                RoutePathView(
                    coordinates: run.routeCoordinates,
                    lineWidth: 4.0, // Bigger route line as requested
                    colorScheme: run.weatherBasedRouteColor ?? run.colorScheme ?? RunColorScheme.presets[0]
                )
                .opacity(0.6) // Semi-transparent so it can be behind content
                .frame(width: 120, height: 120) // Fixed size on right side
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Dark overlay for better text readability
            Color.black.opacity(0.3)
            
            // Content overlay
            VStack(spacing: 0) {
                // Top section - Run title and indicators
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.name.lowercased())
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                            .lineLimit(2)
                        
                        // Location on its own line as requested
                        if let locationText = run.smartLocationDisplay {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(locationText.lowercased())
                                    .font(.custom("Helvetica Neue", size: 13))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .shadow(color: .black.opacity(0.6), radius: 1)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Date
                        Text(formatDateForDisplay(run.date))
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.6), radius: 1)
                        
                        // Music indicator with song count
                        if let tracks = run.spotifyTracks, !tracks.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                                
                                Text("\(tracks.count)")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                            }
                        }
                        
                    }
                }
                
                Spacer()
                
                // Bottom section - Prominent distance + other stats
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // DISTANCE - Front and center with prominent display
                        HStack(spacing: 4) {
                            Text(formatDistance(run.distance))
                                .font(.custom("Helvetica Neue", size: 18))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text(distanceUnitAbbreviation())
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(16)
                        
                        // Other stats in smaller pills
                        HStack(spacing: 6) {
                            RunStatBadge(
                                icon: "speedometer",
                                value: UserPreferences.shared.formatPace(run.averagePace),
                                unit: "/\(UserPreferences.shared.distanceUnit == .miles ? "mi" : "km")",
                                color: .green
                            )
                            
                            RunStatBadge(
                                icon: "clock",
                                value: run.compactFormattedDuration,
                                unit: "",
                                color: .blue
                            )
                        }
                    }
                    
                    Spacer()
                    
                    // Power song display - bottom-aligned with pace/time badges
                    if let powerSong = run.powerSong {
                        VStack(alignment: .trailing, spacing: 0) {
                            Spacer() // Push the power song to the bottom
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                // Power song name with fire emoji
                                HStack(spacing: 4) {
                                    Text("🔥")
                                        .font(.system(size: 14))
                                    Text(powerSong.name.lowercased())
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                                
                                // Power song pace below the name
                                if let powerSongPace = run.powerSongPacePerMile {
                                    Text(powerSongPace + "/mi")
                                        .font(.custom("Helvetica Neue", size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                }
            }
            .padding(18) // Slightly more padding for better proportions
        }
        .frame(height: 165) // Taller to accommodate prominent distance and power song
        .contentShape(Rectangle()) // Ensure entire area is tappable
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let userPrefs = UserPreferences.shared
        switch userPrefs.distanceUnit {
        case .miles:
            let miles = meters / 1609.34
            return String(format: "%.2f", miles)
        case .kilometers:
            let km = meters / 1000.0
            return String(format: "%.2f", km)
        }
    }
    
    private func distanceUnitAbbreviation() -> String {
        return UserPreferences.shared.distanceUnit.abbreviation
    }
    
    private func fallbackGradientForRun(_ run: RunActivity) -> LinearGradient {
        // More diverse gradient backgrounds to differentiate cards
        let gradientVariations: [[Color]] = [
            // Warm sunset
            [Color.orange.opacity(0.5), Color.pink.opacity(0.4), Color.red.opacity(0.3)],
            // Cool blue
            [Color.blue.opacity(0.5), Color.cyan.opacity(0.4), Color.teal.opacity(0.3)],
            // Purple vibes
            [Color.purple.opacity(0.5), Color.pink.opacity(0.4), Color.indigo.opacity(0.3)],
            // Green nature
            [Color.green.opacity(0.5), Color.mint.opacity(0.4), Color.teal.opacity(0.3)],
            // Warm orange
            [Color.orange.opacity(0.5), Color.yellow.opacity(0.4), Color.red.opacity(0.3)]
        ]
        
        // Use run ID hash to consistently pick the same gradient for each run
        let gradientIndex = abs(run.id.hashValue) % gradientVariations.count
        let selectedGradient = gradientVariations[gradientIndex]
        
        return LinearGradient(
            colors: selectedGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct RunStatBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            Text(value)
                .font(.custom("Helvetica Neue", size: 12))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.custom("Helvetica Neue", size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Mission District"
    )
    
    RunRowView(run: sampleRun)
        .padding()
}

// MARK: - Context Menu Component

struct RunContextMenu: View {
    let run: RunActivity
    let onAction: () -> Void
    @StateObject private var spotifyService = SpotifyService.shared
    @StateObject private var toastManager = ToastManager()
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Share Run Card
            Button(action: {
                HapticFeedbackService.shared.lightTap()
                shareRunCard()
                onAction()
            }) {
                Label("Share Card", systemImage: "square.and.arrow.up")
            }
            
            // Copy Run Details
            Button(action: {
                HapticFeedbackService.shared.selection()
                copyRunDetails()
                onAction()
            }) {
                Label("Copy Details", systemImage: "doc.on.doc")
            }
            
            // View on Strava (if available)
            Button(action: {
                HapticFeedbackService.shared.lightTap()
                openInStrava()
                onAction()
            }) {
                Label("View on Strava", systemImage: "arrow.up.right.square")
            }
            
            Divider()
            
            // Delete Run (destructive)
            Button(role: .destructive, action: {
                HapticFeedbackService.shared.warning()
                showDeleteAlert = true
            }) {
                Label("Delete Run Data", systemImage: "trash")
            }
        }
        .alert("Delete Run Data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRunData()
                onAction()
            }
        } message: {
            Text("This will remove the locally saved customizations for this run. The original Strava activity will not be affected.")
        }
    }
    
    private func shareRunCard() {
        // Generate and share the run card
        Task {
            // TODO: Implement card sharing directly from context menu
            print("🎨 Sharing card for run: \(run.name)")
        }
    }
    
    private func copyRunDetails() {
        let details = """
        \(run.name)
        Distance: \(String(format: "%.1f", run.distanceInMiles)) miles
        Time: \(run.formattedDuration)
        Pace: \(run.pacePerMile)/mile
        Date: \(DateFormatter.localizedString(from: run.date, dateStyle: .medium, timeStyle: .none))
        \(run.city != nil ? "Location: \(run.city!)" : "")
        """
        
        UIPasteboard.general.string = details
        
        // Haptic feedback for successful copy
        HapticFeedbackService.shared.success()
        
        // Show toast notification for feedback
        toastManager.show(message: "Copied to clipboard", icon: "doc.on.doc", color: .green)
        print("📋 Copied run details to clipboard")
    }
    
    private func openInStrava() {
        // Open run in Strava app or web
        let stravaURL = URL(string: "strava://activities/\(run.id)")
        let webURL = URL(string: "https://www.strava.com/activities/\(run.id)")
        
        if let stravaURL = stravaURL, UIApplication.shared.canOpenURL(stravaURL) {
            UIApplication.shared.open(stravaURL)
        } else if let webURL = webURL {
            UIApplication.shared.open(webURL)
        }
    }
    
    
    private func deleteRunData() {
        // TODO: Implement local data deletion
        print("🗑️ Deleting local data for run: \(run.name)")
    }
}


// MARK: - Weather Helper Functions

private func weatherEmoji(for condition: WeatherData.WeatherCondition) -> String {
    switch condition {
    case .clear: return "☀️"
    case .cloudy: return "☁️"
    case .rain: return "🌧️"
    case .snow: return "❄️"
    case .fog: return "🌫️"
    case .thunderstorm: return "⛈️"
    case .unknown: return "🌤️"
    }
}
