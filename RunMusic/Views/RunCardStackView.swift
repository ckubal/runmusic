import SwiftUI
import CoreLocation
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
                let _ = logger.info("🎨 Navigating to canvas for run: \(run.name) (ID: \(run.id))")
                let _ = logger.info("🎨 Run has background photo: \(run.backgroundPhoto != nil)")
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
            
            // FALLBACK: If no tracks found in Firebase and Spotify is authenticated and run is recent (within 7 days), 
            // try fetching from live Spotify API
            if tracks.isEmpty && spotifyService.isAuthenticated && run.date > Date().addingTimeInterval(-7 * 24 * 60 * 60) {
                logger.info("🌐 No tracks in Firebase for recent run, falling back to Spotify API")
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
        
        return RunCardView(run: run)
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
        logger.info("🎵 CONSERVATIVE: Loading Spotify data for \(currentRuns.count) visible cards (Firebase + Spotify fallback)")
        
        for (index, run) in currentRuns.enumerated() {
            // Skip if already has Spotify data
            guard run.spotifyTracks == nil || run.spotifyTracks?.isEmpty == true else {
                logger.info("🎵 SKIP: Card [\(index)] '\(run.name)' already has \(run.spotifyTracks?.count ?? 0) tracks")
                continue
            }
            
            logger.info("🎵 LOADING: Card [\(index)] '\(run.name)' needs Spotify data")
            
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
                    maxCacheAge: isRefresh ? 0 : 24 * 60 * 60 // Force fresh if refresh, else 24hr cache
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
                            continue
                        }
                        
                        logger.info("🎵 FETCH: Run '\(runActivities[i].name)' has no tracks, fetching from Firebase...")
                        let endTime = runActivities[i].date.addingTimeInterval(runActivities[i].elapsedTime)
                        var tracks = await spotifyService.fetchImportedTracksForTimeRange(
                            startTime: runActivities[i].date,
                            endTime: endTime
                        )
                        
                        // FALLBACK: If no tracks found in Firebase and Spotify is authenticated and run is recent (within 7 days), 
                        // try fetching from live Spotify API
                        if tracks.isEmpty && spotifyService.isAuthenticated && runActivities[i].date > Date().addingTimeInterval(-7 * 24 * 60 * 60) {
                            logger.info("🌐 No tracks in Firebase for recent run, falling back to Spotify API")
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
    
    private func assignBackgroundPhotos() async {
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
            guard run.backgroundPhoto == nil else { 
                logger.info("📷 Skipping '\(run.name)' - already has photo background")
                continue 
            }
            
            logger.info("📷 Processing run '\(run.name)' (\(run.date))")
            
            // Fetch photos from the run timeframe
            let photos = await PhotoService.shared.fetchPhotosForRun(
                date: run.date,
                duration: run.elapsedTime
            )
            
            // If photos are available during run timeframe, use the first one
            if !photos.isEmpty {
                logger.info("📷 Found \(photos.count) photos during run timeframe for '\(run.name)'")
                if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                    from: photos,
                    filterType: .blur
                ) {
                    await updateRunBackground(runId: run.id, photoBackground: photoBackground)
                    logger.info("✅ Using timeframe photo for run '\(run.name)'")
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
                
                let expandedPhotos = await PhotoService.shared.fetchPhotosForRun(
                    date: expandedStartTime,
                    duration: 48 * 60 * 60 // 2 day window
                )
                
                if !expandedPhotos.isEmpty {
                    logger.info("📷 Found \(expandedPhotos.count) photos in expanded timeframe for '\(run.name)'")
                    if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                        from: expandedPhotos,
                        filterType: .blur
                    ) {
                        await updateRunBackground(runId: run.id, photoBackground: photoBackground)
                        logger.info("✅ Using same-day photo for run '\(run.name)'")
                        continue
                    } else {
                        logger.error("❌ Failed to create photo background from expanded timeframe photos for '\(run.name)'")
                    }
                } else {
                    logger.info("📷 No photos found in expanded timeframe for '\(run.name)'")
                }
                
                // Third fallback: recent photos from camera roll (most recent 50)
                let recentPhotos = await PhotoService.shared.fetchPhotosForRun(
                    date: Date().addingTimeInterval(-30 * 24 * 60 * 60), // Last 30 days
                    duration: 30 * 24 * 60 * 60 // 30 day window
                )
                
                if !recentPhotos.isEmpty {
                    if let photoBackground = await PhotoService.shared.selectRandomPhoto(
                        from: recentPhotos,
                        filterType: .blur
                    ) {
                        await updateRunBackground(runId: run.id, photoBackground: photoBackground)
                        logger.info("📷 Using recent camera roll photo as fallback for run '\(run.name)'")
                        continue
                    }
                }
                
                // Ultimate fallback: Create a default background for simulator/testing
                if let defaultBackground = await createDefaultBackground(for: run) {
                    await updateRunBackground(runId: run.id, photoBackground: defaultBackground)
                    logger.info("📷 Using default background for simulator for run '\(run.name)'")
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
    }
    
    var body: some View {
        SimpleRunCanvasView(run: $run)
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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background layer - photo background with fallback
                Group {
                    if let photoBackground = run.backgroundPhoto,
                       photoBackground.photoData != nil {
                        PhotoBackgroundView(photoBackground: photoBackground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Color(.systemGray6)
                            .ignoresSafeArea()
                    }
                }
                
                // Canvas area
                ZStack {
                    // Tap area to deselect
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedAsset = nil
                        }
                    
                    // Render single simple asset
                    ForEach(assets) { asset in
                        SimpleAssetView(
                            asset: asset,
                            isSelected: selectedAsset?.id == asset.id,
                            onSelect: {
                                selectedAsset = asset
                            },
                            onUpdate: { updatedAsset in
                                if let index = assets.firstIndex(where: { $0.id == updatedAsset.id }) {
                                    assets[index] = updatedAsset
                                }
                            }
                        )
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
                canvasSize = geometry.size
                setupSimpleAssets()
                // Calculate power song if needed
                calculatePowerSongIfNeeded()
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
        print("🎨 SIMPLE CANVAS: Setting up assets for run: \(run.name)")
        print("🎨 SIMPLE CANVAS: Canvas size: \(canvasSize)")
        var newAssets: [CanvasAsset] = []
        
        // Combined title and distance asset
        let userPrefs = UserPreferences.shared
        let distanceValue: Double
        let unit: String
        
        switch userPrefs.distanceUnit {
        case .miles:
            distanceValue = run.distance / 1609.34
            unit = "mi"
        case .kilometers:
            distanceValue = run.distance / 1000.0
            unit = "km"
        }
        
        // Stats line asset (top right) - moved to very top
        let statsCluster = StatsCluster(run: run)
        let statsAsset = CanvasAsset(
            type: .stats,
            content: .stats(statsCluster),
            position: CGPoint(x: canvasSize.width - 120, y: canvasSize.height * 0.05)
        )
        newAssets.append(statsAsset)
        
        // Location asset - moved higher with less spacing
        if let location = run.smartLocationDisplay {
            let locationAsset = CanvasAsset(
                type: .location,
                content: .location(location.lowercased()),
                position: CGPoint(x: canvasSize.width - 120, y: canvasSize.height * 0.1),
                fontSize: 12,
                fontWeight: .medium,
                color: .orange
            )
            newAssets.append(locationAsset)
        }
        
        // Title and distance - moved higher, just below location
        let titleDistanceAsset = CanvasAsset(
            type: .titleDistance,
            content: .titleDistance(title: run.name, distance: distanceValue, unit: unit),
            position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.18),
            fontSize: 32,
            fontWeight: .bold,
            color: .orange // Will be overridden by gradient
        )
        newAssets.append(titleDistanceAsset)
        
        // Add route below title if available - made bigger and positioned higher
        if !run.routeCoordinates.isEmpty {
            let routeAsset = CanvasAsset.createRoute(
                for: run,
                position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.35)
            )
            // Increase the scale to make it bigger
            var scaledRouteAsset = routeAsset
            scaledRouteAsset.scale = 1.2
            newAssets.append(scaledRouteAsset)
        }
        
        // Add song list if available - positioned from left edge with padding
        if let tracks = run.spotifyTracks, !tracks.isEmpty {
            print("🎵 SIMPLE CANVAS DEBUG - Song List Section:")
            print("  - Total tracks: \(tracks.count)")
            print("  - Visible tracks: \(tracks.filter { $0.isVisible }.count)")
            print("  - Sample track names: \(tracks.prefix(3).map { $0.name }.joined(separator: ", "))")
            print("  - Sample track isVisible values: \(tracks.prefix(3).map { $0.isVisible })")
            
            let songListAsset = CanvasAsset.createSongList(
                for: run, 
                position: CGPoint(x: 200, y: canvasSize.height * 0.7)
            )
            newAssets.append(songListAsset)
            print("🎵 SIMPLE CANVAS: Song list asset created and added to canvas")
        } else {
            print("🎵 SIMPLE CANVAS DEBUG - No Song List:")
            print("  - run.spotifyTracks is nil: \(run.spotifyTracks == nil)")
            print("  - tracks array is empty: \(run.spotifyTracks?.isEmpty ?? true)")
        }
        
        // Add power song if available - right-aligned with screen edge
        print("🔥 DEBUG: Checking power song for run: \(run.name)")
        print("🔥 DEBUG: run.powerSong exists: \(run.powerSong != nil)")
        if let powerSong = run.powerSong {
            print("🔥 DEBUG: Power song found: \(powerSong.name) by \(powerSong.artist)")
        }
        print("🔥 DEBUG: run.powerSongPacePerMile: \(run.powerSongPacePerMile ?? "nil")")
        
        if let powerSongAsset = CanvasAsset.createPowerSong(
            for: run, 
            // Position power song more conservatively to ensure it's fully visible
            position: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.75)
        ) {
            print("🔥 DEBUG: Power song asset created successfully")
            newAssets.append(powerSongAsset)
        } else {
            print("🔥 DEBUG: Failed to create power song asset - no power song data")
        }
        
        // Add album art for albums with 3+ songs
        let availableAlbumArt = run.availableAlbumArt
        print("🎨 Album Art Debug for run: \(run.name)")
        print("🎨 Available album art count: \(availableAlbumArt.count)")
        
        for (index, albumArt) in availableAlbumArt.prefix(4).enumerated() {
            // Debug logging for album art URL
            print("🎨 Album Art Debug: Album '\(albumArt.albumName)' by \(albumArt.artistName)")
            if let imageURL = albumArt.imageURL, !imageURL.isEmpty {
                print("🎨 Album Art URL: \(imageURL)")
            } else {
                print("🎨 Album Art URL: empty/nil - enrichment available in Settings")
                // DISABLED: Automatic enrichment to prevent API abuse
                // User can manually trigger enrichment from Settings if desired
            }
            
            // Position album art in a grid pattern
            let row = index / 2
            let col = index % 2
            
            let albumAsset = CanvasAsset.createAlbumArt(
                imageURL: albumArt.imageURL,
                imageData: nil, // Will be loaded asynchronously
                albumName: albumArt.albumName,
                artistName: albumArt.artistName,
                position: CGPoint(
                    x: canvasSize.width * 0.7 + CGFloat(col * 80),
                    y: canvasSize.height * 0.65 + CGFloat(row * 80)
                )
            )
            newAssets.append(albumAsset)
        }
        
        assets = newAssets
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
                
                // Force a UI refresh by regenerating assets with updated album art
                setupSimpleAssets()
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
                
                await MainActor.run {
                    // Calculate Power Song using the same logic
                    DataConversionService.shared.calculatePowerSong(for: &run, from: streams)
                    
                    if let powerSong = run.powerSong {
                        let pace = run.powerSongPacePerMile ?? "Unknown"
                        print("🔥 POWER SONG SUCCESS: '\(powerSong.name)' by \(powerSong.artist) - Pace: \(pace)")
                        
                        // Update the assets to include the new power song
                        setupSimpleAssets()
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

struct SimpleAssetView: View {
    let asset: CanvasAsset
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdate: (CanvasAsset) -> Void
    
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                switch asset.type {
                case .stats:
                    HStack {
                        Spacer()
                        statsClusterView
                    }
                    .frame(width: geometry.size.width, alignment: .trailing)
                    .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .location:
                    HStack {
                        Spacer()
                        locationAssetView
                    }
                    .frame(width: geometry.size.width, alignment: .trailing)
                    .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .titleDistance:
                    titleDistanceAssetView
                        .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .songList:
                    HStack {
                        songListAssetView
                            .overlay(
                                // Selection indicator for song list
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
                        Spacer()
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                    .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .powerSong:
                    HStack {
                        Spacer()
                        powerSongAssetView
                            .overlay(
                                // Selection indicator for power song
                                Group {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.1))
                                            )
                                    }
                                }
                            )
                    }
                    .frame(width: geometry.size.width, alignment: .trailing)
                    .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .route:
                    routeAssetView
                        .overlay(
                            // Selection indicator for route
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                }
                            }
                        )
                        .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                case .albumArt:
                    albumArtAssetView
                        .overlay(
                            // Selection indicator for album art
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
                        .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                default:
                    textAssetView
                        .position(x: asset.position.x + dragOffset.width, y: asset.position.y + dragOffset.height)
                }
            }
        }
        .onTapGesture {
            onSelect()
        }
        .gesture(
            isSelected ? 
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Update the asset position - all assets use the same direct positioning
                    var updatedAsset = asset
                    updatedAsset.position.x += value.translation.width
                    updatedAsset.position.y += value.translation.height
                    
                    onUpdate(updatedAsset)
                    dragOffset = .zero
                }
            : nil
        )
    }
    
    private var textAssetView: some View {
        Text(asset.content.displayText)
            .font(.custom("Helvetica Neue", size: asset.fontSize))
            .fontWeight(asset.fontWeight)
            .foregroundColor(asset.color)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .stroke(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
            )
    }
    
    private var titleDistanceAssetView: some View {
        VStack(spacing: 4) {
            if case .titleDistance(let title, let distance, let unit) = asset.content {
                // Distance above title with gradient - more prominent
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
                
                // Title below with same gradient - bigger than before
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
                .stroke(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
        )
    }
    
    private var locationAssetView: some View {
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
                .stroke(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
        )
    }
    
    private var statsClusterView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if case .stats(let stats) = asset.content {
                // Date, time, pace in horizontal line
                HStack(spacing: 12) {
                    // Date with calendar icon
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(stats.date)
                            .font(.custom("Helvetica Neue", size: 14))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    
                    // Time with clock icon
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(stats.time)
                            .font(.custom("Helvetica Neue", size: 14))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    
                    // Pace with stopwatch icon
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(stats.pace)
                            .font(.custom("Helvetica Neue", size: 14))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    
                    // Weather with thermometer icon (if available)
                    if let weather = stats.weather {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(weather)
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var songListAssetView: some View {
        Group {
            if case .songList(let tracks, let powerSongId) = asset.content {
                VStack(alignment: .leading, spacing: 1) {
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
                                .shadow(color: asset.showBlackOutline ? .black : .clear, radius: asset.showBlackOutline ? 1 : 0)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Rectangle()
                                .fill(asset.showBlackOutline ? Color.black : Color.clear)
                        )
                    }
                }
            }
        }
    }
    
    private var powerSongAssetView: some View {
        Group {
            if case .powerSong(let track, let pace) = asset.content {
                HStack(spacing: 10) {
                    Text("🔥")
                        .font(.system(size: 28))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name.lowercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist.lowercased())
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        if let pace = pace {
                            HStack(spacing: 2) {
                                Text(pace)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                Text("per mile")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.8), Color.red.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
        }
    }
    
    private var routeAssetView: some View {
        Group {
            if case .route(let coordinates) = asset.content {
                RoutePathView(
                    coordinates: coordinates,
                    songPositions: [],
                    lineWidth: 4.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets[0]
                )
                .frame(width: 250, height: 250)
                .scaleEffect(asset.scale)
                .contentShape(Rectangle()) // Make the route tappable
            }
        }
    }
    
    private var albumArtAssetView: some View {
        Group {
            if case .albumArt(let imageURL, let imageData, let albumName, let artistName) = asset.content {
                Group {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let imageURL = imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
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
                .scaleEffect(asset.scale)
            }
        }
    }
    
    private func romanNumeral(for number: Int) -> String {
        let romanNumerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", 
                           "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
        return number <= romanNumerals.count ? romanNumerals[number - 1] : "\(number)"
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
                                .shadow(color: showBlackOutline ? .black : .clear, radius: showBlackOutline ? 1 : 0)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.8))
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
                                    
                                    Button("Select First 10") {
                                        selectFirst10()
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
                                
                                // Text color picker
                                HStack {
                                    Text("Text Color")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    ColorPicker("", selection: $textColor)
                                        .frame(width: 44, height: 32)
                                }
                                
                                // Black outline toggle
                                HStack {
                                    Text("Text Shadow")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Toggle("", isOn: $showBlackOutline)
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
            // If no specific selection, select first few songs up to maxSongs
            selectedSongs = Set(allTracks.prefix(min(maxSongs, allTracks.count)).map { $0.id })
        }
        
        // Initialize styling from current asset
        textColor = asset.color
        selectedFont = asset.fontFamily ?? "Helvetica Neue"
        showBlackOutline = asset.showBlackOutline
    }
    
    private func toggleSongSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else if selectedSongs.count < maxSongs {
            selectedSongs.insert(songId)
        }
    }
    
    private func selectFirst10() {
        guard let allTracks = run.spotifyTracks else { return }
        selectedSongs = Set(allTracks.prefix(10).map { $0.id })
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

#Preview {
    RunCardStackView(selectedRunId: .constant(nil))
        .environmentObject(FirebaseAuthService.shared)
}