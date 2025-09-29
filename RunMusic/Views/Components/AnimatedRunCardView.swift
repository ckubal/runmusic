import SwiftUI
import AVFoundation

struct AnimatedRunCardView: View {
    let run: RunActivity
    let fontFamily: FontFamily
    @State private var animationProgress: Double = 0.0
    @State private var isRecording = false
    
    // Animation timing constants
    private let totalDuration: Double = 12.0
    private let routeAnimationStart: Double = 2.0
    private let routeAnimationDuration: Double = 8.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (same as ShareableCardView)
                backgroundView(geometry: geometry)
                
                // Animated content layers
                VStack(spacing: 0) {
                    // Header (appears immediately)
                    headerWithStatsSection
                        .opacity(headerOpacity)
                        .animation(.easeIn, value: animationProgress)
                    
                    // Route section with progressive drawing
                    VStack {
                        let songPositions = generateDynamicSongPositions()
                        
                        AnimatedRoutePathView(
                            coordinates: run.routeCoordinates,
                            songPositions: songPositions,
                            lineWidth: 4,
                            showSongIndicators: !songPositions.isEmpty,
                            colorScheme: RunColorScheme.presets.first
                        )
                        .padding(.horizontal, 8)
                    }
                    .frame(height: geometry.size.height * 0.45)
                    
                    Spacer()
                    
                    // Track list with staggered reveal
                    if !sortedTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(sortedTracks.filter { $0.isVisible }.enumerated()), id: \.offset) { index, track in
                                    let isPowerSong = run.powerSong?.id == track.id
                                    InstagramStyleTrackRow(
                                        track: track,
                                        index: index + 1,
                                        fontFamily: fontFamily,
                                        isPowerSong: isPowerSong
                                    )
                                }
                                
                                // Show "+N other songs" if there are hidden tracks
                                let hiddenCount = sortedTracks.count - sortedTracks.filter { $0.isVisible }.count
                                if hiddenCount > 0 {
                                    HStack(spacing: 6) {
                                        Text("+\(hiddenCount) other songs")
                                            .font(fontFamily.customFont(size: 10))
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
                            .opacity(trackListProgress > 0.8 ? 1.0 : 0.0)
                            .animation(.easeIn, value: trackListProgress)
                        }
                        .padding(.bottom, 20)
                    }
                }
                .padding(24)
            }
        }
    }
    
    // MARK: - Animation Progress Calculations
    
    private var headerOpacity: Double {
        animationProgress >= 0.1 ? 1.0 : 0.0
    }
    
    private var routeProgress: Double {
        let routeStart = routeAnimationStart / totalDuration
        let routeEnd = (routeAnimationStart + routeAnimationDuration) / totalDuration
        
        if animationProgress < routeStart { return 0.0 }
        if animationProgress > routeEnd { return 1.0 }
        
        return (animationProgress - routeStart) / (routeEnd - routeStart)
    }
    
    private var songMarkerProgress: Double {
        // Song markers appear progressively as route draws
        routeProgress
    }
    
    private var trackListProgress: Double {
        // Track list starts revealing when route is 50% complete
        let trackStart = 0.5
        if routeProgress < trackStart { return 0.0 }
        return (routeProgress - trackStart) / (1.0 - trackStart)
    }
    
    // MARK: - Data Processing
    
    private var sortedTracks: [SpotifyTrack] {
        guard let tracks = run.spotifyTracks else { return [] }
        return tracks.filter { $0.isVisible }
                    .sorted { $0.playedAt < $1.playedAt }
    }
    
    // MARK: - Animation Control
    
    func startAnimation() {
        withAnimation(.linear(duration: totalDuration)) {
            animationProgress = 1.0
        }
    }
    
    func resetAnimation() {
        animationProgress = 0.0
    }
    
    // MARK: - View Components
    
    private func backgroundView(geometry: GeometryProxy) -> some View {
        let gradientColors = [
            Color.orange.opacity(0.15),
            Color.pink.opacity(0.08),
            Color.purple.opacity(0.05),
            Color(.systemBackground)
        ]
        
        return Group {
            if let photoBackground = run.backgroundPhoto {
                PhotoBackgroundView(photoBackground: photoBackground)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private var headerWithStatsSection: some View {
        VStack(spacing: 12) {
            // Top row: App branding and stats with date
            HStack {
                // Left side: App branding with watermark (flush with left edge)
                HStack {
                    Image("RTT_watermark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 14)
                        .opacity(0.7)
                    Spacer()
                }
                .offset(x: -24) // Offset to counteract the horizontal padding
                
                Spacer()
                
                // Right side: Stats with date first as requested
                HStack(spacing: 12) {
                    compactStatView(
                        icon: "calendar",
                        value: formatDateLowercase(run.date),
                        unit: ""
                    )
                    
                    compactStatView(
                        icon: "clock",
                        value: run.formattedDuration,
                        unit: ""
                    )
                    
                    compactStatView(
                        icon: "speedometer",
                        value: UserPreferences.shared.formatPace(run.averagePace),
                        unit: "/\(UserPreferences.shared.distanceUnit.abbreviation)"
                    )
                }
            }
            
            // Mileage prominent with run name smaller (user request)
            VStack(spacing: 4) {
                Text("\(UserPreferences.shared.formatDistance(run.distance)) \(UserPreferences.shared.distanceUnit.abbreviation.lowercased())")
                    .font(fontFamily.customFont(size: 32))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(run.name.lowercased())
                    .font(fontFamily.customFont(size: 18))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(.orange)
            }
            
            // Location only (date moved to top row)
            HStack {
                if let city = run.city {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text(city.lowercased())
                            .font(fontFamily.customFont(size: 13))
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
        }
    }
    
    private func compactStatView(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(fontFamily.customFont(size: 10))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(fontFamily.customFont(size: 8))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatDateLowercase(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
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
}

// MARK: - Animated Card Route View

struct AnimatedCardRouteView: View {
    let coordinates: [LocationData]
    let tracks: [SpotifyTrack]
    let progress: Double
    let songMarkerProgress: Double
    let fontFamily: FontFamily
    
    var body: some View {
        ZStack {
            // Progressive route drawing
            AnimatedRoutePathView(
                coordinates: coordinates,
                lineWidth: 4
            )
            
            // Song markers appearing along the route
            let indexedMarkers = Array(visibleSongMarkers.enumerated())
            ForEach(indexedMarkers, id: \.offset) { index, marker in
                SongMarkerView(
                    position: marker.position,
                    romanNumeral: marker.romanNumeral,
                    isVisible: marker.isVisible,
                    fontFamily: fontFamily
                )
            }
        }
    }
    
    private var visibleSongMarkers: [SongMarker] {
        guard !coordinates.isEmpty,
              let firstTimestamp = coordinates.first?.timestamp,
              let lastTimestamp = coordinates.last?.timestamp else {
            return []
        }
        
        let runDuration = lastTimestamp.timeIntervalSince(firstTimestamp)
        
        return tracks.enumerated().compactMap { index, track in
            let trackTime = track.playedAt.timeIntervalSince(firstTimestamp)
            let positionRatio = trackTime / runDuration
            
            // Only show markers that should be visible based on progress
            let markerShouldAppear = positionRatio <= songMarkerProgress
            
            return SongMarker(
                position: CGPoint(x: positionRatio, y: 0.5), // Simplified positioning
                romanNumeral: romanNumeral(for: index + 1),
                isVisible: markerShouldAppear
            )
        }
    }
    
    private func romanNumeral(for number: Int) -> String {
        let values = [10, 9, 5, 4, 1]
        let numerals = ["X", "IX", "V", "IV", "I"]
        
        var num = number
        var result = ""
        
        for (index, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: numerals[index], count: count)
                num %= value
            }
        }
        
        return result
    }
}

// MARK: - Supporting Types

struct SongMarker {
    let position: CGPoint
    let romanNumeral: String
    let isVisible: Bool
}

struct SongMarkerView: View {
    let position: CGPoint
    let romanNumeral: String
    let isVisible: Bool
    let fontFamily: FontFamily
    
    var body: some View {
        Text(romanNumeral)
            .font(fontFamily.customFont(size: 10))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.orange)
            .clipShape(Circle())
            .scaleEffect(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isVisible)
            .position(position)
    }
}

// MARK: - Animated Track List

struct AnimatedTrackListView: View {
    let tracks: [SpotifyTrack]
    let progress: Double
    let fontFamily: FontFamily
    let powerSong: SpotifyTrack?
    
    var body: some View {
        let indexedTracks = Array(tracks.enumerated())
        
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(indexedTracks, id: \.offset) { index, track in
                let trackProgress = trackProgressFor(index: index)
                
                InstagramStyleTrackRow(track: track, index: index + 1, fontFamily: fontFamily, isPowerSong: powerSong?.id == track.id)
                    .opacity(trackProgress > 0 ? 1.0 : 0.0)
                    .offset(x: trackProgress > 0 ? 0 : -50)
                    .animation(
                        .easeOut(duration: 0.3)
                        .delay(Double(index) * 0.1),
                        value: progress
                    )
            }
        }
    }
    
    private func trackProgressFor(index: Int) -> Double {
        let trackThreshold = Double(index) / Double(max(1, tracks.count))
        return max(0, min(1, (progress - trackThreshold) * Double(tracks.count)))
    }
}

#Preview {
    // Sample data for preview
    let sampleTracks = [
        SpotifyTrack(id: "1", name: "So Far Ahead", artist: "Clipse", album: "Let God Sort Em Out", playedAt: Date(), durationMs: 200000, albumImageURL: nil),
        SpotifyTrack(id: "2", name: "Inglorious Bastards", artist: "Clipse", album: "Let God Sort Em Out", playedAt: Date().addingTimeInterval(180), durationMs: 190000, albumImageURL: nil)
    ]
    
    let sampleRun = RunActivity(
        id: "1",
        name: "Light Work",
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
        neighborhood: "Mission District",
        spotifyTracks: sampleTracks
    )
    
    AnimatedRunCardView(run: sampleRun, fontFamily: FontFamily.default)
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .onAppear {
            // Auto-start animation in preview
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Animation would start here
            }
        }
}