import SwiftUI
import CoreLocation
import Photos
import os.log

struct RunCardStackView: View {
    private let logger = Logger(subsystem: "com.charliekubal.runmusic", category: "RunCardStackView")
    
    // Optional binding for deep-linking to specific runs
    @Binding var selectedRunId: String?
    
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @StateObject private var userPreferences = UserPreferences.shared
    private let firestoreService = FirestoreService.shared
    
    // Card stack state (adapted from RunTunes)
    @State private var runs: [RunActivity] = []
    @State private var swipedRuns: [RunActivity] = [] // Track swiped cards
    @State private var dragOffset: CGSize = .zero
    @State private var navigationPath = NavigationPath()
    
    // RunMusic-specific state
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
    @State private var isApproachingEnd = false
    @State private var showFirebasePrompt = false
    @State private var hasExistingFirebaseAccount = false
    @State private var userUsername: String?
    @State private var selectedRun: RunActivity?
    @State private var isPullToRefresh = false
    
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Background gradient (like RunTunes)
                Color(.systemGray6)
                    .ignoresSafeArea()
                
                VStack {
                    headerView
                    
                    // Pull down indicator - supports both card restore and pull-to-refresh
                    if dragOffset.height > 50 || isPullToRefresh {
                        HStack(spacing: 8) {
                            if isPullToRefresh {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.green)
                            } else {
                                Image(systemName: swipedRuns.isEmpty ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                            }
                            
                            Text(isPullToRefresh ? "Checking for new runs..." : 
                                 (swipedRuns.isEmpty ? "Release to refresh" : "Release to restore card"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(swipedRuns.isEmpty || isPullToRefresh ? .green : .blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill((swipedRuns.isEmpty || isPullToRefresh ? Color.green : Color.blue).opacity(0.1))
                        )
                        .scaleEffect(isPullToRefresh ? 1.0 : min(1.0, dragOffset.height / 150))
                        .opacity(isPullToRefresh ? 1.0 : min(1.0, Double(dragOffset.height - 50) / 100))
                        .animation(.easeOut(duration: 0.2), value: dragOffset)
                    }
                    
                    Spacer()
                    
                    // Card stack or loading/empty state
                    Group {
                        if isLoading && runs.isEmpty {
                            loadingStateView
                        } else {
                            cardStackView
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer()
                    
                    // Banner sections (preserved from RunMusic)
                    VStack(spacing: 8) {
                        firebaseBannerSection
                        stravaBannerSection
                        spotifyBannerSection
                        firebaseUpsellBannerSection
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationDestination(for: RunActivity.self) { run in
                let _ = logger.info("🎨 NAVIGATION: RunCardStackView → RunCanvasDestinationView for run: \(run.name) (ID: \(run.id))")
                let _ = logger.info("🎨 NAVIGATION: Run has background photo: \(run.portraitSettings.backgroundPhoto != nil)")
                let _ = logger.info("🎨 NAVIGATION: Run has \(run.spotifyTracks?.count ?? 0) Spotify tracks")
                return RunCanvasDestinationView(initialRun: run)
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
            logger.info("RunCardStackView appeared - Spotify authenticated: \(spotifyService.isAuthenticated)")
            
            Task {
                await loadRuns()
                
                // Load username if Firebase authenticated
                if firebaseAuth.isAuthenticated, let userId = firebaseAuth.currentUser?.uid {
                    if let profile = try? await FirestoreService.shared.getUserProfile(userId: userId) {
                        userUsername = profile.username
                    }
                    
                    await spotifyService.syncWithFirebase()
                }
                
                // Photo assignment moved to after runs are loaded
                
                // Check for existing Firebase account
                if stravaService.isAuthenticated, let stravaUserId = stravaService.athlete?.id {
                    await checkForExistingFirebaseAccount(stravaUserId: String(stravaUserId))
                }
                
                // Show sign-in prompt logic (preserved from RunMusic)
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
            if !oldValue && newValue {
                logger.info("Spotify connected - refreshing runs")
                Task {
                    await loadRuns(isRefresh: true)
                }
            }
        }
        .onChange(of: selectedRunId) { _, runId in
            if let runId = runId {
                print("📱 Deep-linking to run: \(runId)")
                if let run = runs.first(where: { $0.id == runId }) {
                    navigationPath.append(run)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectedRunId = nil
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text(userUsername != nil ? "@\(userUsername!)'s runs" : "runs")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.primary)
            
            Spacer()
            
            // Back to top button - takes you to most recent run
            Button(action: {
                scrollToTop()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.primary)
                    .font(.title2)
            }
            .disabled(runs.isEmpty || (swipedRuns.isEmpty && currentPage == 1))
            .opacity(runs.isEmpty || (swipedRuns.isEmpty && currentPage == 1) ? 0.3 : 1.0)
            
            // Settings button
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.primary)
                    .font(.title2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
    }
    
    // MARK: - Card Stack (adapted from RunTunes)
    
    private var cardStackView: some View {
        Group {
            if runs.isEmpty {
                emptyStateView
            } else {
                ZStack {
                    ForEach(Array(runs.prefix(3).enumerated()), id: \.element.id) { index, run in
                        cardView(for: index, run: run)
                    }
                    
                    // Loading indicator for more runs
                    if isLoadingMore {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.orange)
                                Text("loading more runs...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.1))
                            )
                            .padding(.bottom, 100)
                            .animation(.easeInOut(duration: 0.3), value: isLoadingMore)
                        }
                    }
                    
                    // "No more runs" indicator when reached end
                    if !hasMoreRuns && runs.count > 10 && !isLoadingMore {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                Text("you've seen all your runs!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.1))
                            )
                            .padding(.bottom, 100)
                            .animation(.easeInOut(duration: 0.3), value: !hasMoreRuns)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text(swipedRuns.isEmpty ? "No runs yet!" : "All cards swiped")
                .font(.title2)
                .foregroundColor(.gray)
            
            if !swipedRuns.isEmpty {
                Text("Pull down to restore")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.7))
            } else {
                // Show connection prompts when no runs
                VStack(spacing: 16) {
                    if !stravaService.isAuthenticated {
                        Text("Connect Strava to see your runs")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    if !spotifyService.isAuthenticated {
                        SpotifyConnectionBanner(context: .generalMusic)
                    }
                }
            }
        }
        .padding()
        .gesture(
            // Allow pull down gesture even when no cards are visible
            DragGesture()
                .onChanged { gesture in
                    dragOffset = gesture.translation
                }
                .onEnded { gesture in
                    if gesture.translation.height > 100 && !swipedRuns.isEmpty {
                        withAnimation(.spring()) {
                            if let restoredRun = swipedRuns.popLast() {
                                runs.insert(restoredRun, at: 0) // FIX: Consistent with main gesture
                                print("🔄 Restored '\(restoredRun.name)' from empty state")
                            }
                        }
                    }
                    dragOffset = .zero
                }
        )
    }
    
    // MARK: - Progressive Loading
    
    private func loadSpotifyDataForRun(runId: String) async {
        
        await MainActor.run {
            // Find the run in our array
            guard let runIndex = self.runs.firstIndex(where: { $0.id == runId }) else { return }
            var run = self.runs[runIndex]
            
            // Skip if already has Spotify data
            guard run.spotifyTracks == nil || run.spotifyTracks?.isEmpty == true else { return }
            
            logger.info("🎵 Progressive loading Spotify data for: \(run.name)")
        }
        
        // Load in background
        Task {
            let runIndex = await MainActor.run { 
                self.runs.firstIndex(where: { $0.id == runId }) 
            }
            guard let runIndex = runIndex else { return }
            let run = await MainActor.run { self.runs[runIndex] }
            
            let endTime = run.date.addingTimeInterval(run.elapsedTime)
            var tracks = await spotifyService.fetchImportedTracksForTimeRange(
                startTime: run.date,
                endTime: endTime
            )
            
            // ENHANCED FALLBACK: If no tracks found in Firebase and Spotify is authenticated and run is very recent (within 1 hour), 
            // try fetching from live Spotify API and cache the results
            if tracks.isEmpty && spotifyService.isAuthenticated && run.date > Date().addingTimeInterval(-1 * 60 * 60) {
                logger.info("🌐 REAL-TIME FETCH: No tracks in Firebase for recent run, fetching from live Spotify API")
                do {
                    let recentTracks = try await spotifyService.fetchRecentTracks(limit: 50)
                    
                    // Debug: Log run time window
                    logger.info("🕐 Run time window: \(run.date) to \(endTime)")
                    logger.info("🕐 Run duration: \(run.elapsedTime) seconds")
                    
                    // Debug: Log first few tracks to see their timing
                    if !recentTracks.isEmpty {
                        logger.info("🎵 Recent tracks from Spotify API:")
                        for (index, track) in recentTracks.prefix(3).enumerated() {
                            logger.info("  \(index + 1). '\(track.name)' at \(track.playedAt)")
                        }
                    }
                    
                    tracks = recentTracks.filter { track in
                        let trackTime = track.playedAt
                        let isInRange = trackTime >= run.date && trackTime <= endTime
                        
                        // Debug: Log why tracks are being filtered out
                        if !isInRange {
                            let timeDiffStart = trackTime.timeIntervalSince(run.date)
                            let timeDiffEnd = trackTime.timeIntervalSince(endTime)
                            logger.info("⏰ Track '\(track.name)' at \(trackTime) excluded - start diff: \(timeDiffStart)s, end diff: \(timeDiffEnd)s")
                        }
                        
                        return isInRange
                    }
                    logger.info("🌐 Found \(tracks.count) tracks from Spotify API for time range")
                    
                    // CACHE TO FIREBASE: Save fetched tracks to Firebase for future use
                    if !tracks.isEmpty {
                        logger.info("💾 CACHING: Saving \(tracks.count) real-time fetched tracks to Firebase")
                        Task.detached(priority: .background) {
                            await self.spotifyService.storeImportedTracks(tracks)
                            await MainActor.run {
                                self.logger.info("✅ CACHED: Successfully saved \(tracks.count) tracks to Firebase")
                            }
                        }
                    }
                } catch {
                    logger.error("❌ Failed to fetch from Spotify API: \(error)")
                }
            }
            
            await MainActor.run {
                logger.info("🔄 PROGRESSIVE UPDATE: Updating run \(runId) with \(tracks.count) tracks")
                
                let runName = self.runs.first { $0.id == runId }?.name ?? 
                              self.swipedRuns.first { $0.id == runId }?.name ?? "unknown"
                
                // Update run in main array with explicit SwiftUI refresh
                if let mainIndex = self.runs.firstIndex(where: { $0.id == runId }) {
                    // CRITICAL FIX: Create a copy of the run with updated tracks to trigger SwiftUI change detection
                    var updatedRun = self.runs[mainIndex]
                    
                    // PREVENT DATA LOSS: Only update if we have more tracks than before
                    let existingTrackCount = updatedRun.spotifyTracks?.count ?? 0
                    if tracks.count >= existingTrackCount {
                        updatedRun.spotifyTracks = tracks
                        logger.info("🎵 UPDATING: \(runName) tracks: \(existingTrackCount) → \(tracks.count)")
                    } else {
                        logger.info("🚫 SKIPPING: \(runName) already has \(existingTrackCount) tracks, not replacing with \(tracks.count)")
                        return // Don't update anything if we're downgrading the data
                    }
                    
                    // Replace the entire run object to ensure SwiftUI detects the change
                    self.runs[mainIndex] = updatedRun
                    
                    logger.info("🎵 Updated main runs[\(mainIndex)] '\(runName)' with \(tracks.count) tracks")
                    
                    // DEBUG: Verify the update worked immediately
                    let verifyCount = self.runs[mainIndex].spotifyTracks?.count ?? -1
                    logger.info("🔍 DEBUG: Immediate verification - runs[\(mainIndex)] now has \(verifyCount) tracks")
                    
                    // Calculate power song if we have tracks and route data
                    print("🔥 POWER SONG DEBUG: Checking conditions for run \(runName)")
                    print("🔥 POWER SONG DEBUG: tracks.isEmpty = \(!tracks.isEmpty), routeCoordinates.isEmpty = \(!updatedRun.routeCoordinates.isEmpty)")
                    print("🔥 POWER SONG DEBUG: tracks count = \(tracks.count), routeCoordinates count = \(updatedRun.routeCoordinates.count)")
                    
                    // Only calculate power song if we have more tracks than before (prevent overwriting good data with empty data)
                    let previousTrackCount = updatedRun.spotifyTracks?.count ?? 0
                    let shouldCalculatePowerSong = !tracks.isEmpty && !updatedRun.routeCoordinates.isEmpty && tracks.count >= previousTrackCount
                    
                    print("🔥 POWER SONG DEBUG: shouldCalculatePowerSong = \(shouldCalculatePowerSong)")
                    print("🔥 POWER SONG DEBUG: tracks.count = \(tracks.count), previousTrackCount = \(previousTrackCount)")
                    
                    if shouldCalculatePowerSong {
                        print("🔥 POWER SONG DEBUG: Starting calculation for \(runName)")
                        // Fetch streams and calculate power song
                        Task.detached(priority: .background) {
                            do {
                                if let activityId = Int(updatedRun.id) {
                                    let streams = try await StravaService.shared.fetchActivityStreams(
                                        id: activityId, 
                                        types: ["time", "latlng", "velocity_smooth"]
                                    )
                                    
                                    await MainActor.run {
                                        // Update the run with power song data
                                        if let runIndex = self.runs.firstIndex(where: { $0.id == runId }) {
                                            var finalRun = self.runs[runIndex]
                                            DataConversionService.shared.calculatePowerSong(for: &finalRun, from: streams)
                                            self.runs[runIndex] = finalRun
                                            
                                            if let powerSong = finalRun.powerSong {
                                                self.logger.info("🔥 Calculated power song for \(runName): \(powerSong.name)")
                                                
                                                // Update cache with power song data
                                                Task.detached(priority: .background) {
                                                    await RunCacheService.shared.updateCachedRun(finalRun)
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    self.logger.error("❌ Failed to calculate power song for \(runName): \(error)")
                                }
                            }
                        }
                    }
                }
                
                // Update run in swiped array with explicit SwiftUI refresh
                if let swipedIndex = self.swipedRuns.firstIndex(where: { $0.id == runId }) {
                    // CRITICAL FIX: Create a copy of the run with updated tracks to trigger SwiftUI change detection
                    var updatedRun = self.swipedRuns[swipedIndex]
                    
                    // PREVENT DATA LOSS: Only update if we have more tracks than before
                    let existingTrackCount = updatedRun.spotifyTracks?.count ?? 0
                    if tracks.count >= existingTrackCount {
                        updatedRun.spotifyTracks = tracks
                        logger.info("🎵 UPDATING SWIPED: \(runName) tracks: \(existingTrackCount) → \(tracks.count)")
                    } else {
                        logger.info("🚫 SKIPPING SWIPED: \(runName) already has \(existingTrackCount) tracks, not replacing with \(tracks.count)")
                        return // Don't update anything if we're downgrading the data
                    }
                    
                    // Replace the entire run object to ensure SwiftUI detects the change
                    self.swipedRuns[swipedIndex] = updatedRun
                    
                    logger.info("🎵 Updated swiped runs[\(swipedIndex)] '\(runName)' with \(tracks.count) tracks")
                    
                    // Calculate power song for swiped runs too
                    if !tracks.isEmpty && !updatedRun.routeCoordinates.isEmpty {
                        Task.detached(priority: .background) {
                            do {
                                if let activityId = Int(updatedRun.id) {
                                    let streams = try await StravaService.shared.fetchActivityStreams(
                                        id: activityId, 
                                        types: ["time", "latlng", "velocity_smooth"]
                                    )
                                    
                                    await MainActor.run {
                                        if let swipedIndex = self.swipedRuns.firstIndex(where: { $0.id == runId }) {
                                            var finalRun = self.swipedRuns[swipedIndex]
                                            DataConversionService.shared.calculatePowerSong(for: &finalRun, from: streams)
                                            self.swipedRuns[swipedIndex] = finalRun
                                            
                                            if let powerSong = finalRun.powerSong {
                                                self.logger.info("🔥 Calculated power song for swiped \(runName): \(powerSong.name)")
                                                
                                                // Update cache with power song data
                                                Task.detached(priority: .background) {
                                                    await RunCacheService.shared.updateCachedRun(finalRun)
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    self.logger.error("❌ Failed to calculate power song for swiped \(runName): \(error)")
                                }
                            }
                        }
                    }
                }
                
                // Only trigger refresh if we actually got tracks
                if tracks.count > 0 {
                    logger.info("✅ Progressive load complete for '\(runName)' with \(tracks.count) tracks")
                    
                    // Enrich album art for tracks that need it
                    if let currentRun = self.runs.first(where: { $0.id == runId }) ?? 
                                        self.swipedRuns.first(where: { $0.id == runId }) {
                        print("🎨 PROGRESSIVE LOAD: Triggering album art enrichment for run: \(runName)")
                        Task {
                            await self.enrichAlbumArtForRunInArray(runId: runId)
                        }
                    } else {
                        print("🎨 PROGRESSIVE LOAD: Could not find run \(runId) in arrays for album art enrichment")
                    }
                } else {
                    print("🎨 PROGRESSIVE LOAD: No tracks loaded for \(runName), skipping album art enrichment")
                }
                
                // Verification - check if the update worked
                let finalCount = self.runs.first { $0.id == runId }?.spotifyTracks?.count ?? 
                                self.swipedRuns.first { $0.id == runId }?.spotifyTracks?.count ?? -1
                
                if tracks.isEmpty {
                    logger.info("ℹ️ PROGRESSIVE: No tracks found for '\(runName)' (expected for runs without music)")
                } else if finalCount == tracks.count {
                    logger.info("✅ PROGRESSIVE: Successfully loaded \(finalCount) tracks for '\(runName)'")
                } else {
                    logger.error("❌ PROGRESSIVE: Verification mismatch for '\(runName)' - expected \(tracks.count), found \(finalCount)")
                }
            }
        }
    }
    
    private func cardView(for index: Int, run: RunActivity) -> some View {
        // Use stable card count of 3 to avoid zIndex fluctuation during loading
        let visibleCardCount = 3
        let safeIndex = min(index, visibleCardCount - 1)
        // Fix: Index 0 (newest run) should be on top with offset 0
        let cardOffset = CGFloat(safeIndex) * 80
        let cardScale = 1.0 - (Double(safeIndex) * 0.02)
        
        // The top card is always index 0 (newest run)
        let isTopCard = index == 0
        
        return RunStackCardView(run: run)
            .offset(y: cardOffset)
            .scaleEffect(cardScale)
            .zIndex(Double(2 - index)) // 0=front(zIndex:2), 1=middle(zIndex:1), 2=back(zIndex:0)
            .offset(y: isTopCard ? dragOffset.height : 0)
            .rotationEffect(.degrees(isTopCard ? Double(dragOffset.width / 15) : 0))
            .gesture(isTopCard ? dragGesture : nil)
            .onTapGesture {
                if isTopCard {
                    // PERFORMANCE FIX: Skip complex searches, just use the run directly
                    selectedRun = run
                    navigationPath.append(run)
                }
            }
            .onAppear {
                // Check if we need to load more runs when cards appear
                if isTopCard {
                    checkIfNeedMoreRuns()
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                dragOffset = gesture.translation
            }
            .onEnded { gesture in
                // Log drag gesture
                print("🔥 Drag ended - offset: \(dragOffset), runs count: \(runs.count), swiped count: \(swipedRuns.count)")
                
                withAnimation(.spring()) {
                    if dragOffset.height < -150 {
                        // Swipe up - remove top card (should be runs[0], not last)
                        print("⬆️ Swiping up - removing top card")
                        dragOffset = CGSize(width: 0, height: -1000)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // Thread-safe array operations with bounds checking
                            if !runs.isEmpty && runs.count > 0 {
                                let swipedRun = runs.removeFirst() // FIX: Remove first card, not last
                                swipedRuns.append(swipedRun)
                                print("🗂️ Moved '\(swipedRun.name)' to swiped stack. Remaining: \(runs.count)")
                                
                                // Progressive loading: Ensure all runs eventually get Spotify data
                                Task {
                                    await loadSpotifyDataForVisibleCardsOnly()
                                }
                                
                                // Check if we need to load more runs (when reaching end of current batch)
                                if hasMoreRuns && runs.count > 0 && runs.count <= 5 {
                                    print("📱 Approaching end of runs, loading more...")
                                    Task {
                                        await loadMoreRuns()
                                    }
                                }
                            }
                            dragOffset = .zero
                        }
                    } else if dragOffset.height > 100 {
                        if !swipedRuns.isEmpty {
                            // Pull down - restore card (reduced threshold for easier access)
                            print("⬇️ Pulling down - restoring card (\(swipedRuns.count) available)")
                            dragOffset = CGSize(width: 0, height: 1000)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                // Thread-safe operations with bounds checking
                                if !swipedRuns.isEmpty, let restoredRun = swipedRuns.popLast() {
                                    runs.insert(restoredRun, at: 0) // FIX: Insert at front, not append
                                    print("🔄 Restored '\(restoredRun.name)' to top of stack. Total: \(runs.count)")
                                }
                                dragOffset = .zero
                            }
                        } else {
                            // Pull down - refresh for new runs from Strava
                            print("🔄 Pull-to-refresh triggered - checking Strava for new runs")
                            isPullToRefresh = true
                            dragOffset = CGSize(width: 0, height: 1000)
                            Task {
                                await loadRuns(isRefresh: true)
                                await MainActor.run {
                                    isPullToRefresh = false
                                    dragOffset = .zero
                                }
                            }
                        }
                    } else {
                        // Spring back to center
                        print("↩️ Springing back to center")
                        dragOffset = .zero
                    }
                }
            }
    }
    
    // MARK: - Loading State
    
    private var loadingStateView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            Text("loading runs...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Banner Sections (preserved from RunMusic)
    
    private var firebaseBannerSection: some View {
        Group {
            let shouldShowFirebaseBanner = stravaService.isAuthenticated && 
                                          spotifyService.isAuthenticated && 
                                          !firebaseAuth.isAuthenticated &&
                                          hasExistingFirebaseAccount
            
            if shouldShowFirebaseBanner {
                BannerView(
                    icon: "person.circle.fill",
                    iconColor: .blue,
                    title: "welcome back! sign in to sync",
                    subtitle: "we found your existing account",
                    buttonText: "sign in",
                    buttonColor: .blue
                ) {
                    showFirebasePrompt = true
                }
            }
        }
    }
    
    private var stravaBannerSection: some View {
        Group {
            let shouldShowStravaBanner = !stravaService.isAuthenticated && !runs.isEmpty
            
            if shouldShowStravaBanner {
                BannerView(
                    icon: "figure.run",
                    iconColor: .orange,
                    title: "reconnect strava",
                    subtitle: "your session expired - reconnect to load new runs",
                    buttonText: "reconnect",
                    buttonColor: .orange
                ) {
                    if let authURL = stravaService.authURL {
                        UIApplication.shared.open(authURL)
                    }
                }
            }
        }
    }
    
    private var spotifyBannerSection: some View {
        Group {
            let shouldShowSpotifyBanner = stravaService.isAuthenticated && !spotifyService.isAuthenticated
            let hasSpotifyHistory = !runs.isEmpty && runs.contains { !($0.spotifyTracks?.isEmpty ?? true) }
            let isSpotifyReconnect = shouldShowSpotifyBanner && hasSpotifyHistory
            
            if shouldShowSpotifyBanner {
                BannerView(
                    icon: "music.note",
                    iconColor: .green,
                    title: isSpotifyReconnect ? "reconnect spotify" : "connect spotify for music data",
                    subtitle: isSpotifyReconnect ? "your session expired - reconnect to see music" : "see what songs powered your runs",
                    buttonText: isSpotifyReconnect ? "reconnect" : "connect",
                    buttonColor: .green
                ) {
                    spotifyService.debugClearAllAuth()
                    if let authURL = spotifyService.authURL {
                        UIApplication.shared.open(authURL)
                    }
                }
            }
        }
    }
    
    private var firebaseUpsellBannerSection: some View {
        Group {
            let shouldShowUpsell = stravaService.isAuthenticated && 
                                 spotifyService.isAuthenticated && 
                                 !firebaseAuth.isAuthenticated
            
            if shouldShowUpsell {
                BannerView(
                    icon: "icloud.fill",
                    iconColor: .blue,
                    title: "save your runs & settings",
                    subtitle: "create an account via apple or google to sync across devices",
                    buttonText: "sign up",
                    buttonColor: .blue
                ) {
                    showFirebasePrompt = true
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Progressive Loading Functions
    
    private func loadSpotifyDataForVisibleCardsOnly() async {
        let currentRuns = await MainActor.run { Array(runs.prefix(3)) } // Only first 3 cards
        
        // Filter to only runs that actually need Spotify data
        let runsNeedingSpotify = currentRuns.filter { run in
            run.spotifyTracks == nil || run.spotifyTracks?.isEmpty == true
        }
        
        guard !runsNeedingSpotify.isEmpty else {
            logger.info("🎵 SKIP: All visible cards already have Spotify data")
            return
        }
        
        logger.info("🎵 CONSERVATIVE: Loading Spotify data for \(runsNeedingSpotify.count)/\(currentRuns.count) visible cards that need it")
        
        for (index, run) in runsNeedingSpotify.enumerated() {
            logger.info("🎵 LOADING: [\(index+1)/\(runsNeedingSpotify.count)] '\(run.name)' needs Spotify data")
            
            // Add small delay between requests for rate limiting
            if index > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await loadSpotifyDataForRun(runId: run.id)
        }
    }
    
    private func loadMoreRuns() async {
        guard !isLoadingMore && hasMoreRuns else {
            print("⚠️ Skipping loadMoreRuns - already loading: \(isLoadingMore), hasMore: \(hasMoreRuns)")
            return
        }
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        print("📱 Loading more runs - current page: \(currentPage + 1)")
        
        do {
            let nextPage = currentPage + 1
            let stravaActivities = try await stravaService.fetchActivities(page: nextPage)
            let runOnlyActivities = stravaActivities.filter { $0.type == "Run" }
            
            if runOnlyActivities.isEmpty {
                print("🚫 No more runs available from Strava")
                await MainActor.run {
                    hasMoreRuns = false
                    isLoadingMore = false
                }
                return
            }
            
            print("🏃 Found \(runOnlyActivities.count) more runs on page \(nextPage)")
            
            var newRuns: [RunActivity] = []
            
            // Load up to 5 runs from this page
            for activity in runOnlyActivities.prefix(5) {
                do {
                    let detailedActivity = try await stravaService.fetchDetailedActivity(id: activity.id)
                    let streams = try? await stravaService.fetchActivityStreams(id: activity.id, types: ["latlng", "time", "velocity_smooth"])
                    let runActivity = await DataConversionService.shared.convertStravaActivityToRunActivity(
                        activity,
                        detailedActivity: detailedActivity,
                        streams: streams
                    )
                    newRuns.append(runActivity)
                } catch {
                    logger.error("Failed to load detailed activity: \(error)")
                }
            }
            
            await MainActor.run {
                // Filter out duplicates and add new runs
                let filteredNewRuns = newRuns.filter { newRun in
                    !self.runs.contains { existingRun in existingRun.id == newRun.id }
                }
                
                self.runs.append(contentsOf: filteredNewRuns)
                self.runs.sort { $0.date > $1.date }
                self.currentPage = nextPage
                self.isLoadingMore = false
                
                print("✅ Added \(filteredNewRuns.count) new runs, total: \(self.runs.count)")
                
                // Check if we got fewer than 5 runs (might be approaching end)
                if runOnlyActivities.count < 5 {
                    self.hasMoreRuns = false
                    print("🚫 Reached end of available runs")
                }
            }
            
        } catch {
            logger.error("Failed to load more runs: \(error)")
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    private func checkIfNeedMoreRuns() {
        // Trigger loading more runs when user has fewer than 8 runs remaining
        // This gives us a nice buffer so users never see "no more runs"
        if hasMoreRuns && !isLoadingMore && runs.count > 0 && runs.count <= 8 {
            print("📎 User approaching end of runs (\(runs.count) remaining), loading more...")
            Task {
                await loadMoreRuns()
            }
        }
    }
    
    // MARK: - Data Loading (preserved from RunMusic)
    
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
        
        await loadRunsForPage(page: 1, isRefresh: isRefresh, initialLoadLimit: 10)
    }
    
    private func scrollToTop() {
        // Reset pagination state
        currentPage = 1
        hasMoreRuns = true
        
        // Restore all swiped runs back to the main stack with animation
        withAnimation(.easeInOut(duration: 0.5)) {
            // Merge swiped runs back to the beginning of the runs array
            if !swipedRuns.isEmpty {
                runs = swipedRuns + runs
                swipedRuns.removeAll()
            }
            
            // Reset any drag offsets
            dragOffset = .zero
        }
        
        // Optionally refresh data to ensure we have the latest runs
        Task {
            await loadRuns(isRefresh: true)
        }
    }
    
    private func loadRunsForPage(page: Int, isRefresh: Bool, initialLoadLimit: Int? = nil) async {
        // This is a simplified version of RunMusic's complex loading logic
        // Full implementation would include Firebase caching, pagination, etc.
        
        Task {
            var runActivities: [RunActivity] = []
            
            do {
                // Use RunCacheService for intelligent caching with Firebase
                logger.info("🔄 Using RunCacheService for cached/fresh run data (refresh: \(isRefresh))")
                let cachedRuns = try await RunCacheService.shared.getCachedRunsOrFetch(
                    stravaService: stravaService,
                    page: page,
                    perPage: initialLoadLimit ?? 10,
                    maxCacheAge: isRefresh ? 0 : 2 * 60 * 60 // Force fresh if refresh, else 2-hour cache for new run detection
                )
                runActivities = Array(cachedRuns.prefix(initialLoadLimit ?? 10))
                logger.info("🏃 Loaded \(runActivities.count) runs via RunCacheService")
                
                // Add Spotify tracks - LAZY LOADING: only for first 3 cards (visible stack)
                if page == 1 {
                    logger.info("🎵 Loading Spotify tracks for first 3 visible cards only")
                    let visibleCardLimit = min(3, runActivities.count)
                    for i in 0..<visibleCardLimit {
                        // CRITICAL FIX: Check if cached run already has Spotify tracks
                        let existingTrackCount = runActivities[i].spotifyTracks?.count ?? 0
                        if existingTrackCount > 0 {
                            logger.info("🎵 CACHED: Run '\(runActivities[i].name)' already has \(existingTrackCount) tracks from cache - preserving")
                            
                            // 🎨 ALBUM ART FIX: Enrich cached tracks with album art if missing
                            if let tracks = runActivities[i].spotifyTracks {
                                // DEBUG: Log actual album art URLs
                                logger.info("🎨 DEBUG: Cached track album art URLs:")
                                for (index, track) in tracks.enumerated() {
                                    let url = track.albumImageURL ?? "nil"
                                    logger.info("  \(index + 1). '\(track.name)' - Album URL: \(url)")
                                }
                                
                                let tracksNeedingArt = tracks.filter { track in
                                    track.albumImageURL == nil || track.albumImageURL?.isEmpty == true
                                }
                                
                                if !tracksNeedingArt.isEmpty {
                                    logger.info("🎨 CACHED ENRICHMENT: \(tracksNeedingArt.count) cached tracks need album art")
                                    let enrichedTracks = await spotifyService.enrichTracksWithAlbumArt(tracksNeedingArt)
                                    
                                    // Update the run with enriched album art
                                    var updatedTracks = tracks
                                    for enrichedTrack in enrichedTracks {
                                        if let index = updatedTracks.firstIndex(where: { $0.id == enrichedTrack.id }) {
                                            updatedTracks[index] = enrichedTrack
                                        }
                                    }
                                    
                                    runActivities[i].spotifyTracks = updatedTracks
                                    logger.info("🎨 CACHED ENRICHMENT: Updated cached run with album art")
                                    
                                    // Update cache with enriched data
                                    await RunCacheService.shared.updateCachedRun(runActivities[i])
                                } else {
                                    logger.info("🎨 CACHED: All \(existingTrackCount) tracks already have album art")
                                }
                            }
                            
                            continue
                        }
                        
                        logger.info("🎵 FETCH: Run '\(runActivities[i].name)' has no tracks, fetching from Firebase...")
                        let endTime = runActivities[i].date.addingTimeInterval(runActivities[i].elapsedTime)
                        var tracks = await spotifyService.fetchImportedTracksForTimeRange(
                            startTime: runActivities[i].date,
                            endTime: endTime
                        )
                        
                        // ENHANCED FALLBACK: If no tracks found in Firebase and Spotify is authenticated and run is very recent (within 1 hour), 
                        // try fetching from live Spotify API and cache the results
                        if tracks.isEmpty && spotifyService.isAuthenticated && runActivities[i].date > Date().addingTimeInterval(-1 * 60 * 60) {
                            logger.info("🌐 REAL-TIME FETCH: No tracks in Firebase for recent run, fetching from live Spotify API")
                            do {
                                let recentTracks = try await spotifyService.fetchRecentTracks(limit: 50)
                                
                                // Debug: Log run time window
                                logger.info("🕐 Run time window: \(runActivities[i].date) to \(endTime)")
                                logger.info("🕐 Run duration: \(runActivities[i].elapsedTime) seconds")
                                
                                // Debug: Log first few tracks to see their timing
                                if !recentTracks.isEmpty {
                                    logger.info("🎵 Recent tracks from Spotify API:")
                                    for (index, track) in recentTracks.prefix(3).enumerated() {
                                        logger.info("  \(index + 1). '\(track.name)' at \(track.playedAt)")
                                    }
                                }
                                
                                tracks = recentTracks.filter { track in
                                    let trackTime = track.playedAt
                                    let isInRange = trackTime >= runActivities[i].date && trackTime <= endTime
                                    
                                    // Debug: Log why tracks are being filtered out
                                    if !isInRange {
                                        let timeDiffStart = trackTime.timeIntervalSince(runActivities[i].date)
                                        let timeDiffEnd = trackTime.timeIntervalSince(endTime)
                                        logger.info("⏰ Track '\(track.name)' at \(trackTime) excluded - start diff: \(timeDiffStart)s, end diff: \(timeDiffEnd)s")
                                    }
                                    
                                    return isInRange
                                }
                                logger.info("🌐 Found \(tracks.count) tracks from Spotify API for time range")
                                
                                // CACHE TO FIREBASE: Save fetched tracks to Firebase for future use
                                if !tracks.isEmpty {
                                    logger.info("💾 CACHING: Saving \(tracks.count) real-time fetched tracks to Firebase")
                                    Task.detached(priority: .background) {
                                        await self.spotifyService.storeImportedTracks(tracks)
                                        await MainActor.run {
                                            self.logger.info("✅ CACHED: Successfully saved \(tracks.count) tracks to Firebase")
                                        }
                                    }
                                }
                            } catch {
                                logger.error("❌ Failed to fetch from Spotify API: \(error)")
                            }
                        }
                        
                        runActivities[i].spotifyTracks = tracks
                        logger.info("🎵 Loaded \(tracks.count) tracks for run: \(runActivities[i].name)")
                        
                        // Enrich album art for tracks that need it
                        if !tracks.isEmpty {
                            print("🎨 CACHE LOAD: Checking album art for run: \(runActivities[i].name)")
                            let tracksNeedingArt = tracks.filter { track in
                                track.albumImageURL?.isEmpty != false
                            }
                            if !tracksNeedingArt.isEmpty {
                                print("🎨 CACHE LOAD: \(tracksNeedingArt.count) tracks need album art enrichment")
                                // Trigger album art enrichment after the runs are added to the UI
                                Task {
                                    // Give the UI a moment to update, then enrich
                                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                    await self.enrichAlbumArtForRunInArray(runId: runActivities[i].id)
                                }
                            } else {
                                print("🎨 CACHE LOAD: All tracks already have album art")
                            }
                        }
                        
                        // Calculate power song if we have tracks and route data
                        if !tracks.isEmpty && !runActivities[i].routeCoordinates.isEmpty {
                            // We need to fetch streams for power song calculation
                            // For now, defer this to progressive loading to avoid slowing initial load
                            logger.info("🔥 Deferring power song calculation for \(runActivities[i].name) - will calculate during progressive loading")
                        }
                    }
                    logger.info("🎵 Deferred Spotify loading for remaining \(runActivities.count - visibleCardLimit) runs")
                }
                
                await MainActor.run {
                    if isRefresh || page == 1 {
                        self.runs = runActivities.sorted { $0.date > $1.date }
                    } else {
                        let newRuns = runActivities.filter { newRun in
                            !self.runs.contains { existingRun in existingRun.id == newRun.id }
                        }
                        self.runs.append(contentsOf: newRuns)
                        self.runs.sort { $0.date > $1.date }
                    }
                    
                    // DEBUG: Check if runs have tracks but missing album art
                    print("🎨 RUNS LOADED DEBUG: Checking \(self.runs.count) runs for missing album art")
                    for run in self.runs.prefix(3) {
                        let trackCount = run.spotifyTracks?.count ?? 0
                        if trackCount > 0 {
                            let tracksWithArt = run.spotifyTracks?.filter { $0.albumImageURL == nil || $0.albumImageURL!.isEmpty }.count ?? 0
                            print("🎨 Run '\(run.name)': \(trackCount) tracks, \(tracksWithArt) need album art")
                            
                            // If tracks exist but need album art, trigger enrichment
                            if tracksWithArt > 0 {
                                print("🎨 MANUAL TRIGGER: Starting album art enrichment for: \(run.name)")
                                Task {
                                    await self.enrichAlbumArtForRunInArray(runId: run.id)
                                }
                            }
                        } else {
                            print("🎨 Run '\(run.name)': No tracks loaded")
                        }
                    }
                    
                    // Debug: Log the first 5 runs with their dates
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d, yyyy HH:mm"
                    logger.info("📅 RUNS SORTED ORDER (first 5):")
                    for (index, run) in self.runs.prefix(5).enumerated() {
                        logger.info("  \(index): \(run.name) - \(dateFormatter.string(from: run.date))")
                    }
                    
                    self.isLoading = false
                    self.isLoadingMore = false
                }
                
                // Start conservative progressive loading for visible cards only (Firebase + Spotify fallback)
                if page == 1 {
                    Task.detached(priority: .background) {
                        await self.loadSpotifyDataForVisibleCardsOnly()
                    }
                }
                
                // Auto-assign photo backgrounds for runs without custom backgrounds
                Task.detached(priority: .background) {
                    await self.assignBackgroundPhotos()
                }
                logger.info("📷 Starting automatic photo background assignment")
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    // Helper function to safely update run background without index conflicts
    @MainActor
    private func updateRunBackground(runId: String, photoBackground: RunPhotoBackground) {
        if let index = runs.firstIndex(where: { $0.id == runId }) {
            runs[index].portraitSettings.backgroundPhoto = photoBackground
            logger.info("📷 ✅ Updated background photo for run '\(runs[index].name)' at index \(index)")
        } else {
            logger.warning("📷 ❌ Could not find run with ID \(runId) to update background")
        }
    }
    
    // Helper function to update run background with caching metadata
    @MainActor
    private func updateRunBackgroundWithMetadata(runId: String, photoBackground: RunPhotoBackground, metadata: PhotoAssignmentMetadata) {
        if let index = runs.firstIndex(where: { $0.id == runId }) {
            runs[index].portraitSettings.backgroundPhoto = photoBackground
            runs[index].portraitSettings.photoAssignmentMetadata = metadata
            logger.info("📷 ✅ Updated background photo with metadata for run '\(runs[index].name)' (type: \(metadata.assignmentType.rawValue))")
        } else {
            logger.warning("📷 ❌ Could not find run with ID \(runId) to update background with metadata")
        }
    }
    
    // Helper function for user-selected backgrounds (invalidates cache)
    @MainActor
    func setUserSelectedBackground(runId: String, photoBackground: RunPhotoBackground) {
        if let index = runs.firstIndex(where: { $0.id == runId }) {
            // Create user-selected metadata to prevent automatic reassignment
            let metadata = PhotoAssignmentMetadata(
                searchDate: Date(),
                assignmentType: .userSelected,
                searchResults: PhotoAssignmentMetadata.PhotoSearchResults(
                    runTimeframePhotos: 0, // Not relevant for user selection
                    sameDayPhotos: 0,
                    recentPhotos: 0,
                    hasPhotoLibraryAccess: true, // User is actively selecting
                    searchTimeMs: 0
                )
            )
            
            runs[index].portraitSettings.backgroundPhoto = photoBackground
            runs[index].portraitSettings.photoAssignmentMetadata = metadata
            logger.info("📷 ✅ User manually selected background for run '\(runs[index].name)' - cache invalidated")
        } else {
            logger.warning("📷 ❌ Could not find run with ID \(runId) to set user-selected background")
        }
    }
    
    // Helper function to clear background and allow reassignment
    @MainActor
    func clearRunBackground(runId: String) {
        if let index = runs.firstIndex(where: { $0.id == runId }) {
            runs[index].portraitSettings.backgroundPhoto = nil
            runs[index].portraitSettings.photoAssignmentMetadata = nil
            logger.info("📷 ✅ Cleared background for run '\(runs[index].name)' - will be reassigned automatically")
        } else {
            logger.warning("📷 ❌ Could not find run with ID \(runId) to clear background")
        }
    }
    
    private func assignBackgroundPhotos() async {
        let startTime = Date()
        
        // Create a safe snapshot of runs to avoid concurrent modification issues
        let runsSnapshot = await MainActor.run { Array(runs) }
        logger.info("📷 Starting photo assignment for \(runsSnapshot.count) runs...")
        
        // Request photo library access if needed
        let hasAccess = await PhotoService.shared.requestPhotoLibraryAccess()
        if !hasAccess {
            logger.error("❌ Photo library access denied - skipping photo assignment")
            return
        }
        
        for (index, var run) in runsSnapshot.enumerated() {
            // Skip if run already has a custom background photo
            guard run.portraitSettings.backgroundPhoto == nil else { 
                logger.info("📷 Skipping '\(run.name)' - already has photo background")
                continue 
            }
            
            // Check if we have valid cached photo assignment metadata
            if let metadata = run.portraitSettings.photoAssignmentMetadata,
               metadata.shouldUseCachedResult {
                logger.info("📷 Using cached photo assignment for '\(run.name)' (type: \(metadata.assignmentType.rawValue))")
                
                // If cache says no photos were found, create default background
                if metadata.assignmentType == .defaultGradient {
                    if let defaultBackground = await createDefaultBackground(for: run) {
                        await updateRunBackground(runId: run.id, photoBackground: defaultBackground)
                        logger.info("📷 Applied cached default background for '\(run.name)'")
                    }
                }
                continue
            }
            
            logger.info("📷 Processing run '\(run.name)' (\(run.date))")
            let searchStartTime = Date()
            
            // Fetch photos from the run timeframe
            let photos = await PhotoService.shared.fetchPhotosForRun(
                date: run.date,
                duration: run.elapsedTime
            )
            
            var expandedPhotos: [PHAsset] = []
            var recentPhotos: [PHAsset] = []
            
            // If photos are available during run timeframe, use the first one
            if !photos.isEmpty {
                logger.info("📷 Found \(photos.count) photos during run timeframe for '\(run.name)'")
                if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                    from: photos,
                    filterType: .blur
                ) {
                    // Create metadata for run timeframe assignment
                    let searchTime = Date().timeIntervalSince(searchStartTime) * 1000 // Convert to ms
                    let metadata = PhotoAssignmentMetadata(
                        searchDate: Date(),
                        assignmentType: .runTimeframe,
                        searchResults: PhotoAssignmentMetadata.PhotoSearchResults(
                            runTimeframePhotos: photos.count,
                            sameDayPhotos: 0, // Not searched yet
                            recentPhotos: 0, // Not searched yet
                            hasPhotoLibraryAccess: hasAccess,
                            searchTimeMs: searchTime
                        )
                    )
                    
                    await updateRunBackgroundWithMetadata(runId: run.id, photoBackground: photoBackground, metadata: metadata)
                    logger.info("✅ Using timeframe photo for run '\(run.name)' (cached for future)")
                    continue
                } else {
                    logger.error("❌ Failed to create photo background from timeframe photos for '\(run.name)'")
                }
            } else {
                logger.info("📷 No photos found during run timeframe for '\(run.name)'")
                // Second fallback: expand search to same day (1 day before/after)
                let expandedStartTime = run.date.addingTimeInterval(-24 * 60 * 60)  // 1 day before
                let expandedEndTime = run.date.addingTimeInterval(run.elapsedTime + 24 * 60 * 60)  // 1 day after
                
                logger.info("📷 No run-time photos, expanding to same day for run '\(run.name)'")
                
                expandedPhotos = await PhotoService.shared.fetchPhotosForRun(
                    date: expandedStartTime,
                    duration: 48 * 60 * 60 // 2 day window
                )
                
                if !expandedPhotos.isEmpty {
                    logger.info("📷 Found \(expandedPhotos.count) photos in expanded timeframe for '\(run.name)'")
                    if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                        from: expandedPhotos,
                        filterType: .blur
                    ) {
                        // Create metadata for same-day expanded assignment
                        let searchTime = Date().timeIntervalSince(searchStartTime) * 1000
                        let metadata = PhotoAssignmentMetadata(
                            searchDate: Date(),
                            assignmentType: .sameDayExpanded,
                            searchResults: PhotoAssignmentMetadata.PhotoSearchResults(
                                runTimeframePhotos: photos.count,
                                sameDayPhotos: expandedPhotos.count,
                                recentPhotos: 0, // Not searched yet
                                hasPhotoLibraryAccess: hasAccess,
                                searchTimeMs: searchTime
                            )
                        )
                        
                        await updateRunBackgroundWithMetadata(runId: run.id, photoBackground: photoBackground, metadata: metadata)
                        logger.info("✅ Using same-day photo for run '\(run.name)' (cached for future)")
                        continue
                    } else {
                        logger.error("❌ Failed to create photo background from expanded timeframe photos for '\(run.name)'")
                    }
                } else {
                    logger.info("📷 No photos found in expanded timeframe for '\(run.name)'")
                }
                
                // Third fallback: recent photos from camera roll (most recent 50)
                recentPhotos = await PhotoService.shared.fetchPhotosForRun(
                    date: Date().addingTimeInterval(-30 * 24 * 60 * 60), // Last 30 days
                    duration: 30 * 24 * 60 * 60 // 30 day window
                )
                
                if !recentPhotos.isEmpty {
                    if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                        from: recentPhotos,
                        filterType: .blur
                    ) {
                        // Create metadata for recent camera roll assignment
                        let searchTime = Date().timeIntervalSince(searchStartTime) * 1000
                        let metadata = PhotoAssignmentMetadata(
                            searchDate: Date(),
                            assignmentType: .recentCameraRoll,
                            searchResults: PhotoAssignmentMetadata.PhotoSearchResults(
                                runTimeframePhotos: photos.count,
                                sameDayPhotos: expandedPhotos.count,
                                recentPhotos: recentPhotos.count,
                                hasPhotoLibraryAccess: hasAccess,
                                searchTimeMs: searchTime
                            )
                        )
                        
                        await updateRunBackgroundWithMetadata(runId: run.id, photoBackground: photoBackground, metadata: metadata)
                        logger.info("📷 Using recent camera roll photo as fallback for run '\(run.name)' (cached for future)")
                        continue
                    }
                }
                
                // Ultimate fallback: Create a default background for simulator/testing
                if let defaultBackground = await createDefaultBackground(for: run) {
                    // Create metadata for default gradient assignment
                    let searchTime = Date().timeIntervalSince(searchStartTime) * 1000
                    let metadata = PhotoAssignmentMetadata(
                        searchDate: Date(),
                        assignmentType: .defaultGradient,
                        searchResults: PhotoAssignmentMetadata.PhotoSearchResults(
                            runTimeframePhotos: photos.count,
                            sameDayPhotos: expandedPhotos.count,
                            recentPhotos: recentPhotos.count,
                            hasPhotoLibraryAccess: hasAccess,
                            searchTimeMs: searchTime
                        )
                    )
                    
                    await updateRunBackgroundWithMetadata(runId: run.id, photoBackground: defaultBackground, metadata: metadata)
                    logger.info("📷 Using default background for simulator for run '\(run.name)' (cached for future)")
                } else {
                    logger.info("📷 No photos available for run '\(run.name)'")
                }
            }
        }
    }
    
    private func createDefaultBackground(for run: RunActivity) async -> RunPhotoBackground? {
        // Create a gradient background based on run characteristics
        let gradientColors: [UIColor]
        
        // Choose gradient based on run characteristics with more vibrant colors
        if let weather = run.weatherData {
            switch weather.timeOfDay {
            case .dawn, .morning:
                gradientColors = [
                    UIColor.systemOrange,
                    UIColor.systemYellow,
                    UIColor.systemPink
                ]
            case .evening:
                gradientColors = [
                    UIColor.systemIndigo,
                    UIColor.systemBlue,
                    UIColor.systemPurple
                ]
            case .night:
                gradientColors = [
                    UIColor.systemPurple,
                    UIColor.systemIndigo,
                    UIColor.darkGray
                ]
            default:
                gradientColors = [
                    UIColor.systemTeal,
                    UIColor.systemCyan,
                    UIColor.systemBlue
                ]
            }
        } else {
            // Default gradient for unknown time - more vibrant
            gradientColors = [
                UIColor.systemTeal,
                UIColor.systemBlue,
                UIColor.systemIndigo
            ]
        }
        
        // Create a gradient background image
        let size = CGSize(width: 400, height: 600) // Standard background size
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let gradientImage = renderer.image { context in
            let cgContext = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            
            let colors = gradientColors.map { $0.cgColor }
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors as CFArray,
                locations: locations
            ) else { return }
            
            // Create a diagonal gradient
            let startPoint = CGPoint(x: 0, y: 0)
            let endPoint = CGPoint(x: size.width, y: size.height)
            
            cgContext.drawLinearGradient(
                gradient,
                start: startPoint,
                end: endPoint,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        
        // Convert to photo background with less blur and higher opacity
        return await PhotoService.shared.createPhotoBackground(
            from: gradientImage,
            filterType: .blur,
            opacity: 0.8
        )
    }
    
    private func checkForExistingFirebaseAccount(stravaUserId: String) async {
        do {
            let existingAccount = try await firestoreService.checkForExistingAccount(stravaUserId: stravaUserId)
            await MainActor.run {
                hasExistingFirebaseAccount = existingAccount
            }
        } catch {
            print("Error checking for existing Firebase account: \(error)")
        }
    }
    
    // MARK: - Album Art Enrichment
    
    @MainActor
    private func enrichAlbumArtForRunInArray(runId: String) async {
        print("🎨 Starting album art enrichment for run ID: \(runId)")
        
        // First, check Spotify authentication status
        print("🎨 Spotify authentication status: \(SpotifyService.shared.isAuthenticated)")
        guard SpotifyService.shared.isAuthenticated else {
            print("🚨 Spotify not authenticated - cannot enrich album art")
            return
        }
        
        // Find the run in either array
        var runActivity: RunActivity
        var isInMainArray = false
        
        if let mainIndex = runs.firstIndex(where: { $0.id == runId }) {
            runActivity = runs[mainIndex]
            isInMainArray = true
        } else if let swipedIndex = swipedRuns.firstIndex(where: { $0.id == runId }) {
            runActivity = swipedRuns[swipedIndex]
            isInMainArray = false
        } else {
            print("🚨 Could not find run with ID: \(runId)")
            return
        }
        
        guard let tracks = runActivity.spotifyTracks, !tracks.isEmpty else {
            print("🎨 No tracks available for enrichment")
            return
        }
        
        // Find tracks that need album art enrichment (empty/nil albumImageURL)
        let tracksNeedingEnrichment = tracks.filter { track in
            let needsEnrichment = track.albumImageURL == nil || track.albumImageURL!.isEmpty
            if needsEnrichment {
                print("🎨 Track '\(track.name)' needs enrichment - albumImageURL: \(track.albumImageURL ?? "nil")")
            }
            return needsEnrichment
        }
        
        print("🎨 Found \(tracksNeedingEnrichment.count) tracks needing album art enrichment out of \(tracks.count) total")
        
        guard !tracksNeedingEnrichment.isEmpty else {
            print("🎨 All tracks already have album art URLs - no enrichment needed")
            return
        }
        
        do {
            print("🎨 Calling SpotifyService.enrichTracksWithAlbumArt for \(tracksNeedingEnrichment.count) tracks...")
            let enrichedTracks = await SpotifyService.shared.enrichTracksWithAlbumArt(tracksNeedingEnrichment)
            print("🎨 Successfully enriched \(enrichedTracks.count) tracks with album art")
            
            // Update the tracks with enriched data
            var updatedTracks = tracks
            var successfulUpdates = 0
            
            for enrichedTrack in enrichedTracks {
                if let index = updatedTracks.firstIndex(where: { $0.id == enrichedTrack.id }) {
                    updatedTracks[index] = enrichedTrack
                    successfulUpdates += 1
                    print("🎨 ✅ Updated track '\(enrichedTrack.name)' with album art URL: \(enrichedTrack.albumImageURL ?? "nil")")
                }
            }
            
            if successfulUpdates > 0 {
                // Update the run in the appropriate array to trigger UI refresh
                runActivity.spotifyTracks = updatedTracks
                
                if isInMainArray, let mainIndex = runs.firstIndex(where: { $0.id == runId }) {
                    runs[mainIndex] = runActivity
                } else if !isInMainArray, let swipedIndex = swipedRuns.firstIndex(where: { $0.id == runId }) {
                    swipedRuns[swipedIndex] = runActivity
                }
                
                print("🎨 ✅ Album art enrichment completed successfully - updated \(successfulUpdates) tracks")
                
                // Update cache with enriched data
                Task.detached(priority: .background) {
                    await RunCacheService.shared.updateCachedRun(runActivity)
                }
            } else {
                print("🎨 ⚠️ No tracks were successfully updated")
            }
            
        } catch {
            print("🚨 Failed to enrich album art: \(error)")
            print("🚨 Error details: \(error.localizedDescription)")
            if let error = error as NSError? {
                print("🚨 Error domain: \(error.domain), code: \(error.code)")
            }
        }
    }
}

// MARK: - Supporting Views

struct BannerView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonText: String
    let buttonColor: Color
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.custom("Helvetica Neue", size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(buttonText) {
                action()
            }
            .font(.custom("Helvetica Neue", size: 14))
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(buttonColor)
            .cornerRadius(20)
        }
        .padding(16)
        .background(buttonColor.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Canvas Destination Wrapper

struct RunCanvasDestinationView: View {
    let initialRun: RunActivity
    @State private var run: RunActivity
    
    init(initialRun: RunActivity) {
        self.initialRun = initialRun
        self._run = State(initialValue: initialRun)
        print("🎨 VIEW INIT: RunCanvasDestinationView created for run: \(initialRun.name)")
    }
    
    var body: some View {
        SimpleRunCanvasView(run: $run)
            .onAppear {
                print("🎨 VIEW APPEAR: RunCanvasDestinationView appeared for run: \(run.name)")
            }
    }
}

struct SimpleRunCanvasView: View {
    @Binding var run: RunActivity
    @Environment(\.dismiss) private var dismiss
    
    @State private var canvasSize: CGSize = .zero
    @State private var assets: [CanvasAsset] = []
    @State private var selectedAsset: CanvasAsset?
    @State private var showingAddAssetMenu = false
    @State private var showingEditSheet = false
    @State private var hasInitializedAssets = false
    
    init(run: Binding<RunActivity>) {
        self._run = run
        print("📱 CANVAS SYSTEM: ✅ SimpleRunCanvasView is the CURRENT/MODERN system")
        print("🎨 VIEW INIT: SimpleRunCanvasView created for run: \(run.wrappedValue.name)")
        print("🎨 VIEW INIT: Run has \(run.wrappedValue.spotifyTracks?.count ?? 0) Spotify tracks")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background layer - photo background with fallback
                Group {
                    if let photoBackground = run.portraitSettings.backgroundPhoto {
                        PhotoBackgroundView(photoBackground: photoBackground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        // Default gradient background
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.pink.opacity(0.1),
                                Color.black.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }
                }
                
                // Canvas area using percentage-based positioning (Unit Coordinate Space 0.0-1.0)
                GeometryReader { canvasGeometry in
                    ZStack {
                        // Tap area to deselect
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAsset = nil
                            }
                        
                        // Render assets using edge-based alignment
                        ForEach(assets.filter { $0.isVisible }) { asset in
                            // Use alignment-based positioning if available, fallback to percentage
                            if let alignment = asset.alignment {
                                AlignmentBasedAssetView(
                                    asset: asset,
                                    isSelected: selectedAsset?.id == asset.id,
                                    canvasSize: canvasGeometry.size,
                                    alignment: alignment,
                                    onSelect: {
                                        selectedAsset = asset
                                    },
                                    onUpdate: { updatedAsset in
                                        updateAsset(updatedAsset)
                                    },
                                    onEdit: { asset in
                                        selectedAsset = asset
                                        if asset.editableType != .none {
                                            showingEditSheet = true
                                        }
                                    }
                                )
                                .onAppear {
                                    print("📱 CANVAS VIEW USAGE: AlignmentBasedAssetView LOADED for \(asset.type) with alignment \(alignment)")
                                }
                            } else {
                                // Fallback to percentage positioning
                                PercentagePositionedAssetView(
                                    asset: asset,
                                    isSelected: selectedAsset?.id == asset.id,
                                    canvasSize: canvasGeometry.size,
                                    onSelect: {
                                        selectedAsset = asset
                                    },
                                    onUpdate: { updatedAsset in
                                        updateAsset(updatedAsset)
                                    },
                                    onEdit: { asset in
                                        selectedAsset = asset
                                        if asset.editableType != .none {
                                            showingEditSheet = true
                                        }
                                    }
                                )
                                .onAppear {
                                    print("📱 CANVAS VIEW USAGE: PercentagePositionedAssetView LOADED for \(asset.type) at position (\(asset.position.x), \(asset.position.y))")
                                }
                            }
                        }
                    }
                }
                
                // Simple controls
                VStack {
                    HStack {
                        Button("Back") {
                            dismiss()
                        }
                        .padding()
                        
                        Spacer()
                        
                        if let selectedAsset = selectedAsset {
                            Text("Selected: \(selectedAsset.type.displayName)")
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                    
                    // Control buttons at bottom
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 16) {
                            // Edit button - only visible when an element is selected
                            if selectedAsset != nil && selectedAsset?.type == .songList {
                                Button {
                                    showingEditSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.6))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Add asset button
                            Button {
                                showingAddAssetMenu = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Capsule()
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .onAppear {
                print("🎨 VIEW APPEAR: SimpleRunCanvasView onAppear for run: \(run.name)")
                canvasSize = geometry.size
                if !hasInitializedAssets {
                    setupSimpleAssets()
                    hasInitializedAssets = true
                }
                // Calculate power song asynchronously to prevent UI blocking
                Task {
                    calculatePowerSongIfNeeded()
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                // Only update canvas size - don't regenerate assets to preserve user changes
                print("🎨 GEOMETRY CHANGE: Canvas size changed from \(canvasSize) to \(newSize) - preserving asset positions")
                canvasSize = newSize
                // Assets keep their percentage-based positions, so they'll automatically scale
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddAssetMenu) {
            SimpleAddAssetMenu(
                onAssetTypeSelected: { type in
                    addNewAsset(type: type)
                }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            if let selectedAsset = selectedAsset, selectedAsset.type == .songList {
                SongListEditSheet(
                    run: run,
                    asset: selectedAsset,
                    onSave: { updatedAsset in
                        if let index = assets.firstIndex(where: { $0.id == updatedAsset.id }) {
                            assets[index] = updatedAsset
                        }
                        showingEditSheet = false
                    }
                )
            }
        }
    }
    
    private func setupSimpleAssets() {
        print("📱 CANVAS SYSTEM: ✅ SimpleRunCanvasView is ACTIVELY USED")
        print("🎨 SIMPLE CANVAS: Setting up assets for run: \(run.name)")
        print("🎨 SIMPLE CANVAS: Canvas size: \(canvasSize)")
        print("🎨 SIMPLE CANVAS: Run has \(run.spotifyTracks?.count ?? 0) Spotify tracks")
        
        // Safety check: Don't create assets if canvas size is invalid
        guard canvasSize.width > 0 && canvasSize.height > 0 else {
            print("🎨 SIMPLE CANVAS: Canvas size is invalid, skipping asset setup")
            return
        }
        
        // Debug Spotify tracks before generating assets
        if let tracks = run.spotifyTracks {
            print("🎨 SIMPLE CANVAS: Analyzing tracks for album art:")
            let albumGroups = Dictionary(grouping: tracks) { track in
                "\(track.album ?? "Unknown")||\(track.artist)"
            }
            for (albumKey, albumTracks) in albumGroups {
                let parts = albumKey.split(separator: "||")
                let albumName = String(parts.first ?? "Unknown")
                let artistName = String(parts.last ?? "Unknown")
                print("🎨   Album: '\(albumName)' by '\(artistName)' - \(albumTracks.count) tracks")
                if albumTracks.count >= 3 {
                    let tracksWithUrls = albumTracks.filter { $0.albumImageURL != nil && !$0.albumImageURL!.isEmpty }
                    print("🎨   ✅ Qualifies for album art! Tracks with URLs: \(tracksWithUrls.count)/\(albumTracks.count)")
                    if let sampleUrl = tracksWithUrls.first?.albumImageURL {
                        print("🎨   Sample URL: \(sampleUrl)")
                    } else {
                        print("🎨   ⚠️ NO ALBUM ART URLS! Will show placeholder for now")
                        // Note: Album art enrichment will happen in background via existing progressive loading
                    }
                }
            }
        }
        
        // Use our centralized asset generation system
        assets = CanvasAsset.generateDefaultAssets(for: run, canvasSize: canvasSize)
        print("🎨 SIMPLE CANVAS: Generated \(assets.count) assets using CanvasAsset.generateDefaultAssets")
        
        // Log which positioning systems will be used
        let alignmentBasedAssets = assets.filter { $0.alignment != nil }
        let absolutePositionAssets = assets.filter { $0.alignment == nil }
        print("📱 ASSET VIEW DISTRIBUTION: \(alignmentBasedAssets.count) will use AlignmentBasedAssetView, \(absolutePositionAssets.count) will use PercentagePositionedAssetView")
        
        // Debug key assets only
        let albumArtAssets = assets.filter { $0.type == .albumArt }
        if !albumArtAssets.isEmpty {
            print("🎨 SIMPLE CANVAS: Generated \(albumArtAssets.count) album art assets")
            for asset in albumArtAssets {
                if case .albumArt(let imageURL, _, let albumName, let artistName) = asset.content {
                    print("🎨 SIMPLE CANVAS: Album art - '\(albumName)' at (\(asset.position.x), \(asset.position.y))")
                }
            }
        }
    }
    
    private func updateAsset(_ updatedAsset: CanvasAsset) {
        if let index = assets.firstIndex(where: { $0.id == updatedAsset.id }) {
            let oldPosition = assets[index].anchorPoint
            assets[index] = updatedAsset
            print("🔄 ASSET UPDATE: \(updatedAsset.type.displayName) position updated")
            print("🔄   Old position: (\(oldPosition?.x ?? 0.5), \(oldPosition?.y ?? 0.5))")
            print("🔄   New position: (\(updatedAsset.anchorPoint?.x ?? 0.5), \(updatedAsset.anchorPoint?.y ?? 0.5))")
            print("🔄   Assets array count: \(assets.count)")
        } else {
            print("🚨 ASSET UPDATE FAILED: Could not find asset with id \(updatedAsset.id) in assets array")
        }
    }
    
    private func updateAssetsWithEnrichedAlbumArt() {
        print("🎨 PRESERVING USER CHANGES: Updating album art without regenerating assets")
        // Update existing album art assets with new URLs without changing positions
        for index in assets.indices {
            if assets[index].type == .albumArt {
                if case .albumArt(_, let imageData, let albumName, let artistName) = assets[index].content {
                    // Find corresponding track for URL
                    if let tracks = run.spotifyTracks {
                        for track in tracks {
                            if track.album == albumName {
                                assets[index].content = .albumArt(
                                    imageURL: track.albumImageURL,
                                    imageData: imageData,
                                    albumName: albumName,
                                    artistName: artistName
                                )
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateAssetsWithPowerSong() {
        print("🎨 PRESERVING USER CHANGES: Updating power song without regenerating assets")
        // Update existing power song asset without changing position
        for index in assets.indices {
            if assets[index].type == .powerSong {
                if let powerSong = run.powerSong {
                    assets[index].content = .powerSong(powerSong, pace: run.powerSongPacePerMile)
                }
                break
            }
        }
    }
    
    private func addNewAsset(type: AssetType) {
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        
        var newAsset: CanvasAsset?
        
        switch type {
        case .text:
            newAsset = CanvasAsset(
                type: .text,
                content: .text("New Text"),
                position: CGPoint(x: centerX, y: centerY),
                fontSize: 24,
                fontWeight: .medium,
                editableType: .text
            )
            
        case .image:
            newAsset = CanvasAsset(
                type: .image,
                content: .image(nil),
                position: CGPoint(x: centerX, y: centerY),
                editableType: .image
            )
            
        case .songList:
            print("🎵 DEBUG [addNewAsset]: Adding song list asset")
            newAsset = CanvasAsset.createSongList(for: run, position: CGPoint(x: centerX, y: centerY))
            if let asset = newAsset {
                print("🎵 DEBUG [addNewAsset]: Song list asset created with content type: \(asset.content)")
            }
            
        case .powerSong:
            newAsset = CanvasAsset.createPowerSong(for: run, position: CGPoint(x: centerX, y: centerY))
            
        case .albumArt:
            // For album art, use the first available album with 3+ songs
            if let firstAlbum = run.availableAlbumArt.first {
                newAsset = CanvasAsset.createAlbumArt(
                    imageURL: firstAlbum.imageURL,
                    imageData: nil,
                    albumName: firstAlbum.albumName,
                    artistName: firstAlbum.artistName,
                    position: CGPoint(x: centerX, y: centerY)
                )
            }
            
        default:
            return
        }
        
        if let asset = newAsset {
            withAnimation(.spring(response: 0.4)) {
                assets.append(asset)
            }
        }
    }
    
    
    @MainActor
    private func enrichAlbumArtForRun(_ runActivity: RunActivity) async {
        print("🎨 Starting album art enrichment for run: \(runActivity.name)")
        
        // First, check Spotify authentication status
        print("🎨 Spotify authentication status: \(SpotifyService.shared.isAuthenticated)")
        guard SpotifyService.shared.isAuthenticated else {
            print("🚨 Spotify not authenticated - cannot enrich album art")
            return
        }
        
        guard let tracks = runActivity.spotifyTracks, !tracks.isEmpty else {
            print("🎨 No tracks available for enrichment")
            return
        }
        
        // Find tracks that need album art enrichment (empty/nil albumImageURL)
        let tracksNeedingEnrichment = tracks.filter { track in
            let needsEnrichment = track.albumImageURL == nil || track.albumImageURL!.isEmpty
            if needsEnrichment {
                print("🎨 Track '\(track.name)' needs enrichment - albumImageURL: \(track.albumImageURL ?? "nil")")
            }
            return needsEnrichment
        }
        
        print("🎨 Found \(tracksNeedingEnrichment.count) tracks needing album art enrichment out of \(tracks.count) total")
        
        guard !tracksNeedingEnrichment.isEmpty else {
            print("🎨 All tracks already have album art URLs - no enrichment needed")
            return
        }
        
        do {
            print("🎨 Calling SpotifyService.enrichTracksWithAlbumArt for \(tracksNeedingEnrichment.count) tracks...")
            let enrichedTracks = await SpotifyService.shared.enrichTracksWithAlbumArt(tracksNeedingEnrichment)
            print("🎨 Successfully enriched \(enrichedTracks.count) tracks with album art")
            
            // Update the run with enriched tracks
            var updatedTracks = tracks
            var successfulUpdates = 0
            
            for enrichedTrack in enrichedTracks {
                if let index = updatedTracks.firstIndex(where: { $0.id == enrichedTrack.id }) {
                    updatedTracks[index] = enrichedTrack
                    successfulUpdates += 1
                    print("🎨 ✅ Updated track '\(enrichedTrack.name)' with album art URL: \(enrichedTrack.albumImageURL ?? "nil")")
                }
            }
            
            if successfulUpdates > 0 {
                // Update the run binding to trigger UI refresh
                var updatedRun = run
                updatedRun.spotifyTracks = updatedTracks
                run = updatedRun
                
                print("🎨 ✅ Album art enrichment completed successfully - updated \(successfulUpdates) tracks")
                
                // Clear selection before regenerating to prevent crashes
                selectedAsset = nil
                
                // Update existing assets with enriched album art instead of regenerating
                updateAssetsWithEnrichedAlbumArt()
            } else {
                print("🎨 ⚠️ No tracks were successfully updated")
            }
            
        } catch {
            print("🚨 Failed to enrich album art: \(error)")
            print("🚨 Error details: \(error.localizedDescription)")
            if let error = error as NSError? {
                print("🚨 Error domain: \(error.domain), code: \(error.code)")
                print("🚨 User info: \(error.userInfo)")
            }
        }
    }
    
    // MARK: - Album Art Enrichment
    
    private func enrichAlbumArtForRun() async {
        guard let tracks = run.spotifyTracks, !tracks.isEmpty else {
            print("🎨 ENRICH: No tracks to enrich")
            return
        }
        
        // Find tracks that need album art URLs
        let tracksNeedingArt = tracks.filter { track in
            track.albumImageURL == nil || track.albumImageURL?.isEmpty == true
        }
        
        guard !tracksNeedingArt.isEmpty else {
            print("🎨 ENRICH: All tracks already have album art")
            return
        }
        
        print("🎨 ENRICH: Enriching \(tracksNeedingArt.count) tracks with album art")
        
        do {
            let enrichedTracks = await SpotifyService.shared.enrichTracksWithAlbumArt(tracksNeedingArt)
            
            await MainActor.run {
                // Update the run's tracks with enriched album art
                var updatedTracks = run.spotifyTracks ?? []
                
                for enrichedTrack in enrichedTracks {
                    if let index = updatedTracks.firstIndex(where: { $0.id == enrichedTrack.id }) {
                        updatedTracks[index] = enrichedTrack
                    }
                }
                
                run.spotifyTracks = updatedTracks
                
                print("🎨 ENRICH: ✅ Updated run with enriched album art")
                
                // Update existing assets with new album art URLs instead of regenerating
                updateAssetsWithEnrichedAlbumArt()
            }
        } catch {
            print("🎨 ENRICH: ❌ Failed to enrich album art: \(error)")
        }
    }
    
    // MARK: - Power Song Calculation
    
    private func calculatePowerSongIfNeeded() {
        // Only calculate if Power Song is not already calculated
        guard run.powerSong == nil else {
            print("🔥 POWER SONG: Already calculated for run: \(run.name)")
            return
        }
        
        // Only calculate if we have Spotify tracks
        guard let tracks = run.spotifyTracks, !tracks.isEmpty else {
            print("🔥 POWER SONG: No Spotify tracks available for run: \(run.name)")
            return
        }
        
        // Limit to recent runs (30 days for on-demand calculation)
        let runAge = Date().timeIntervalSince(run.date)
        let maxAgeForOnDemand = 30 * 24 * 60 * 60.0 // 30 days in seconds
        
        guard runAge <= maxAgeForOnDemand else {
            print("🔥 POWER SONG: Run too old for on-demand calculation: \(run.name)")
            return
        }
        
        print("🔥 POWER SONG: Starting calculation for run: \(run.name)")
        
        Task {
            do {
                guard let activityId = Int(run.id) else {
                    print("🔥 POWER SONG: Invalid activity ID: \(run.id)")
                    return
                }
                
                let streams = try await StravaService.shared.fetchActivityStreams(id: activityId, types: ["time", "latlng"])
                
                // Calculate Power Song using the same logic (off main thread)
                var updatedRun = run
                DataConversionService.shared.calculatePowerSong(for: &updatedRun, from: streams)
                
                await MainActor.run {
                    // Update run on main thread
                    run = updatedRun
                    
                    if let powerSong = run.powerSong {
                        let pace = run.powerSongPacePerMile ?? "Unknown"
                        print("🔥 POWER SONG SUCCESS: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace)")
                        
                        // Update existing assets with power song instead of regenerating
                        updateAssetsWithPowerSong()
                    } else {
                        print("🔥 POWER SONG: No Power Song calculated for \(run.name)")
                    }
                }
            } catch {
                print("🔥 POWER SONG ERROR: Failed to calculate for \(run.name): \(error)")
            }
        }
    }
}

// MARK: - Alignment Extension

extension Alignment {
    func asCGPoint(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeading: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: size.width / 2, y: 0)
        case .topTrailing: return CGPoint(x: size.width, y: 0)
        case .leading: return CGPoint(x: 0, y: size.height / 2)
        case .center: return CGPoint(x: size.width / 2, y: size.height / 2)
        case .trailing: return CGPoint(x: size.width, y: size.height / 2)
        case .bottomLeading: return CGPoint(x: 0, y: size.height)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height)
        case .bottomTrailing: return CGPoint(x: size.width, y: size.height)
        default: return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }
}

// MARK: - Percentage-Based Positioned Asset View (Unit Coordinate Space 0.0-1.0)

struct PercentagePositionedAssetView: View {
    let asset: CanvasAsset
    let isSelected: Bool
    let canvasSize: CGSize
    let onSelect: () -> Void
    let onUpdate: (CanvasAsset) -> Void
    var onEdit: ((CanvasAsset) -> Void)? = nil
    
    // Gesture state for interactions
    @State private var gestureMode: GestureMode = .none
    @State private var dragOffset: CGSize = .zero
    
    enum GestureMode {
        case none, dragging, scaling, rotating
    }
    
    
    var body: some View {
        Group {
            switch asset.type {
            case .titleDistance:
                titleDistanceView
            case .stats:
                statsView
            case .location:
                locationView
            case .route:
                percentageRouteView
            case .songList:
                songListView
            case .powerSong:
                powerSongView
            case .albumArt:
                albumArtView
            default:
                EmptyView()
            }
        }
        .scaleEffect(asset.scale, anchor: .center)
        .rotationEffect(.degrees(asset.rotation), anchor: .center)
        .position(
            x: (asset.anchorPoint?.x ?? 0.5) * canvasSize.width + dragOffset.width,
            y: (asset.anchorPoint?.y ?? 0.5) * canvasSize.height + dragOffset.height
        )
        .overlay(
            Group {
                if isSelected {
                    // Simple selection indicator
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
        )
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            if let onEdit = onEdit {
                onEdit(asset)
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    // Only allow dragging if element is already selected
                    if isSelected && (gestureMode == .none || gestureMode == .dragging) {
                        gestureMode = .dragging
                        
                        // Update visual position in real-time with drag offset
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    print("🎯 DRAG ENDED: Asset \(asset.type.displayName), gestureMode: \(gestureMode), isSelected: \(isSelected)")
                    print("🎯 DRAG ENDED: Translation: (\(value.translation.width), \(value.translation.height))")
                    
                    if gestureMode == .dragging && isSelected {
                        // Apply final position and reset drag offset
                        let oldX = asset.anchorPoint?.x ?? 0.5
                        let oldY = asset.anchorPoint?.y ?? 0.5
                        let newX = max(0.0, min(1.0, oldX + value.translation.width / canvasSize.width))
                        let newY = max(0.0, min(1.0, oldY + value.translation.height / canvasSize.height))
                        
                        print("🎯 DRAG CALCULATION:")
                        print("🎯   Canvas size: \(canvasSize)")
                        print("🎯   Old anchor: (\(oldX), \(oldY))")
                        print("🎯   Translation pixels: (\(value.translation.width), \(value.translation.height))")
                        print("🎯   Translation percentage: (\(value.translation.width / canvasSize.width), \(value.translation.height / canvasSize.height))")
                        print("🎯   New anchor (before clamp): (\(oldX + value.translation.width / canvasSize.width), \(oldY + value.translation.height / canvasSize.height))")
                        print("🎯   New anchor (final): (\(newX), \(newY))")
                        
                        var updatedAsset = asset
                        updatedAsset.anchorPoint = CGPoint(x: newX, y: newY)
                        print("🎯 CALLING onUpdate with updated asset...")
                        onUpdate(updatedAsset)
                        print("🎯 onUpdate call completed")
                        
                        dragOffset = .zero
                        gestureMode = .none
                        print("🎯 Reset dragOffset and gestureMode")
                    } else {
                        print("🎯 DRAG IGNORED: gestureMode=\(gestureMode), isSelected=\(isSelected)")
                        dragOffset = .zero
                        gestureMode = .none
                    }
                }
        )
        .simultaneousGesture(
            MagnificationGesture(minimumScaleDelta: 0.01)
                .onChanged { value in
                    // Only allow scaling if element is already selected
                    if isSelected && (gestureMode == .none || gestureMode == .scaling) {
                        gestureMode = .scaling
                        
                        // Update scale in real-time during magnification
                        let newScale = max(0.3, min(3.0, asset.scale * value))
                        var updatedAsset = asset
                        updatedAsset.scale = newScale
                        onUpdate(updatedAsset)
                    }
                }
                .onEnded { value in
                    if gestureMode == .scaling && isSelected {
                        print("🔍 SCALE COMPLETE: Final scale \(asset.scale)")
                        gestureMode = .none
                    } else {
                        gestureMode = .none
                    }
                }
        )
        .simultaneousGesture(
            RotationGesture(minimumAngleDelta: .degrees(1))
                .onChanged { value in
                    // Only allow rotation if element is already selected
                    if isSelected && (gestureMode == .none || gestureMode == .rotating) {
                        gestureMode = .rotating
                        
                        // Update rotation in real-time during rotation
                        let newRotation = (asset.rotation + value.degrees).truncatingRemainder(dividingBy: 360)
                        var updatedAsset = asset
                        updatedAsset.rotation = newRotation
                        onUpdate(updatedAsset)
                    }
                }
                .onEnded { value in
                    if gestureMode == .rotating && isSelected {
                        print("🔄 ROTATE COMPLETE: Final rotation \(asset.rotation)°")
                        gestureMode = .none
                    } else {
                        gestureMode = .none
                    }
                }
        )
    }
    
    // Asset view implementations (same as AlignedAssetView)
    private var titleDistanceView: some View {
        VStack(spacing: 4) {
            if case .titleDistance(let title, let distance, let unit) = asset.content {
                Text("\(String(format: "%.2f", distance)) \(unit)")
                    .font(.custom("Helvetica Neue", size: 32))
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(title.lowercased())
                    .font(.custom("Helvetica Neue", size: 20))
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var statsView: some View {
        HStack(spacing: 12) {
            if case .stats(let stats) = asset.content {
                Text(stats.date)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("•")
                    .font(.custom("Helvetica Neue", size: 11))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(stats.time)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("•")
                    .font(.custom("Helvetica Neue", size: 11))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(stats.pace)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                if let weather = stats.weather {
                    Text("•")
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(weather)
                        .font(.custom("Helvetica Neue", size: 11))
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var locationView: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.system(size: 12))
                .foregroundColor(asset.color)
            Text(asset.content.displayText)
                .font(.custom("Helvetica Neue", size: 12))
                .fontWeight(.medium)
                .foregroundColor(asset.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var percentageRouteView: some View {
        Group {
            if case .route(let coordinates) = asset.content {
                RoutePathView(
                    coordinates: coordinates,
                    songPositions: nil,
                    lineWidth: 3.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets.first
                )
                .frame(width: 150, height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
            }
        }
    }
    
    private var songListView: some View {
        Group {
            if case .songList(let tracks, let powerSongId) = asset.content {
                VStack(alignment: .leading, spacing: 4) { // Add spacing between lines
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        let isPowerSong = track.id == powerSongId
                        
                        HStack(spacing: 12) {
                            if isPowerSong {
                                Text("🔥")
                                    .font(.system(size: 16))
                                    .frame(width: 24, alignment: .leading)
                            } else {
                                Text(romanNumeral(for: index + 1))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 24, alignment: .leading)
                            }
                            
                            Text("\(track.name.lowercased()) - \(track.artist.lowercased())")
                                .font(.custom(asset.fontFamily ?? "Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(isPowerSong ? .orange : asset.color)
                                .lineLimit(1)
                                .padding(.horizontal, 12) // Padding inside the background
                                .padding(.vertical, 6) // Vertical padding inside background
                                .background(
                                    // Background that fits the text content
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(asset.showBlackOutline ? 0.8 : 0.4))
                                )
                        }
                    }
                }
                .overlay(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                )
            }
        }
    }
    
    private var powerSongView: some View {
        Group {
            if case .powerSong(let track, let pace) = asset.content {
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: asset.fontSize * 2.5))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name.lowercased())
                            .font(.system(size: asset.fontSize * 1.2, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist.lowercased())
                            .font(.system(size: asset.fontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        if let pace = pace {
                            HStack(spacing: 1) {
                                Text(pace)
                                    .font(.system(size: asset.fontSize * 1.1, weight: .medium))
                                    .foregroundColor(.white)
                                Text("per mile")
                                    .font(.system(size: asset.fontSize * 0.8, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.4),
                                    Color.red.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    private var albumArtView: some View {
        Group {
            if case .albumArt(let imageURL, let imageData, let albumName, let artistName) = asset.content {
                Group {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                print("🎨 ALBUM ART RENDER: ✅ Cached image displayed for '\(albumName)'")
                            }
                    } else if let imageURL = imageURL, let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url, albumName: albumName, artistName: artistName)
                    } else {
                        // Placeholder for album art
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text(albumName.prefix(12))
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                            )
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
            }
        }
    }
    
    private func romanNumeral(for number: Int) -> String {
        let romanNumerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", 
                           "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
        return number <= romanNumerals.count ? romanNumerals[number - 1] : "\(number)"
    }
}

struct SimpleAddAssetMenu: View {
    let onAssetTypeSelected: (AssetType) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let assetTypes: [AssetType] = [.text, .image, .songList, .powerSong, .albumArt]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Add Element")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                ForEach(assetTypes, id: \.self) { type in
                    Button(action: {
                        onAssetTypeSelected(type)
                        dismiss()
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: type.systemIcon)
                                .font(.system(size: 30))
                                .foregroundColor(.blue)
                            
                            Text(type.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .presentationDetents([.height(400)])
    }
}


// MARK: - Song List Edit Sheet

struct SongListEditSheet: View {
    let run: RunActivity
    let asset: CanvasAsset
    let onSave: (CanvasAsset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSongs: Set<String> = []
    @State private var selectedFont: String = "Helvetica Neue"
    @State private var textColor: Color = .white
    @State private var showBlackOutline: Bool = true
    
    private let availableFonts = [
        ("Helvetica Neue", "HelveticaNeue"),
        ("Arial", "Arial"),
        ("Georgia", "Georgia"),
        ("Times New Roman", "TimesNewRomanPSMT"),
        ("Futura", "Futura"),
        ("Avenir", "Avenir")
    ]
    private let maxSongs = 20
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Edit Song List")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Preview Section with sample track
                    VStack(spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Preview card showing how the font/color will look
                        HStack(spacing: 12) {
                            Text("i")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, alignment: .leading)
                            
                            Text("sample track - artist name")
                                .font(.custom(selectedFont == "Helvetica Neue" ? "HelveticaNeue" : selectedFont, size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(textColor)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(showBlackOutline ? Color.black.opacity(0.8) : Color.clear)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Divider()
                    .padding(.vertical, 16)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Song Selection Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Songs (\(selectedSongs.count)/\(maxSongs))")
                                    .font(.headline)
                                
                                Spacer()
                                
                                // Select All / Clear buttons
                                HStack(spacing: 12) {
                                    Button("Clear") {
                                        selectedSongs.removeAll()
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .disabled(selectedSongs.isEmpty)
                                    
                                    Button("Show All") {
                                        showAllSongs()
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                }
                            }
                            
                            // Song list
                            if let tracks = run.spotifyTracks, !tracks.isEmpty {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                        HStack(spacing: 12) {
                                            Button {
                                                toggleSongSelection(track.id)
                                            } label: {
                                                Image(systemName: selectedSongs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedSongs.contains(track.id) ? .blue : .gray)
                                                    .font(.title3)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .lineLimit(1)
                                                Text(track.artist)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer()
                                            
                                            if track.id == run.powerSong?.id {
                                                Text("🔥")
                                                    .font(.system(size: 16))
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedSongs.contains(track.id) ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                        )
                                        .animation(.easeInOut(duration: 0.2), value: selectedSongs.contains(track.id))
                                    }
                                }
                            } else {
                                Text("No songs available")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Styling Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Styling")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(spacing: 20) {
                                // Font picker with previews
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Font")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                        ForEach(availableFonts, id: \.0) { fontName, fontIdentifier in
                                            Button {
                                                selectedFont = fontName
                                            } label: {
                                                Text(fontName)
                                                    .font(.custom(fontIdentifier, size: 16))
                                                    .foregroundColor(.primary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(selectedFont == fontName ? Color.blue.opacity(0.2) : Color(.systemGray6))
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 8)
                                                                    .stroke(selectedFont == fontName ? Color.blue : Color.clear, lineWidth: 2)
                                                            )
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                // Text color picker - replaced with preset colors to avoid ColorPicker crashes
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Text Color")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                                        let colors: [Color] = [.white, .black, .red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan, .gray, .brown]
                                        ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                                            Button {
                                                textColor = color
                                            } label: {
                                                Circle()
                                                    .fill(color)
                                                    .frame(width: 32, height: 32)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(textColor == color ? Color.blue : Color.gray.opacity(0.3), lineWidth: textColor == color ? 3 : 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                // Black outline toggle - simplified to prevent freezing
                                HStack {
                                    Text("Text Shadow")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    
                                    Button {
                                        showBlackOutline.toggle()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: showBlackOutline ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(showBlackOutline ? .blue : .gray)
                                            Text(showBlackOutline ? "Enabled" : "Disabled")
                                                .font(.subheadline)
                                                .foregroundColor(showBlackOutline ? .blue : .gray)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedSongs.isEmpty)
                }
            }
        }
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            setupInitialState()
        }
    }
    
    private func setupInitialState() {
        // Initialize selected songs from the current asset
        if case .songList(let tracks, _) = asset.content {
            selectedSongs = Set(tracks.map { $0.id })
        } else if let allTracks = run.spotifyTracks {
            // Default to first 10 songs
            selectedSongs = Set(allTracks.prefix(10).map { $0.id })
        }
        
        // Initialize styling from current asset
        textColor = asset.color
        selectedFont = asset.fontFamily ?? "Helvetica Neue"
        showBlackOutline = asset.showBlackOutline || true // Default to enabled
    }
    
    private func toggleSongSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else if selectedSongs.count < maxSongs {
            selectedSongs.insert(songId)
        }
    }
    
    private func showAllSongs() {
        guard let allTracks = run.spotifyTracks else { return }
        selectedSongs = Set(allTracks.map { $0.id })
    }
    
    private func saveChanges() {
        guard let allTracks = run.spotifyTracks else { return }
        
        // Filter and order selected tracks
        let filteredTracks = allTracks.filter { selectedSongs.contains($0.id) }
        
        // Create updated asset with new song selection and styling
        var updatedAsset = asset
        updatedAsset.content = .songList(tracks: filteredTracks, powerSongId: run.powerSong?.id)
        
        // Update the styling properties
        updatedAsset.color = textColor
        updatedAsset.fontFamily = selectedFont
        updatedAsset.showBlackOutline = showBlackOutline
        
        onSave(updatedAsset)
        dismiss()
    }
}

// MARK: - Edge-Based Alignment Asset View (SwiftUI Alignment System)

struct AlignmentBasedAssetView: View {
    let asset: CanvasAsset
    let isSelected: Bool
    let canvasSize: CGSize
    let alignment: CanvasAlignment
    let onSelect: () -> Void
    let onUpdate: (CanvasAsset) -> Void
    var onEdit: ((CanvasAsset) -> Void)? = nil
    
    // Gesture state for interactions
    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentRotation: Double = 0.0
    @State private var gestureMode: GestureMode = .none
    
    enum GestureMode {
        case none, dragging, scaling, rotating
    }
    
    // Calculate vertical spacing offset to prevent overlapping
    private var verticalSpacingOffset: CGPoint {
        switch asset.type {
        case .titleDistance:
            return CGPoint(x: 0, y: -220) // Move title much higher up
        case .stats:
            return CGPoint(x: 0, y: 0) // Stats at top-right (base position)
        case .location:
            return CGPoint(x: 0, y: 40) // Location below stats
        case .route:
            return CGPoint(x: 0, y: -80) // Move route map higher up from center
        case .songList:
            return CGPoint(x: 0, y: 200) // Song list lower on left
        case .powerSong:
            return CGPoint(x: 0, y: 0) // Power song at bottom-right (base position)
        default:
            return CGPoint(x: 0, y: 0)
        }
    }
    
    var body: some View {
        ZStack {
            // Use overlay with proper SwiftUI alignment
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: alignment.swiftUIAlignment) {
                    assetContentView
                        .scaleEffect(asset.scale * currentScale, anchor: .center)
                        .rotationEffect(.degrees(asset.rotation + currentRotation), anchor: .center)
                        .offset(x: dragOffset.width + verticalSpacingOffset.x, 
                               y: dragOffset.height + verticalSpacingOffset.y)
                        .onTapGesture {
                            onSelect()
                        }
                        .onTapGesture(count: 2) {
                            if let onEdit = onEdit {
                                onEdit(asset)
                            }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    // Only allow dragging if element is already selected
                                    if isSelected && (gestureMode == .none || gestureMode == .dragging) {
                                        gestureMode = .dragging
                                        
                                        // Update visual position in real-time with drag offset
                                        dragOffset = value.translation
                                    }
                                }
                                .onEnded { value in
                                    if gestureMode == .dragging && isSelected {
                                        // Apply final position and reset drag offset
                                        let alignmentCenter = alignment.swiftUIAlignment.asCGPoint(in: canvasSize)
                                        let currentX = (alignmentCenter.x + verticalSpacingOffset.x) / canvasSize.width
                                        let currentY = (alignmentCenter.y + verticalSpacingOffset.y) / canvasSize.height
                                        
                                        let newX = max(0.0, min(1.0, currentX + value.translation.width / canvasSize.width))
                                        let newY = max(0.0, min(1.0, currentY + value.translation.height / canvasSize.height))
                                        
                                        var updatedAsset = asset
                                        updatedAsset.anchorPoint = CGPoint(x: newX, y: newY)
                                        updatedAsset.alignment = nil // Switch to percentage positioning
                                        print("🎯 ALIGNMENT DRAG: Updating asset \(asset.type.displayName) to position (\(newX), \(newY))")
                                        onUpdate(updatedAsset)
                                        print("🎯 ALIGNMENT DRAG: Called onUpdate with new position")
                                        
                                        dragOffset = .zero
                                        gestureMode = .none
                                        print("🎯 ALIGNMENT DRAG: Reset drag offset and gesture mode")
                                    } else {
                                        dragOffset = .zero
                                        gestureMode = .none
                                    }
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture(minimumScaleDelta: 0.01)
                                .onChanged { value in
                                    // Only allow scaling if element is already selected
                                    if isSelected && (gestureMode == .none || gestureMode == .scaling) {
                                        gestureMode = .scaling
                                        currentScale = value
                                    }
                                }
                                .onEnded { value in
                                    if gestureMode == .scaling && isSelected {
                                        var updatedAsset = asset
                                        updatedAsset.scale = max(0.3, min(3.0, asset.scale * value))
                                        onUpdate(updatedAsset)
                                        
                                        // Delayed reset to prevent snap-back visual effect
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            currentScale = 1.0
                                            gestureMode = .none
                                        }
                                        
                                        print("🔍 ALIGNMENT SCALE COMPLETE: Updated \(asset.type) scale to \(updatedAsset.scale)")
                                    } else {
                                        currentScale = 1.0
                                        gestureMode = .none
                                    }
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture(minimumAngleDelta: .degrees(1))
                                .onChanged { value in
                                    // Only allow rotation if element is already selected
                                    if isSelected && (gestureMode == .none || gestureMode == .rotating) {
                                        gestureMode = .rotating
                                        currentRotation = value.degrees
                                    }
                                }
                                .onEnded { value in
                                    if gestureMode == .rotating && isSelected {
                                        var updatedAsset = asset
                                        updatedAsset.rotation = (asset.rotation + value.degrees).truncatingRemainder(dividingBy: 360)
                                        onUpdate(updatedAsset)
                                        
                                        // Delayed reset to prevent snap-back visual effect
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            currentRotation = 0
                                            gestureMode = .none
                                        }
                                        
                                        print("🔄 ALIGNMENT ROTATE COMPLETE: Updated \(asset.type) rotation to \(updatedAsset.rotation)°")
                                    } else {
                                        currentRotation = 0
                                        gestureMode = .none
                                    }
                                }
                        )
                        .padding(.all, 20) // Padding from edges
                }
        }
    }
    
    @ViewBuilder
    private var assetContentView: some View {
        Group {
            switch asset.type {
            case .titleDistance:
                titleDistanceView
            case .stats:
                statsView
            case .location:
                locationView
            case .route:
                alignmentRouteView
            case .songList:
                songListView
            case .powerSong:
                powerSongView
            default:
                EmptyView()
            }
        }
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.8), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
            }
        )
    }
    
    // Asset view implementations (reuse from PercentagePositionedAssetView)
    private var titleDistanceView: some View {
        VStack(spacing: 4) {
            if case .titleDistance(let title, let distance, let unit) = asset.content {
                Text("\(String(format: "%.2f", distance)) \(unit)")
                    .font(.custom("Helvetica Neue", size: 32))
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(title.lowercased())
                    .font(.custom("Helvetica Neue", size: 20))
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
    }
    
    private var statsView: some View {
        HStack(spacing: 12) {
            if case .stats(let stats) = asset.content {
                Text(stats.date)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("•")
                    .font(.custom("Helvetica Neue", size: 11))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(stats.time)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("•")
                    .font(.custom("Helvetica Neue", size: 11))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(stats.pace)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                if let weather = stats.weather {
                    Text("•")
                        .font(.custom("Helvetica Neue", size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(weather)
                        .font(.custom("Helvetica Neue", size: 11))
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    private var locationView: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.system(size: 12))
                .foregroundColor(asset.color)
            Text(asset.content.displayText)
                .font(.custom("Helvetica Neue", size: 12))
                .fontWeight(.medium)
                .foregroundColor(asset.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
    }
    
    private var alignmentRouteView: some View {
        Group {
            if case .route(let coordinates) = asset.content {
                RoutePathView(
                    coordinates: coordinates,
                    songPositions: nil,
                    lineWidth: 3.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets.first
                )
                .frame(width: 150, height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                )
            }
        }
    }
    
    private var songListView: some View {
        Group {
            if case .songList(let tracks, let powerSongId) = asset.content {
                VStack(alignment: .leading, spacing: 4) { // Add spacing between lines
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        let isPowerSong = track.id == powerSongId
                        
                        HStack(spacing: 12) {
                            if isPowerSong {
                                Text("🔥")
                                    .font(.system(size: 16))
                                    .frame(width: 24, alignment: .leading)
                            } else {
                                Text(romanNumeral(for: index + 1))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 24, alignment: .leading)
                            }
                            
                            Text("\(track.name.lowercased()) - \(track.artist.lowercased())")
                                .font(.custom(asset.fontFamily ?? "Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(isPowerSong ? .orange : asset.color)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8) // Reduced padding for content-fitting background
                        .padding(.vertical, 4) // Reduced vertical padding
                        .background(
                            // Background that fits the content only
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(asset.showBlackOutline ? 0.8 : 0.4))
                        )
                    }
                }
            }
        }
    }
    
    private var powerSongView: some View {
        Group {
            if case .powerSong(let track, let pace) = asset.content {
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: asset.fontSize * 2.5))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name.lowercased())
                            .font(.system(size: asset.fontSize * 1.2, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist.lowercased())
                            .font(.system(size: asset.fontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        if let pace = pace {
                            HStack(spacing: 1) {
                                Text(pace)
                                    .font(.system(size: asset.fontSize * 1.1, weight: .medium))
                                    .foregroundColor(.white)
                                Text("per mile")
                                    .font(.system(size: asset.fontSize * 0.8, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.4),
                                    Color.red.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    private var finalRouteView: some View {
        Group {
            if case .route(let coordinates) = asset.content {
                RoutePathView(
                    coordinates: coordinates,
                    songPositions: nil,
                    lineWidth: 3.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets.first
                )
                .frame(width: 150, height: 150) // Made map bigger
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2) // Added bigger outline
                        )
                )
            }
        }
    }
    
    private func romanNumeral(for number: Int) -> String {
        let romanNumerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", 
                           "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
        return number <= romanNumerals.count ? romanNumerals[number - 1] : "\(number)"
    }
}

// MARK: - Cached Async Image for Album Art

struct CachedAsyncImage: View {
    let url: URL
    let albumName: String
    let artistName: String
    
    @State private var cachedImageData: Data?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let cachedImageData = cachedImageData,
               let uiImage = UIImage(data: cachedImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        print("🎨 CACHED: ✅ Instant load for '\(albumName)'")
                    }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                print("🎨 CACHED: ✅ Downloaded '\(albumName)', saving to cache")
                                Task {
                                    await saveImageToCache()
                                }
                            }
                    case .failure(_):
                        albumArtPlaceholder
                    case .empty:
                        albumArtPlaceholder
                    @unknown default:
                        albumArtPlaceholder
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadCachedImage()
            }
        }
    }
    
    private var albumArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(albumName.prefix(12))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            )
    }
    
    private func loadCachedImage() async {
        let cacheKey = "\(albumName)_\(artistName)".lowercased().replacingOccurrences(of: " ", with: "_")
        
        do {
            if let imageData = try await FirestoreService.shared.getCachedAlbumArt(cacheKey: cacheKey) {
                await MainActor.run {
                    self.cachedImageData = imageData
                    print("🎨 CACHED: ✅ Loaded from Firebase cache for '\(albumName)'")
                }
            }
        } catch {
            print("🎨 CACHED: No cache found for '\(albumName)', will download")
        }
    }
    
    private func saveImageToCache() async {
        let cacheKey = "\(albumName)_\(artistName)".lowercased().replacingOccurrences(of: " ", with: "_")
        
        do {
            let (imageData, _) = try await URLSession.shared.data(from: url)
            try await FirestoreService.shared.cacheAlbumArt(cacheKey: cacheKey, imageData: imageData)
            
            await MainActor.run {
                self.cachedImageData = imageData
                print("🎨 CACHED: ✅ Saved '\(albumName)' to Firebase cache")
            }
        } catch {
            print("🎨 CACHED: ❌ Failed to cache '\(albumName)': \(error)")
        }
    }
}

// MARK: - RunStackCardView for Card Stack Display

struct RunStackCardView: View {
    let run: RunActivity
    @State private var photoBackground: RunPhotoBackground?
    @State private var isLoadingPhoto = false
    
    var body: some View {
        ZStack {
            // Background layer - SOLID photo or smart gradient (no transparency)
            Group {
                // First try the custom photo background we loaded
                if let photoBackground = photoBackground {
                    PhotoBackgroundView(photoBackground: photoBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                // Then try the run's stored background photo
                else if let runPhotoBackground = run.backgroundPhoto,
                        runPhotoBackground.photoData != nil {
                    PhotoBackgroundView(photoBackground: runPhotoBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } 
                // Fallback to smart gradients with variety
                else {
                    smartFallbackGradient(for: run)
                }
            }
            
            // SOLID dark overlay for text readability (prevents card bleed-through)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.85),
                    Color.black.opacity(1.0)  // Completely opaque at bottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Route display - positioned ABOVE dark overlay for visibility
            VStack {
                Spacer()
                RoutePathView(
                    coordinates: run.routeCoordinates,
                    lineWidth: 8.0,  // Reduced thickness for cleaner look
                    colorScheme: run.weatherBasedRouteColor ?? run.colorScheme ?? RunColorScheme.presets[0]
                )
                .opacity(0.95)  // High opacity for prominence
                .frame(width: 300, height: 220)  // Large size
                .clipped()
                Spacer().frame(height: 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Content layout optimized for card stacking
            VStack(spacing: 0) {
                // TOP SECTION - Full width title and location
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.name.lowercased())
                        .font(.custom("Helvetica Neue", size: 26))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 1, y: 1)
                        .lineLimit(2)  // Optimized for 2-line titles
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                        .frame(maxWidth: .infinity, alignment: .leading) // Full width
                    
                    // Location display - full width
                    if let locationText = run.smartLocationDisplay {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                            Text(locationText.lowercased())
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)  // Allow location to wrap instead of truncating
                        }
                        .shadow(color: .black.opacity(0.8), radius: 2)
                        .frame(maxWidth: .infinity, alignment: .leading) // Full width
                    }
                    
                    // Power song - right-aligned with compact background
                    if let powerSong = run.powerSong {
                        HStack {
                            Spacer() // Push power song to the right
                            
                            HStack(spacing: 6) {
                                Text("🔥")
                                    .font(.system(size: 14))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(powerSong.name.lowercased())
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    // Add pace if available
                                    if let pace = run.powerSongPacePerMile {
                                        Text(pace + "/mi")
                                            .font(.custom("Helvetica Neue", size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                        .padding(.top, 6) // Space from location
                    }
                }
                
                Spacer()
                
                // MIDDLE SECTION - Space for route visibility
                Spacer().frame(height: 180)
                
                // MAIN DISTANCE - Large and prominent
                VStack(spacing: 4) {
                    Text(formatDistance(run.distance))
                        .font(.custom("Helvetica Neue", size: 42))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 1, y: 1)
                    
                    Text(distanceUnitAbbreviation().lowercased())
                        .font(.custom("Helvetica Neue", size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
                
                Spacer().frame(height: 20)
                
                // BOTTOM ESSENTIAL DATA STRIP - Visible when cards are stacked
                VStack(spacing: 8) {
                    // First row: Date (with day) and Time
                    HStack {
                        Text(formatDateWithDayForDisplay(run.date))
                            .font(.custom("Helvetica Neue", size: 11))
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        Text(run.compactFormattedDuration)
                            .font(.custom("Helvetica Neue", size: 11))
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // Second row: Distance, Pace, Weather
                    HStack {
                        Text("\(formatDistance(run.distance)) \(distanceUnitAbbreviation().lowercased())")
                            .font(.custom("Helvetica Neue", size: 11))
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        Text(UserPreferences.shared.formatPace(run.averagePace) + "/\(UserPreferences.shared.distanceUnit == .miles ? "mi" : "km")")
                            .font(.custom("Helvetica Neue", size: 11))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        if let weather = run.weatherData {
                            HStack(spacing: 3) {
                                Text(weather.condition.emoji)
                                    .font(.system(size: 11))
                                Text("\(Int(weather.temperature))°F")
                                    .font(.custom("Helvetica Neue", size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(1.0))  // COMPLETELY SOLID background for data strip
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 28) // Increased vertical padding for top/bottom spacing
        }
        .frame(height: 520) // Further increased height to prevent all text cutoff
        .contentShape(Rectangle())
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .onAppear {
            loadPhotoBackgroundIfNeeded()
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadPhotoBackgroundIfNeeded() {
        // Only load if we don't already have a background and aren't currently loading
        guard photoBackground == nil && !isLoadingPhoto else { return }
        
        // Skip if run already has a background photo
        guard run.backgroundPhoto == nil else { return }
        
        Task {
            await MainActor.run {
                isLoadingPhoto = true
            }
            
            // Use PhotoService to fetch photos from run timeframe
            let photos = await PhotoService.shared.fetchPhotosForRun(date: run.date, duration: run.elapsedTime)
            
            // If photos found, create a photo background with lighter filtering
            if !photos.isEmpty {
                if let selectedPhotoBackground = await PhotoService.shared.selectRandomPhoto(from: photos, filterType: .softFocus) {
                    await MainActor.run {
                        self.photoBackground = selectedPhotoBackground
                        self.isLoadingPhoto = false
                    }
                    return
                }
            }
            
            await MainActor.run {
                isLoadingPhoto = false
            }
        }
    }
    
    private func formatDateWithDayForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d"
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
        return UserPreferences.shared.distanceUnit.abbreviation.lowercased()
    }
    
    private func smartFallbackGradient(for run: RunActivity) -> LinearGradient {
        // Weather and time-based gradient variations for visual diversity
        let weatherGradients: [WeatherData.WeatherCondition: [Color]] = [
            .clear: [Color.orange, Color.yellow.opacity(0.8), Color.red.opacity(0.6)],
            .cloudy: [Color.gray, Color.blue.opacity(0.6), Color.purple.opacity(0.4)],
            .rain: [Color.blue, Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
            .snow: [Color.blue, Color.white.opacity(0.8), Color.cyan.opacity(0.6)],
            .fog: [Color.gray, Color.mint.opacity(0.6), Color.blue.opacity(0.4)],
            .thunderstorm: [Color.purple, Color.indigo.opacity(0.8), Color.black.opacity(0.6)]
        ]
        
        let timeOfDayGradients: [WeatherData.TimeOfDay: [Color]] = [
            .dawn: [Color.orange, Color.pink.opacity(0.8), Color.yellow.opacity(0.6)],
            .morning: [Color.blue, Color.cyan.opacity(0.8), Color.mint.opacity(0.6)],
            .afternoon: [Color.yellow, Color.orange.opacity(0.8), Color.red.opacity(0.6)],
            .evening: [Color.purple, Color.pink.opacity(0.8), Color.orange.opacity(0.6)],
            .night: [Color.indigo, Color.purple.opacity(0.8), Color.black.opacity(0.6)]
        ]
        
        // Prefer weather-based gradients, fallback to time of day
        if let weather = run.weatherData {
            if let weatherColors = weatherGradients[weather.condition] {
                return LinearGradient(
                    colors: weatherColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if let timeColors = timeOfDayGradients[weather.timeOfDay] {
                return LinearGradient(
                    colors: timeColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        
        // Final fallback: diverse gradients based on run ID for consistency
        let fallbackGradients: [[Color]] = [
            [Color.blue, Color.cyan.opacity(0.8), Color.teal.opacity(0.6)],
            [Color.purple, Color.pink.opacity(0.8), Color.indigo.opacity(0.6)],
            [Color.green, Color.mint.opacity(0.8), Color.teal.opacity(0.6)],
            [Color.orange, Color.yellow.opacity(0.8), Color.red.opacity(0.6)],
            [Color.red, Color.pink.opacity(0.8), Color.orange.opacity(0.6)]
        ]
        
        let gradientIndex = abs(run.id.hashValue) % fallbackGradients.count
        let selectedGradient = fallbackGradients[gradientIndex]
        
        return LinearGradient(
            colors: selectedGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    RunCardStackView(selectedRunId: .constant(nil))
        .environmentObject(FirebaseAuthService.shared)
}