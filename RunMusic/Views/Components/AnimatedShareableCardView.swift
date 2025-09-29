import SwiftUI

struct AnimatedShareableCardView: View {
    let run: RunActivity
    let progress: Double // 0.0 to 1.0
    let currentSong: SpotifyTrack?
    let songOpacity: Double
    let fontFamily: FontFamily
    
    @StateObject private var userPreferences = UserPreferences.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Photo background or gradient (positioned absolutely)
                if let photoBackground = run.backgroundPhoto {
                    PhotoBackgroundView(photoBackground: photoBackground)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else {
                    // Default gradient background
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.15),
                            Color.pink.opacity(0.08),
                            Color.purple.opacity(0.05),
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                
                // Main content - layout independent of background
                VStack(spacing: 0) {
                    // Header with stats moved to top-right
                    VStack(spacing: 16) {
                        headerWithStatsSection
                        
                        // Animated route section
                        VStack {
                            let songPositions = generateSongPositions()
                            
                            AnimatedRoutePathView(
                                coordinates: run.routeCoordinates,
                                songPositions: shouldShowSongs ? songPositions : [],
                                lineWidth: 4,
                                showSongIndicators: shouldShowSongs && !songPositions.isEmpty,
                                colorScheme: colorScheme
                            )
                            .padding(.horizontal, 8)
                        }
                        .frame(maxHeight: geometry.size.height * 0.45) // Balanced size for route display
                    }
                    
                    // Songs positioned at bottom with minimal spacing
                    Spacer(minLength: 10)
                    
                    // Animated track list - only show tracks that should be visible at current progress
                    if let tracks = visibleTracksAtProgress, !tracks.isEmpty, shouldShowSongs {
                        VStack(alignment: .leading, spacing: 0) {
                            AnimatedInstagramStyleTrackList(tracks: tracks, songOpacity: songOpacity, fontFamily: fontFamily)
                        }
                    }
                    
                    // Current song overlay if there's a current song
                    if let song = currentSong, songOpacity > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.name)
                                    .font(fontFamily.customFont(size: 14))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Text(song.artist)
                                    .font(fontFamily.customFont(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                        .opacity(songOpacity)
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)
                .padding(.bottom, 0)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowCity: Bool {
        run.showCity ?? userPreferences.showCityByDefault
    }
    
    private var shouldShowSongs: Bool {
        run.showSongs ?? userPreferences.showSongsByDefault
    }
    
    private var colorScheme: RunColorScheme {
        run.colorScheme ?? userPreferences.defaultColorScheme
    }
    
    // Animated distance that increases with progress
    private var animatedDistance: Double {
        return run.distance * progress
    }
    
    // Filter tracks based on animation progress
    private var visibleTracksAtProgress: [SpotifyTrack]? {
        guard let tracks = run.spotifyTracks else { return nil }
        
        return tracks.filter { track in
            // Show tracks that have appeared in the animation so far
            let trackStartTime = track.playedAt.timeIntervalSince(run.date)
            let adjustedStartTime = trackStartTime <= 30 ? 0 : trackStartTime
            let trackProgress = adjustedStartTime / run.elapsedTime
            return trackProgress <= progress && track.isVisible
        }
    }
    
    // MARK: - Header Section
    
    private var headerWithStatsSection: some View {
        VStack(spacing: 12) {
            // Top row: App branding and date with stats
            HStack {
                // Left side: App branding with watermark (flush with left edge)
                HStack {
                    Image("RTT_watermark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 14) // Adjust height to match text size
                        .opacity(0.7) // Subtle watermark appearance
                    Spacer()
                }
                .offset(x: -24) // Offset to counteract the horizontal padding
                
                Spacer()
                
                // Right side: Animated Stats with date
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 12) {
                        compactStatView(
                            icon: "clock",
                            value: formatAnimatedDuration(run.elapsedTime * progress),
                            unit: ""
                        )
                        
                        compactStatView(
                            icon: "speedometer", 
                            value: userPreferences.formatPace(run.averagePace),
                            unit: "/\(userPreferences.distanceUnit.abbreviation)"
                        )
                    }
                    
                    Text(formatDateLowercase(run.date))
                        .font(fontFamily.customFont(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Run name with animated mileage
            VStack(spacing: 4) {
                Text(run.name.lowercased())
                    .font(fontFamily.customFont(size: 26))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(colorScheme.gradient)
                
                Text("\(userPreferences.formatDistance(animatedDistance)) \(userPreferences.distanceUnit.abbreviation.lowercased())")
                    .font(fontFamily.customFont(size: 22))
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme.primaryColor.color)
            }
            
            // Location
            HStack {
                if let city = run.city, shouldShowCity {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(colorScheme.primaryColor.color)
                        Text(city.lowercased())
                            .font(fontFamily.customFont(size: 13))
                            .fontWeight(.medium)
                            .foregroundColor(colorScheme.primaryColor.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorScheme.primaryColor.color.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Helper Methods
    
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
    
    private func generateSongPositions() -> [SongPosition] {
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
                        finalTracks = [lastPreRunTrack] + duringRunTracks
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
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatAnimatedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Animated Track List Component

struct AnimatedInstagramStyleTrackList: View {
    let tracks: [SpotifyTrack]
    let songOpacity: Double
    let fontFamily: FontFamily
    let maxTracks: Int = 10 // Max 10 tracks on shareable card
    
    // Sort tracks chronologically (earliest first)
    private var sortedTracks: [SpotifyTrack] {
        tracks.sorted { $0.playedAt < $1.playedAt }
    }
    
    var body: some View {
        let displayTracks = Array(sortedTracks.prefix(maxTracks))
        let indexedTracks = Array(displayTracks.enumerated())
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) { // Even tighter spacing
                ForEach(indexedTracks, id: \.offset) { index, track in
                    AnimatedInstagramStyleTrackRow(track: track, index: index + 1, opacity: songOpacity, fontFamily: fontFamily)
                }
                
                // Always show "other songs" count when there are more tracks than displayed
                let remainingSongs = sortedTracks.count - displayTracks.count
                if remainingSongs > 0 {
                    HStack {
                        Text("+\(remainingSongs) other \(remainingSongs == 1 ? "song" : "songs")")
                            .font(fontFamily.customFont(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(0) // Hard corners
                        
                        Spacer()
                    }
                    .opacity(songOpacity)
                }
            }
            .padding(.leading, 30) // 30px from left edge
            
            Spacer() // Allow content to extend to the right
        }
    }
}

struct AnimatedInstagramStyleTrackRow: View {
    let track: SpotifyTrack
    let index: Int
    let opacity: Double
    let fontFamily: FontFamily
    
    var body: some View {
        HStack(spacing: 6) {
            Text(romanNumeral(for: index))
                .font(fontFamily.customFont(size: 10))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 16, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(fontFamily.customFont(size: 10))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.white)
                
                Text(track.artist)
                    .font(fontFamily.customFont(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            
            Spacer()
            
            if track.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.7))
        .cornerRadius(0) // Hard corners like Instagram
        .opacity(opacity)
    }
    
    private func romanNumeral(for number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let numerals = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        
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