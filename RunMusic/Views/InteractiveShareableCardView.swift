import SwiftUI
import CoreLocation

// Struct to hold transformation states for export
struct ShareableCardTransforms {
    let trackListOffset: CGSize
    let trackListScale: CGFloat
    let trackListRotation: Angle
    let trackListZIndex: Double
    
    let routeOffset: CGSize
    let routeScale: CGFloat
    let routeRotation: Angle
    let routeZIndex: Double
}

struct InteractiveShareableCardView: View {
    @Binding var run: RunActivity
    @StateObject private var userPreferences = UserPreferences.shared
    var layoutType: ShareableCardLayoutType = .portrait
    var fontFamily: FontFamily?
    
    // Stat visibility toggles
    var showDate: Bool = true
    var showTime: Bool = true
    var showPace: Bool = true
    var showTemperature: Bool = true
    
    // Track list interaction states
    @State private var trackListOffset = CGSize.zero
    @State private var trackListScale: CGFloat = 1.0
    @State private var trackListRotation: Angle = .zero
    @State private var trackListZIndex: Double = 1
    @State private var trackListLastOffset = CGSize.zero
    @State private var trackListLastScale: CGFloat = 1.0
    @State private var trackListLastRotation: Angle = .zero
    
    // Route interaction states
    @State private var routeOffset = CGSize.zero
    @State private var routeScale: CGFloat = 1.0
    @State private var routeRotation: Angle = .zero
    @State private var routeZIndex: Double = 0
    @State private var routeLastOffset = CGSize.zero
    @State private var routeLastScale: CGFloat = 1.0
    @State private var routeLastRotation: Angle = .zero
    
    // Route animation states
    @State private var showAnimatedRoute = false
    
    // UI states
    @State private var showResetAlert = false
    
    // Callback for exporting with current transforms
    var onExport: ((ShareableCardTransforms) -> Void)?
    
    // Portrait-only settings (simplified)
    private var currentLayoutSettings: LayoutSpecificSettings {
        return run.portraitSettings
    }
    
    var body: some View {
        GeometryReader { geometry in
            let _ = print("📐 CARD DIMENSIONS: width=\(geometry.size.width), height=\(geometry.size.height)")
            ZStack {
                // Photo background or gradient
                backgroundView(geometry: geometry)
                
                // Main content
                VStack(spacing: 0) {
                    // Header with stats
                    VStack(spacing: 16) {
                        headerWithStatsSection
                        
                        // Interactive route section
                        interactiveRouteSection
                            .frame(minHeight: geometry.size.height * 0.25, maxHeight: geometry.size.height * 0.45)
                            .zIndex(routeZIndex)
                    }
                    
                    // Songs with balanced spacing
                    Spacer(minLength: 8)  // Reduced since we now have bottom padding
                    
                    let tracks = run.spotifyTracks
                    let tracksNotEmpty = !(tracks?.isEmpty ?? true)
                    let shouldShow = shouldShowSongs
                    let _ = print("🎵 CANVAS RENDER DEBUG:")
                    let _ = print("  - tracks count: \(tracks?.count ?? 0)")
                    let _ = print("  - tracksNotEmpty: \(tracksNotEmpty)")
                    let _ = print("  - shouldShowSongs: \(shouldShow)")
                    let _ = print("  - will render song list: \(tracks != nil && tracksNotEmpty && shouldShow)")
                    
                    if let tracks = tracks, tracksNotEmpty, shouldShow {
                        VStack(alignment: .leading, spacing: 0) {
                            interactiveTrackList(tracks: tracks.filter { $0.isVisible })
                                .zIndex(trackListZIndex)
                        }
                        .padding(.leading, -30) // Move track list 30px closer to left edge (24-30=-6px from edge) - further left as requested
                    } else {
                        let _ = print("🎵 SONG LIST NOT RENDERED - Missing condition:")
                        let _ = print("  - Has tracks: \(tracks != nil)")
                        let _ = print("  - Tracks not empty: \(tracksNotEmpty)")
                        let _ = print("  - Should show songs: \(shouldShow)")
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)
                .padding(.bottom, 10) // Small padding between track list and bottom border
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                
                // Interactive album art displays
                Group {
                    let currentAlbumArtDisplays = run.portraitSettings.albumArtDisplays
                    let _ = print("🎨 COMPREHENSIVE DEBUG - ALBUM ART RENDERING:")
                    let _ = print("  Layout Type: \(layoutType.rawValue)")
                    let _ = print("  Album Art Displays Count: \(currentAlbumArtDisplays?.count ?? 0)")
                    let _ = print("  Album Art Displays Nil Check: \(currentAlbumArtDisplays == nil ? "NIL" : "NOT NIL")")
                    
                    if let albumArtDisplays = currentAlbumArtDisplays {
                        let _ = print("  ✅ Album art displays exist, checking each item...")
                        let _ = print("  📐 CARD BOUNDS: width=\(geometry.size.width), height=\(geometry.size.height)")
                        ForEach(albumArtDisplays.indices, id: \.self) { index in
                            let albumArt = albumArtDisplays[index]
                            let _ = print("  📍 Album Art \(index): \(albumArt.albumName)")
                            let _ = print("      Position: (\(albumArt.offsetX), \(albumArt.offsetY))")
                            let _ = print("      Scale: \(albumArt.scale)")
                            let _ = print("      ZIndex: \(albumArt.zIndex)")
                            let _ = print("      Visible: \(albumArt.isVisible)")
                            let _ = print("      Image URL: \(albumArt.imageURL ?? "NO URL")")
                            
                            // Check if position is within card bounds
                            let inBounds = (albumArt.offsetX >= 0 && albumArt.offsetX <= geometry.size.width) && 
                                          (albumArt.offsetY >= 0 && albumArt.offsetY <= geometry.size.height)
                            let _ = print("      IN BOUNDS: \(inBounds ? "YES" : "NO - OUTSIDE CARD!")")
                            
                            if albumArt.isVisible {
                                let _ = print("  ✅ RENDERING album art \(index): \(albumArt.albumName)")
                                InteractiveAlbumArtView(albumArt: Binding(
                                    get: { 
                                        return run.portraitSettings.albumArtDisplays?[index] ?? albumArt 
                                    },
                                    set: { newValue in
                                        if run.portraitSettings.albumArtDisplays != nil {
                                            run.portraitSettings.albumArtDisplays![index] = newValue
                                        }
                                    }
                                )) {
                                    onExport?(getCurrentTransforms())
                                }
                                .zIndex(albumArt.zIndex)
                            } else {
                                let _ = print("  ❌ NOT RENDERING album art \(index): \(albumArt.albumName) - isVisible: \(albumArt.isVisible)")
                            }
                        }
                    } else {
                        let _ = print("  ❌ NO ALBUM ART DISPLAYS FOUND - this is the problem!")
                    }
                }
                .id("albumArt-\(layoutType.rawValue)-\(run.portraitSettings.albumArtDisplays?.map { "\($0.id)-\($0.isVisible)" }.joined(separator: "_") ?? "none")") // Force refresh when album art changes
                
                // Power Song Card Display
                if let powerSongDisplay = run.portraitSettings.powerSongDisplay, powerSongDisplay.isVisible {
                    let actualPosition = powerSongDisplay.absolutePosition(
                        cardWidth: geometry.size.width, 
                        cardHeight: geometry.size.height
                    )
                    let _ = print("🔥 RENDERING: Power song at (\(actualPosition.x), \(actualPosition.y)) on card (\(geometry.size.width), \(geometry.size.height))")
                    
                    InteractivePowerSongView(
                        powerSongDisplay: Binding(
                            get: { 
                                return run.portraitSettings.powerSongDisplay ?? powerSongDisplay 
                            },
                            set: { newValue in
                                run.portraitSettings.powerSongDisplay = newValue
                            }
                        ),
                        colorScheme: colorScheme,
                        cardWidth: geometry.size.width,
                        cardHeight: geometry.size.height
                    ) {
                        onExport?(getCurrentTransforms())
                    }
                    .zIndex(powerSongDisplay.zIndex)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            // Album art initialization and enrichment is now handled by RunDetailView lazy loading
            // when the view opens, providing better performance and correct URL propagation
            
            // SINGLE CODE PATH: Always ensure proper default positioning
            initializeAlbumArtToDefaults()  // Always set to proper defaults
            initializePowerSongToDefaults()  // Always set to proper defaults
        }
        .alert("reset to defaults?", isPresented: $showResetAlert) {
            Button("cancel", role: .cancel) { }
            Button("reset", role: .destructive) {
                resetLayout()
            }
        } message: {
            Text("this will reset all positioning, size, and rotation to defaults.")
        }
    }
    
    // MARK: - Interactive Components
    
    private func interactiveTrackList(tracks: [SpotifyTrack]) -> some View {
        // Pass all tracks from run for correct "other songs" count
        let allTracksFromRun = run.spotifyTracks ?? []
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                let isPowerSong = run.powerSong?.id == track.id
                InstagramStyleTrackRow(
                    track: track,
                    index: index + 1,
                    fontFamily: currentFontFamily,
                    isPowerSong: isPowerSong
                )
            }
            
            // Show "+N other songs" if there are hidden tracks
            let hiddenCount = allTracksFromRun.count - tracks.count
            if hiddenCount > 0 {
                HStack(spacing: 6) {
                    Text("+\(hiddenCount) other songs")
                        .font(currentFontFamily.customFont(size: 10))
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(0) // Hard corners for Instagram style
            }
        }
            .scaleEffect(trackListScale)
            .rotationEffect(trackListRotation)
            .offset(trackListOffset)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            trackListOffset = CGSize(
                                width: trackListLastOffset.width + value.translation.width,
                                height: trackListLastOffset.height + value.translation.height
                            )
                            // Bring to front when interacting
                            trackListZIndex = 2
                            routeZIndex = 0
                            // Update export callback
                            onExport?(getCurrentTransforms())
                        }
                        .onEnded { _ in
                            trackListLastOffset = trackListOffset
                        },
                    MagnificationGesture()
                        .onChanged { value in
                            trackListScale = trackListLastScale * value
                            onExport?(getCurrentTransforms())
                        }
                        .onEnded { value in
                            trackListLastScale = trackListScale
                        }
                )
                .simultaneously(with: RotationGesture()
                    .onChanged { value in
                        trackListRotation = trackListLastRotation + value
                        onExport?(getCurrentTransforms())
                    }
                    .onEnded { value in
                        trackListLastRotation = trackListRotation
                    }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    trackListOffset = .zero
                    trackListScale = 1.0
                    trackListRotation = .zero
                    trackListLastOffset = .zero
                    trackListLastScale = 1.0
                    trackListLastRotation = .zero
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: trackListOffset)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: trackListScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: trackListRotation)
    }
    
    private var interactiveRouteSection: some View {
        VStack {
            let songPositions = generateDynamicSongPositions()
            
            Group {
                if showAnimatedRoute {
                    AnimatedRoutePathView(
                        coordinates: run.routeCoordinates,
                        songPositions: shouldShowSongs ? songPositions : [],
                        lineWidth: 4,
                        showSongIndicators: shouldShowSongs && !songPositions.isEmpty,
                        colorScheme: colorScheme,
                        animationDuration: 3.0
                    )
                } else {
                    RoutePathView(
                        coordinates: run.routeCoordinates,
                        songPositions: shouldShowSongs ? songPositions : [],
                        lineWidth: 4,
                        showSongIndicators: shouldShowSongs && !songPositions.isEmpty,
                        colorScheme: colorScheme
                    )
                }
            }
            .padding(.horizontal, 8)
            .scaleEffect(routeScale)
            .rotationEffect(routeRotation)
            .offset(routeOffset)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            routeOffset = CGSize(
                                width: routeLastOffset.width + value.translation.width,
                                height: routeLastOffset.height + value.translation.height
                            )
                            // Bring to front when interacting
                            routeZIndex = 2
                            trackListZIndex = 0
                            onExport?(getCurrentTransforms())
                        }
                        .onEnded { _ in
                            routeLastOffset = routeOffset
                        },
                    MagnificationGesture()
                        .onChanged { value in
                            routeScale = routeLastScale * value
                            onExport?(getCurrentTransforms())
                        }
                        .onEnded { value in
                            routeLastScale = routeScale
                        }
                )
                .simultaneously(with: RotationGesture()
                    .onChanged { value in
                        routeRotation = routeLastRotation + value
                        onExport?(getCurrentTransforms())
                    }
                    .onEnded { value in
                        routeLastRotation = routeRotation
                    }
                )
            )
            .onLongPressGesture(minimumDuration: 1.0) {
                // Toggle between static and animated route on long press
                withAnimation(.easeInOut(duration: 0.3)) {
                    showAnimatedRoute.toggle()
                }
            }
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    routeOffset = .zero
                    routeScale = 1.0
                    routeRotation = .zero
                    routeLastOffset = .zero
                    routeLastScale = 1.0
                    routeLastRotation = .zero
                }
            }
            .animation(.interactiveSpring(), value: routeOffset)
            .animation(.interactiveSpring(), value: routeScale)
            .animation(.interactiveSpring(), value: routeRotation)
        }
    }
    
    // MARK: - Helper Functions
    
    func getCurrentTransforms() -> ShareableCardTransforms {
        ShareableCardTransforms(
            trackListOffset: trackListOffset,
            trackListScale: trackListScale,
            trackListRotation: trackListRotation,
            trackListZIndex: trackListZIndex,
            routeOffset: routeOffset,
            routeScale: routeScale,
            routeRotation: routeRotation,
            routeZIndex: routeZIndex
        )
    }
    
    private func resetLayout() {
        withAnimation(.spring()) {
            // Reset track list transforms to defaults
            trackListOffset = .zero
            trackListScale = 1.0
            trackListRotation = .zero
            trackListZIndex = 1
            trackListLastOffset = .zero
            trackListLastScale = 1.0
            trackListLastRotation = .zero
            
            // Reset route transforms to defaults
            routeOffset = .zero
            routeScale = 1.0
            routeRotation = .zero
            routeZIndex = 0
            routeLastOffset = .zero
            routeLastScale = 1.0
            routeLastRotation = .zero
            
            // Reset to defaults using SINGLE CODE PATH
            initializeAlbumArtToDefaults()  // Always recreate with defaults
            initializePowerSongToDefaults()  // Always recreate with defaults
            
            print("🔄 RESET: Layout reset to defaults using single code path")
        }
    }
    
    private func backgroundView(geometry: GeometryProxy) -> some View {
        let defaultGradientColors = [
            Color.orange.opacity(0.15),
            Color.pink.opacity(0.08),
            Color.purple.opacity(0.05),
            Color(.systemBackground)
        ]
        let defaultGradient = LinearGradient(
            colors: defaultGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        return Group {
            if let photoBackground = run.backgroundPhoto {
                PhotoBackgroundView(photoBackground: photoBackground)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                defaultGradient
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowCity: Bool {
        currentLayoutSettings.showCity ?? userPreferences.showCityByDefault
    }
    
    private var shouldShowSongs: Bool {
        let result = currentLayoutSettings.showSongs ?? userPreferences.showSongsByDefault
        print("🎵 SONG DISPLAY DEBUG:")
        print("  - currentLayoutSettings.showSongs: \(String(describing: currentLayoutSettings.showSongs))")
        print("  - userPreferences.showSongsByDefault: \(userPreferences.showSongsByDefault)")
        print("  - shouldShowSongs result: \(result)")
        print("  - run.spotifyTracks count: \(run.spotifyTracks?.count ?? 0)")
        return result
    }
    
    private var colorScheme: RunColorScheme {
        // Prioritize weather-based color, then user selection, then default
        run.weatherBasedRouteColor ?? 
        currentLayoutSettings.colorScheme ?? 
        userPreferences.defaultColorScheme
    }
    
    private var currentFontFamily: FontFamily {
        fontFamily ?? currentLayoutSettings.fontFamily ?? userPreferences.defaultFontFamily
    }
    
    private var headerWithStatsSection: some View {
        VStack(spacing: 12) {
            // Top row: App watermark, stats, and location in same line
            HStack(alignment: .top) {
                // Left side: Watermark
                VStack(alignment: .leading, spacing: 2) {
                    // Watermark using asset (transparency is built into the asset)
                    Image("RTT_watermark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 14)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                    
                    Text(" @ckubal") // Username display with space separation from left border
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .opacity(0.5)
                        .foregroundColor(.white)
                }
                .offset(x: -24) // Offset to counteract the horizontal padding
                
                Spacer()
                
                // Center-right: Stats and location in same row, further right
                VStack(alignment: .trailing, spacing: 4) {
                    // Stats row
                    HStack(spacing: 6) {
                        if showDate {
                            compactStatView(
                                icon: "calendar",
                                value: formatDateLowercase(run.date),
                                unit: ""
                            )
                        }
                        
                        if showTime {
                            compactStatView(
                                icon: "clock",
                                value: run.formattedDuration,
                                unit: ""
                            )
                        }
                        
                        if showPace {
                            compactStatView(
                                icon: "speedometer",
                                value: userPreferences.formatPace(run.averagePace),
                                unit: "/\(userPreferences.distanceUnit.abbreviation)"
                            )
                        }
                        
                        if showTemperature, let weather = run.weatherData {
                            compactStatView(
                                icon: "thermometer",
                                value: userPreferences.formatTemperature(weather.temperature),
                                unit: ""
                            )
                        }
                    }
                    
                    // Location row right-aligned
                    if let locationText = run.smartLocationDisplay, shouldShowCity {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundColor(colorScheme.primaryColor.color)
                            Text(locationText.lowercased())
                                .font(currentFontFamily.customFont(size: 11))
                                .fontWeight(.medium)
                                .foregroundColor(colorScheme.primaryColor.color)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorScheme.primaryColor.color.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .offset(x: 10) // Push further to right edge
            }
            
            // Mileage prominent with run name smaller (user request)  
            VStack(spacing: 4) {
                Text("\(userPreferences.formatDistance(run.distance)) \(userPreferences.distanceUnit.abbreviation.lowercased())")
                    .font(currentFontFamily.customFont(size: 32))
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colorScheme.gradient)
                
                Text(run.name.lowercased())
                    .font(currentFontFamily.customFont(size: 18))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(colorScheme.primaryColor.color)
            }
        }
    }
    
    private func compactStatView(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 1) { // Reduced internal spacing
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6)) // Grayed out and more subtle
                .scaleEffect(0.8) // Smaller icons
            
            // Combine value and unit into single Text to prevent line breaks
            Text(value + (!unit.isEmpty ? unit : ""))
                .font(currentFontFamily.customFont(size: 9)) // Slightly smaller font  
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5) // More aggressive scaling to fit everything
                .truncationMode(.tail) // Truncate if still too long
                .fixedSize(horizontal: false, vertical: true) // Allow horizontal compression but prevent vertical expansion
        }
        .layoutPriority(0) // Lower priority allows compression if needed
    }
    
    private func generateSongPositions() -> [SongPosition] {
        guard let tracks = run.spotifyTracks,
              !tracks.isEmpty,
              !run.routeCoordinates.isEmpty else {
            return []
        }
        
        let runDuration = run.elapsedTime
        let visibleTracks = tracks.filter { $0.isVisible }
        
        return visibleTracks.enumerated().compactMap { index, track in
            let trackStartTime = track.playedAt.timeIntervalSince(run.date)
            let progressRatio = max(0, min(1, trackStartTime / runDuration))
            
            // Check if this track is the Power Song
            let isPowerSong = run.powerSong?.id == track.id
            return SongPosition(songIndex: index, progressRatio: progressRatio, isPowerSong: isPowerSong)
        }
    }
    
    private func generateDynamicSongPositions() -> [SongPosition] {
        guard let tracks = run.spotifyTracks,
              !tracks.isEmpty,
              !run.routeCoordinates.isEmpty else {
            return []
        }
        
        let runDuration = run.elapsedTime
        let sortedTracks = tracks.sorted { $0.playedAt < $1.playedAt }
        
        // Separate tracks into pre-run and during-run
        let preRunTracks = sortedTracks.filter { track in
            track.playedAt.timeIntervalSince(run.date) < 0
        }
        
        let duringRunTracks = sortedTracks.filter { track in
            track.playedAt.timeIntervalSince(run.date) >= 0
        }
        
        var finalTracks: [SpotifyTrack] = []
        
        // Check if we need to include a pre-run song
        if let firstDuringRunTrack = duringRunTracks.first {
            let firstTrackStartTime = firstDuringRunTrack.playedAt.timeIntervalSince(run.date)
            
            if firstTrackStartTime <= 30 {
                // Case 2: New song starts within 30 seconds, use it as first song
                finalTracks = duringRunTracks
            } else {
                // Case 3: Gap at beginning - look for pre-run song that might have been playing
                if let lastPreRunTrack = preRunTracks.last {
                    let trackStartTime = lastPreRunTrack.playedAt.timeIntervalSince(run.date)
                    let estimatedTrackEnd = trackStartTime + Double(lastPreRunTrack.durationMs) / 1000.0
                    
                    // If the pre-run song would have been playing for >30 seconds during the run
                    if estimatedTrackEnd > 30 {
                        // Case 1: Include the pre-run song as first song
                        // Remove duplicate if the same track appears at the start of during-run tracks
                        var dedupedDuringRunTracks = duringRunTracks
                        if let firstDuringTrack = duringRunTracks.first,
                           firstDuringTrack.name == lastPreRunTrack.name && 
                           firstDuringTrack.artist == lastPreRunTrack.artist {
                            dedupedDuringRunTracks = Array(duringRunTracks.dropFirst())
                        }
                        finalTracks = [lastPreRunTrack] + dedupedDuringRunTracks
                    } else {
                        // Pre-run song ended too early, just use during-run tracks
                        finalTracks = duringRunTracks
                    }
                } else {
                    // No pre-run tracks available
                    finalTracks = duringRunTracks
                }
            }
        } else {
            // No during-run tracks, check if we have a pre-run song that extends into the run
            if let lastPreRunTrack = preRunTracks.last {
                let trackStartTime = lastPreRunTrack.playedAt.timeIntervalSince(run.date)
                let estimatedTrackEnd = trackStartTime + Double(lastPreRunTrack.durationMs) / 1000.0
                
                if estimatedTrackEnd > 30 {
                    finalTracks = [lastPreRunTrack]
                }
            }
        }
        
        let visibleTracks = finalTracks.filter { $0.isVisible }
        
        return visibleTracks.enumerated().compactMap { index, track in
            let trackStartTime = track.playedAt.timeIntervalSince(run.date)
            
            // Position pre-run songs (negative start time) at the beginning
            // Position songs that started within 30 seconds at the beginning  
            let adjustedStartTime = trackStartTime <= 30 ? 0 : trackStartTime
            
            let progressRatio = max(0, min(1, adjustedStartTime / runDuration))
            
            // Check if this track is the Power Song
            let isPowerSong = run.powerSong?.id == track.id
            return SongPosition(songIndex: index, progressRatio: progressRatio, isPowerSong: isPowerSong)
        }
    }
    
    private func formatDateLowercase(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"  // Format: "jun 15" 
        return formatter.string(from: date).lowercased()
    }
    
    private func initializeAlbumArtToDefaults() {
        // Always create/recreate album art with default positioning
        let availableAlbumArt = run.availableAlbumArt
        guard let firstAlbum = availableAlbumArt.first else {
            run.portraitSettings.albumArtDisplays = nil
            print("🎨 SINGLE PATH: No album art available")
            return
        }
        
        print("🎨 SINGLE PATH: Initializing album art for '\(firstAlbum.albumName)'")
        
        let cardWidth: CGFloat = 362.0  // Standard portrait width
        let cardHeight: CGFloat = 595.56  // Standard portrait height
        
        var defaultAlbumArt = firstAlbum
        
        // SINGLE SOURCE OF TRUTH FOR DEFAULT POSITIONING
        let position = CGPoint(
            x: cardWidth - 70,  // Closer to right edge (10px closer)
            y: cardHeight - 120 // Higher up to sit above power song
        )
        defaultAlbumArt.offsetX = position.x
        defaultAlbumArt.offsetY = position.y
        defaultAlbumArt.scale = 0.8  // Default scale
        defaultAlbumArt.rotationDegrees = 0.0  // Default rotation (no rotation)
        defaultAlbumArt.isVisible = true  // Always visible by default
        defaultAlbumArt.zIndex = 2.0
        
        run.portraitSettings.albumArtDisplays = [defaultAlbumArt]
        print("🎨 SINGLE PATH: Album art initialized at (\(position.x), \(position.y))")
    }
    
    private func initializeAlbumArtIfNeeded() {
        // Only initialize if not already set up
        guard run.portraitSettings.albumArtDisplays == nil else { return }
        initializeAlbumArtToDefaults()
    }
    
    // MARK: - Centralized Initialization (Single Code Path)
    
    private func initializePowerSongToDefaults() {
        // Always create/recreate power song with default positioning
        guard let powerSong = run.powerSong,
              let pacePerMile = run.powerSongPacePerMile else {
            run.portraitSettings.powerSongDisplay = nil
            return
        }
        
        print("🔥 SINGLE PATH: Initializing Power Song display for '\(powerSong.name)' by \(powerSong.artist)")
        
        var powerSongDisplay = PowerSongDisplay(
            songName: powerSong.name,
            artistName: powerSong.artist,
            pacePerMile: pacePerMile
        )
        
        // SINGLE SOURCE OF TRUTH FOR DEFAULT POSITIONING
        powerSongDisplay.offsetXPercent = 0.86  // 86% from left (right side)  
        powerSongDisplay.offsetYPercent = 0.92   // 92% from top (adjusted higher per user feedback)
        powerSongDisplay.scale = 1.0  // Default scale (no scaling)
        powerSongDisplay.rotationDegrees = 0.0  // Default rotation (no rotation)
        powerSongDisplay.isVisible = true  // Always visible by default
        powerSongDisplay.zIndex = 3.0  // Above album art
        
        run.portraitSettings.powerSongDisplay = powerSongDisplay
        
        print("🔥 SINGLE PATH: Power Song initialized at (\(powerSongDisplay.offsetXPercent * 100)%, \(powerSongDisplay.offsetYPercent * 100)%)")
    }
    
    private func initializePowerSongIfNeeded() {
        // Only initialize if not already set up
        guard run.portraitSettings.powerSongDisplay == nil else { return }
        initializePowerSongToDefaults()
    }
}

#Preview {
    let sampleTracks = [
        SpotifyTrack(id: "1", name: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playedAt: Date(), durationMs: 200000, albumImageURL: nil, isFavorite: true),
        SpotifyTrack(id: "2", name: "Good 4 U", artist: "Olivia Rodrigo", album: "SOUR", playedAt: Date().addingTimeInterval(210), durationMs: 178000, albumImageURL: nil)
    ]
    
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run in Golden Gate Park",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Golden Gate Park",
        spotifyTracks: sampleTracks
    )
    
    InteractiveShareableCardView(run: .constant(sampleRun), fontFamily: nil)
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .padding()
}


// Compact color selector button with popup
struct ColorSelectorButton: View {
    let selectedScheme: RunColorScheme
    let onSchemeSelected: (RunColorScheme) -> Void
    
    @State private var showColorPicker = false
    
    var body: some View {
        Button(action: {
            showColorPicker = true
        }) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [selectedScheme.primaryColor.color, selectedScheme.secondaryColor.color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32) // Larger tap target
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(showColorPicker ? 0.95 : 1.0) // Visual feedback
        .animation(.easeInOut(duration: 0.1), value: showColorPicker)
        .sheet(isPresented: $showColorPicker) {
            ColorPickerSheet(
                selectedScheme: selectedScheme,
                onSchemeSelected: onSchemeSelected
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }
}

// Color picker sheet
struct ColorPickerSheet: View {
    let selectedScheme: RunColorScheme
    let onSchemeSelected: (RunColorScheme) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("color scheme")
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("done") {
                    dismiss()
                }
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Color grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                ForEach(RunColorScheme.presets, id: \.id) { scheme in
                    Button(action: {
                        onSchemeSelected(scheme)
                        dismiss()
                    }) {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [scheme.primaryColor.color, scheme.secondaryColor.color],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedScheme.id == scheme.id ? Color.primary : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            
                            Text(scheme.name)
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
}

// Font selector button
struct FontSelectorButton: View {
    let selectedFont: FontFamily
    let onFontSelected: (FontFamily) -> Void
    
    @State private var showFontPicker = false
    
    var body: some View {
        Button(action: {
            showFontPicker = true
        }) {
            Text("Aa")
                .font(selectedFont.font(size: 16, weight: Font.Weight.medium))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray5))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(showFontPicker ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: showFontPicker)
        .sheet(isPresented: $showFontPicker) {
            FontPickerSheet(
                selectedFont: selectedFont,
                onFontSelected: onFontSelected
            )
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
    }
}

// Font picker sheet
struct FontPickerSheet: View {
    let selectedFont: FontFamily
    let onFontSelected: (FontFamily) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionService = SubscriptionService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("font family")
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("done") {
                    dismiss()
                }
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Default font section (always at top)
                    defaultFontSection
                    
                    // Free fonts section (excluding default)
                    fontSection(title: "Free", fonts: FontFamily.presets.filter { !$0.isPremium && $0.name != FontFamily.default.name }, headerColor: .blue)
                    
                    // Premium fonts section  
                    fontSection(title: "Premium", fonts: FontFamily.presets.filter { $0.isPremium }, headerColor: .orange)
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var defaultFontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Default")
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Button(action: {
                onFontSelected(FontFamily.default)
                dismiss()
            }) {
                HStack {
                    Text("The quick brown fox")
                        .font(FontFamily.default.font(size: 16, weight: Font.Weight.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(FontFamily.default.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("recommended")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if selectedFont.id == FontFamily.default.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedFont.id == FontFamily.default.id ? Color.blue.opacity(0.1) : Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func fontSection(title: String, fonts: [FontFamily], headerColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(headerColor)
                
                if title == "Premium" && !subscriptionService.isPremium {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            
            ForEach(fonts, id: \.id) { font in
                Button(action: {
                    if font.isPremium && !subscriptionService.isPremium {
                        // Show premium prompt or ignore
                        return
                    }
                    onFontSelected(font)
                    dismiss()
                }) {
                    HStack {
                        Text("The quick brown fox")
                            .font(font.font(size: 16, weight: Font.Weight.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(font.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if font.isPremium && !subscriptionService.isPremium {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if selectedFont.id == font.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedFont.id == font.id ? Color.blue.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .disabled(font.isPremium && !subscriptionService.isPremium)
                .opacity(font.isPremium && !subscriptionService.isPremium ? 0.6 : 1.0)
            }
        }
    }
}